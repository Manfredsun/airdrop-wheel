import Foundation
import Network
import Security

// MARK: - HTTP Framing & Decoder

public enum HTTPProtocolError: Error, Equatable {
    case malformed
    case tooLarge
    case unsupportedEncoding
    case incomplete
    case invalidPlist
}

public struct HTTPProbeResponse: Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
}

public struct DiscoverHTTPDecoder: Sendable {
    private var buffer = Data()
    public let maximumBody: Int

    public init(maximumBody: Int = 10_485_760) {
        self.maximumBody = maximumBody
    }

    public mutating func append(_ bytes: Data, eof: Bool = false) throws -> HTTPProbeResponse? {
        guard bytes.count <= maximumBody * 2 + 32768 - buffer.count else { throw HTTPProtocolError.tooLarge }
        buffer.append(bytes)

        guard let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > 32768 { throw HTTPProtocolError.tooLarge }
            if eof { throw HTTPProtocolError.incomplete }
            return nil
        }

        guard boundary.lowerBound <= 32768,
              let text = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) else {
            throw HTTPProtocolError.malformed
        }

        let lines = text.components(separatedBy: "\r\n")
        let statusParts = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard statusParts.count >= 2,
              ["HTTP/1.1", "HTTP/1.0"].contains(String(statusParts[0])),
              statusParts[1].count == 3,
              let status = Int(statusParts[1]),
              (100...599).contains(status) else {
            throw HTTPProtocolError.malformed
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            let key = parts[0].lowercased().trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = boundary.upperBound
        let bodyBytes = Data(buffer[bodyStart...])

        if let encoding = headers["transfer-encoding"], encoding.lowercased() == "chunked" {
            if let decoded = try decodeChunks(bodyBytes) {
                return HTTPProbeResponse(status: status, headers: headers, body: decoded)
            }
        } else if let lengthText = headers["content-length"] {
            guard let length = Int(lengthText), length <= maximumBody else {
                throw HTTPProtocolError.malformed
            }
            if bodyBytes.count >= length {
                return HTTPProbeResponse(status: status, headers: headers, body: Data(bodyBytes.prefix(length)))
            }
        } else if eof {
            guard bodyBytes.count <= maximumBody else { throw HTTPProtocolError.tooLarge }
            return HTTPProbeResponse(status: status, headers: headers, body: bodyBytes)
        }

        if eof { throw HTTPProtocolError.incomplete }
        return nil
    }

    private func decodeChunks(_ body: Data) throws -> Data? {
        var cursor = 0
        var output = Data()

        while cursor < body.count {
            guard let range = body.range(of: Data("\r\n".utf8), in: cursor..<body.count) else {
                return nil
            }
            guard range.lowerBound - cursor <= 1024,
                  let line = String(data: body[cursor..<range.lowerBound], encoding: .ascii),
                  let hex = line.split(separator: ";", omittingEmptySubsequences: false).first,
                  !hex.isEmpty, hex.allSatisfy({ $0.isHexDigit }),
                  let size = Int(hex, radix: 16) else {
                throw HTTPProtocolError.malformed
            }
            cursor = range.upperBound

            if size == 0 {
                if body.count - cursor >= 2 && body[cursor..<cursor+2] == Data("\r\n".utf8) {
                    return output
                }
                if body.range(of: Data("\r\n\r\n".utf8), in: cursor..<body.count) != nil {
                    return output
                }
                return nil
            }

            guard size <= maximumBody - output.count else { throw HTTPProtocolError.tooLarge }
            guard body.count - cursor >= size + 2 else { return nil }
            guard body[cursor+size..<cursor+size+2] == Data("\r\n".utf8) else {
                throw HTTPProtocolError.malformed
            }
            output.append(body[cursor..<cursor+size])
            cursor += size + 2
        }
        return nil
    }
}

// MARK: - Discover Request & Reply

public struct DiscoverReply {
    public static func request(senderName: String = Host.current().localizedName ?? "Mac",
                               senderID: String = makeSenderID()) throws -> Data {
        let plist: [String: Any] = [
            "Discoverable": true,
            "SenderID": senderID,
            "SenderModelName": "Mac",
            "SenderComputerName": senderName
        ]
        let body = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let header = "POST /Discover HTTP/1.1\r\nUser-Agent: AirDrop/1.0\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

    public static func makeSenderID() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuid.prefix(12))
    }
}

// MARK: - AirDrop /Ask Offer

public struct AirDropOffer {
    public let transferID: UUID
    public let payload: TransferPayload
    public let senderName: String
    public let senderModel: String
    public let senderID: String

