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
        if (100...199).contains(status) {
            // Interim informational response (e.g. 100 Continue); discard header block and keep reading
            buffer.removeSubrange(..<bodyStart)
            return try append(Data(), eof: eof)
        }

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
            "TransferID": ["id": transferID.uuidString.uppercased()],
            "SenderComputerName": senderName,
            "SenderModelName": senderModel,
            "SenderID": senderID,
            "BundleID": "com.apple.finder",
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

// MARK: - CPIO Streaming Archive Generator (POSIX ODC Format for Apple BOMCopier)

public final class AirDropCPIOArchive {
    public static let maximumChunkSize: Int = 65_536

    /// Creates an Apple-compatible POSIX ODC (070707) CPIO entry (exact 76-byte fixed octal header).
    public static func odcEntry(name: String, data: Data, mode: UInt32, ino: UInt32, mtime: UInt64) -> Data {
        let nameBytes = Data(name.utf8) + Data([0])
        let fields: [UInt32] = [0, ino, mode, 0, 0, 1, 0]
        var header = "070707" + fields.map { String(format: "%06o", $0) }.joined()
        header += String(format: "%011llo%06o%011llo", mtime, UInt32(nameBytes.count), UInt64(data.count))
        assert(header.utf8.count == 76, "ODC header must be exactly 76 ASCII bytes")
        return Data(header.utf8) + nameBytes + data
    }

    /// Builds the full streaming raw POSIX ODC CPIO archive for a list of items.
    public static func buildArchive(for items: [ValidatedTransferItem]) throws -> Data {
        var archive = Data()
        var inodeCounter: UInt32 = 1
        let mtime = UInt64(Date().timeIntervalSince1970)

        // 1. Root entry "."
        archive.append(odcEntry(name: ".", data: Data(), mode: 0o40755, ino: inodeCounter, mtime: mtime))
        inodeCounter += 1

        // 2. Add each item
        for item in items {
            let accessStarted = item.url.startAccessingSecurityScopedResource()
            defer {
                if accessStarted { item.url.stopAccessingSecurityScopedResource() }
            }

            if item.isDirectory {
                try appendDirectory(item.url, relativePrefix: "./" + item.displayName, to: &archive, inodeCounter: &inodeCounter, mtime: mtime)
            } else {
                let fileData = try Data(contentsOf: item.url, options: .mappedIfSafe)
                archive.append(odcEntry(name: "./" + item.displayName, data: fileData, mode: 0o100644, ino: inodeCounter, mtime: mtime))
                inodeCounter += 1
            }
        }

        // 3. Trailer "TRAILER!!!"
        archive.append(odcEntry(name: "TRAILER!!!", data: Data(), mode: 0, ino: inodeCounter, mtime: mtime))

        // 4. Pad entire archive to 512-byte block boundary
        let blockPad = (512 - (archive.count % 512)) % 512
        if blockPad > 0 {
            archive.append(Data(repeating: 0, count: blockPad))
        }

        return archive
    }

    private static func appendDirectory(_ dirURL: URL, relativePrefix: String, to archive: inout Data, inodeCounter: inout UInt32, mtime: UInt64) throws {
        archive.append(odcEntry(name: relativePrefix, data: Data(), mode: 0o40755, ino: inodeCounter, mtime: mtime))
        inodeCounter += 1

        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        for childURL in contents {
            let childName = childURL.lastPathComponent
            let childRel = relativePrefix + "/" + childName
            let vals = try childURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if vals.isDirectory == true {
                try appendDirectory(childURL, relativePrefix: childRel, to: &archive, inodeCounter: &inodeCounter, mtime: mtime)
            } else {
                let childData = try Data(contentsOf: childURL, options: .mappedIfSafe)
                archive.append(odcEntry(name: childRel, data: childData, mode: 0o100644, ino: inodeCounter, mtime: mtime))
                inodeCounter += 1
            }
        }
    }

    /// Splits archive into clean streaming chunk slices without adding fake corruption headers.
    public static func makeStreamChunks(from rawArchive: Data, chunkSize: Int = maximumChunkSize) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        while offset < rawArchive.count {
            let len = min(chunkSize, rawArchive.count - offset)
            chunks.append(rawArchive.subdata(in: offset..<offset+len))
            offset += len
        }
        return chunks.isEmpty ? [rawArchive] : chunks
    }

    /// Backward-compatible alias for chunk slicing
    public static func dvzipChunks(from rawArchive: Data) -> [Data] {
        makeStreamChunks(from: rawArchive)
    }
}
