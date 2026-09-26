import Foundation

struct LocalFile: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let size: Int64

    init(url: URL, name: String, size: Int64) {
        self.url = url
        self.name = name
        self.size = size
        self.id = url.path
    }
}

struct UploadRequest: Sendable {
    var files: [LocalFile]
    var email: String
    var message: String
    var password: String
    var days: Int
    var maxDownloads: Int
}

struct UploadProgress: Sendable, Equatable {
    var detail: String
    var bytesSent: Int64
    var bytesTotal: Int64
    var fileName: String
    var fileIndex: Int
    var fileCount: Int

    static let idle = UploadProgress(
        detail: "",
        bytesSent: 0,
        bytesTotal: 0,
        fileName: "",
        fileIndex: 0,
        fileCount: 0
    )

    var fraction: Double {
        guard bytesTotal > 0 else { return 0 }
        return min(1, Double(bytesSent) / Double(bytesTotal))
    }
}

enum TransferError: Error, Sendable {
    case message(String)
    case retryable(String)
    case needNewCode
    case altcha
    case http(Int)
}

extension TransferError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .message(let text), .retryable(let text):
            return text
        case .needNewCode:
            return "La confirmation e-mail n’est plus valable. Demandez un nouveau code."
        case .altcha:
            return "La vérification anti-robot a été refusée."
        case .http(let status):
            return "SwissTransfer a répondu \(status)."
        }
    }

    var retries: Bool {
        if case .retryable = self { return true }
        if case .http(let status) = self { return status >= 500 }
        return false
    }
}

enum Format {
    static let maxBytes: Int64 = 53_687_091_200

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    static func count(_ value: Int) -> String {
        value <= 1 ? "1 fichier" : "\(value) fichiers"
    }
}
