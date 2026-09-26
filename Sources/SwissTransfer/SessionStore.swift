import Foundation

struct PersistedSession: Codable, Sendable {
    var cookies: [String: String]
    var version: String
    var email: String
    var emailValidationId: String
    var validated: Bool
}

enum SessionStore {
    struct Snapshot: Sendable {
        var email: String
        var validationId: String
        var validated: Bool
    }

    static var fileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwissTransfer/session.json", isDirectory: false)
    }

    static func load() -> PersistedSession? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }

    static func peek() -> Snapshot {
        guard let saved = load() else { return Snapshot(email: "", validationId: "", validated: false) }
        return Snapshot(
            email: saved.email,
            validationId: saved.emailValidationId,
            validated: saved.validated
        )
    }

    static func save(_ session: PersistedSession) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