    public init(
        transferID: UUID = UUID(),
        payload: TransferPayload,
        senderName: String = Host.current().localizedName ?? "Mac",
        senderModel: String = "Mac",
        senderID: String = DiscoverReply.makeSenderID()
    ) {
        self.transferID = transferID
        self.payload = payload
        self.senderName = senderName
        self.senderModel = senderModel
        self.senderID = senderID
    }

    public func request() throws -> Data {
        var plist: [String: Any] = [
            "TransferID": ["id": transferID.uuidString],
            "SenderComputerName": senderName,
            "SenderModelName": senderModel,
            "SenderID": senderID,
            "BundleID": "app.airdropwheel2.macos",
            "ConvertMediaFormats": false
        ]

        switch payload {
        case .files(let items):
            plist["TransferType"] = ["files": [:]]
            plist["Items"] = [String]()
            var fileDicts: [[String: Any]] = []

            for item in items {
                let dict: [String: Any] = [
                    "FileName": item.displayName,
                    "FileType": item.uti,
                    "FileSize": Int64(item.byteSize),
                    "FileBomPath": "./" + item.displayName,
                    "FileIsDirectory": item.isDirectory,
                    "ShouldConvertMediaFormats": false
                ]
                fileDicts.append(dict)
            }
            plist["Files"] = fileDicts

        case .links(let urls):
            plist["TransferType"] = ["links": [:]]
            plist["Files"] = [[String: Any]]()
            plist["Items"] = urls.map(\.absoluteString)
        }

        let body = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let header = "POST /Ask HTTP/1.1\r\nUser-Agent: AirDrop/1.0\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nConnection: keep-alive\r\n\r\n"
        return Data(header.utf8) + body
    }
}

// MARK: - CPIO & DVZip Streaming Archive Generator

public final class AirDropCPIOArchive {
    public static let maximumChunkSize: Int = 65_536

    public static func makeCPIOEntry(name: String, size: UInt64, mode: UInt32, inode: UInt32) -> Data {
        let nameBytes = Data(name.utf8) + Data([0])
        let fields: [UInt32] = [0, inode, mode, 0, 0, 1, 0, 0]
        let header = "070707" + fields.map { String(format: "%06o", $0) }.joined()
            + String(format: "%011o%06o%011llo", UInt32(nameBytes.count), size)
        return Data(header.utf8) + nameBytes
    }

    /// Builds the full streaming raw CPIO archive for a list of items.
    public static func buildArchive(for items: [ValidatedTransferItem]) throws -> Data {
        var archive = Data()
        var inodeCounter: UInt32 = 1

        // Root entry "."
        archive.append(makeCPIOEntry(name: ".", size: 0, mode: 0o40755, inode: inodeCounter))
        inodeCounter += 1

        for item in items {
            if item.isDirectory {
                try appendDirectory(item.url, relativePrefix: "./" + item.displayName, to: &archive, inodeCounter: &inodeCounter)
            } else {
                let fileData = try Data(contentsOf: item.url, options: .mappedIfSafe)
                archive.append(makeCPIOEntry(name: "./" + item.displayName, size: UInt64(fileData.count), mode: 0o100644, inode: inodeCounter))
                archive.append(fileData)
                inodeCounter += 1
            }
        }

        // Trailer
        archive.append(makeCPIOEntry(name: "TRAILER!!!", size: 0, mode: 0, inode: inodeCounter))
        return archive
    }

    private static func appendDirectory(_ dirURL: URL, relativePrefix: String, to archive: inout Data, inodeCounter: inout UInt32) throws {
        archive.append(makeCPIOEntry(name: relativePrefix, size: 0, mode: 0o40755, inode: inodeCounter))
        inodeCounter += 1

        let contents = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
        for childURL in contents {
            let childName = childURL.lastPathComponent
            let childRel = relativePrefix + "/" + childName
            let vals = try childURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if vals.isDirectory == true {
                try appendDirectory(childURL, relativePrefix: childRel, to: &archive, inodeCounter: &inodeCounter)
            } else {
                let childData = try Data(contentsOf: childURL, options: .mappedIfSafe)
                archive.append(makeCPIOEntry(name: childRel, size: UInt64(childData.count), mode: 0o100644, inode: inodeCounter))
                archive.append(childData)
                inodeCounter += 1
            }
        }
    }

    /// Splits archive into DVZip stored chunks (4-byte length header with high bit 0x80000000).
    public static func dvzipChunks(from rawArchive: Data) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        while offset < rawArchive.count {
            let len = min(maximumChunkSize, rawArchive.count - offset)
            let slice = rawArchive.subdata(in: offset..<offset+len)
            var header = (UInt32(len) | 0x8000_0000).bigEndian
            let chunkData = withUnsafeBytes(of: &header) { Data($0) } + slice
            chunks.append(chunkData)
            offset += len
        }
        return chunks
    }
}
