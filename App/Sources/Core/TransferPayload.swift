import Foundation
import UniformTypeIdentifiers

public enum PayloadValidationError: Error, Equatable {
    case empty
    case unreadable(String)
    case unsupportedScheme(String)
    case icloudPlaceholder(String)
    case invalidDirectory(String)

    public var message: String {
        switch self {
        case .empty:
            return "未選取任何檔案或連結。"
        case .unreadable(let name):
            return "無法讀取「\(name)」。請檢查檔案存取權限。"
        case .unsupportedScheme(let scheme):
            return "不支援的網址協定（\(scheme)）。AirDrop 僅支援 http 或 https 連結。"
        case .icloudPlaceholder(let name):
            return "「\(name)」仍在 iCloud 雲端尚未下載至本機。請先在 Finder 下載後再傳送。"
        case .invalidDirectory(let name):
            return "資料夾「\(name)」包含無法讀取的內容或循環連結。"
        }
    }
}

public struct ValidatedTransferItem: Sendable, Equatable {
    public let url: URL
    public let displayName: String
    public let uti: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let byteSize: UInt64

    public init(
        url: URL,
        displayName: String? = nil,
        uti: String? = nil,
        isDirectory: Bool? = nil,
        isPackage: Bool? = nil,
        byteSize: UInt64? = nil
    ) {
        let stdURL = url.standardizedFileURL
        self.url = stdURL
        let resolvedName = displayName ?? stdURL.lastPathComponent
        self.displayName = resolvedName

        let values = try? stdURL.resourceValues(forKeys: [
            .contentTypeKey,
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .isRegularFileKey
        ])

        let isDir = isDirectory ?? (values?.isDirectory == true)
        let isPkg = isPackage ?? (values?.isPackage == true)
        self.isDirectory = isDir
        self.isPackage = isPkg

        if let uti {
            self.uti = uti
        } else if let contentType = values?.contentType?.identifier {
            self.uti = contentType
        } else if isDir && !isPkg {
            self.uti = UTType.folder.identifier
        } else if isPkg {
            self.uti = UTType.package.identifier
        } else if let type = UTType(filenameExtension: stdURL.pathExtension) {
            self.uti = type.identifier
        } else {
            self.uti = "public.data"
        }

        if let byteSize {
            self.byteSize = byteSize
        } else if isDir {
            self.byteSize = Self.calculateDirectorySize(at: stdURL)
        } else {
            self.byteSize = UInt64(values?.fileSize ?? 0)
        }
    }

    private static func calculateDirectorySize(at dirURL: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  vals.isSymbolicLink != true,
                  vals.isRegularFile == true,
                  let size = vals.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }
}

public enum TransferPayload: Sendable, Equatable {
    case files([ValidatedTransferItem])
    case links([URL])

    public var count: Int {
        switch self {
        case .files(let items): return items.count
        case .links(let urls): return urls.count
        }
    }

    public var isEmpty: Bool {
        count == 0
    }

    public var headline: String {
        switch self {
        case .files(let items):
            if items.count == 1 {
                return items[0].displayName
            }
            return "\(items.count) 個項目"
        case .links(let urls):
            if urls.count == 1 {
                return urls[0].host ?? urls[0].absoluteString
            }
            return "\(urls.count) 個連結"
        }
    }

    public var totalBytes: UInt64 {
        switch self {
        case .files(let items):
            return items.reduce(0) { $0 + $1.byteSize }
        case .links:
            return 0
        }
    }

    public var totalBytesText: String? {
        switch self {
        case .files:
            return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        case .links:
            return nil
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .files(let items):
            if items.count == 1 {
                let item = items[0]
                if item.isDirectory && !item.isPackage { return "folder" }
                if item.isPackage { return "shippingbox" }
                let uti = item.uti.lowercased()
                if uti.contains("image") || uti.contains("jpeg") || uti.contains("png") || uti.contains("heic") { return "photo" }
                if uti.contains("movie") || uti.contains("video") || uti.contains("mp4") || uti.contains("quicktime") { return "film" }
                if uti.contains("audio") || uti.contains("sound") || uti.contains("mp3") { return "music.note" }
                if uti.contains("pdf") { return "doc.richtext" }
                if uti.contains("archive") || uti.contains("zip") || uti.contains("tar") || uti.contains("disk-image") { return "doc.zipper" }
                return "doc"
            }
            return "doc.on.doc"
        case .links:
            return "link"
        }
    }

    public var firstURL: URL? {
        switch self {
        case .files(let items): return items.first?.url
        case .links(let urls): return urls.first
        }
    }

    public var allURLs: [URL] {
        switch self {
        case .files(let items): return items.map(\.url)
        case .links(let urls): return urls
        }
    }
}

public enum TransferPayloadValidator {
    public static func validate(urls: [URL]) -> Result<TransferPayload, PayloadValidationError> {
        guard !urls.isEmpty else { return .failure(.empty) }

        // Check if all are web links
        let webLinks = urls.filter {
            let scheme = $0.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }

        if webLinks.count == urls.count {
            return .success(.links(webLinks))
        }

        // If there's an unsupported non-file scheme
        for url in urls {
            if let scheme = url.scheme?.lowercased(), scheme != "file", scheme != "http", scheme != "https" {
                return .failure(.unsupportedScheme(scheme))
            }
        }

        var items: [ValidatedTransferItem] = []
        for rawURL in urls {
            let fileURL = rawURL.standardizedFileURL
            let path = fileURL.path

            guard FileManager.default.fileExists(atPath: path) else {
                return .failure(.unreadable(fileURL.lastPathComponent))
            }
            guard FileManager.default.isReadableFile(atPath: path) else {
                return .failure(.unreadable(fileURL.lastPathComponent))
            }

            // Detect iCloud dataless placeholder
            if let values = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               let status = values.ubiquitousItemDownloadingStatus,
               status == .notDownloaded {
                return .failure(.icloudPlaceholder(fileURL.lastPathComponent))
            }

            // Pre-flight read check to trigger macOS TCC consent prompt early (e.g. ~/Documents, ~/Desktop)
            let accessStarted = fileURL.startAccessingSecurityScopedResource()
            if let handle = try? FileHandle(forReadingFrom: fileURL) {
                try? handle.close()
            }
            if accessStarted {
                fileURL.stopAccessingSecurityScopedResource()
            }

            items.append(ValidatedTransferItem(url: fileURL))
        }

        return .success(.files(items))
    }
}
