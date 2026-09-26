import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Step: Equatable {
        case welcome
        case email
        case code
        case drop
        case compose
        case uploading
        case done
    }

    @Published var step: Step
    @Published var email: String
    @Published var code = ""
    @Published var message = ""
    @Published var password = ""
    @Published var protect = false
    @Published var days: Int
    @Published var maxDownloads: Int
    @Published var files: [LocalFile] = []
    @Published var banner: String?
    @Published var busy = false
    @Published var isTargeted = false
    @Published var progress = UploadProgress.idle
    @Published var downloadURL: String?
    @Published var linkCopied = false
    @Published private(set) var hasToken: Bool

    private let client = SwissTransferClient()
    private var uploadTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    private init() {
        let saved = SessionStore.peek()
        let storedDays = UserDefaults.standard.integer(forKey: "expiresInDays")
        let storedDownloads = UserDefaults.standard.integer(forKey: "maxDownloads")
        days = [1, 3, 7, 15, 30].contains(storedDays) ? storedDays : 30
        maxDownloads = [1, 20, 100, 200, 250].contains(storedDownloads) ? storedDownloads : 250
        if saved.validated, !saved.validationId.isEmpty {
            email = saved.email
            hasToken = true
            step = .drop
        } else if !saved.validationId.isEmpty, !saved.email.isEmpty {
            email = saved.email
            hasToken = false
            step = .code
        } else {
            email = saved.email.isEmpty
                ? (UserDefaults.standard.string(forKey: "draftEmail") ?? "")
                : saved.email
            hasToken = false
            step = .welcome
        }
    }

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    var canTransfer: Bool {
        !files.isEmpty && totalSize <= Format.maxBytes && step != .uploading && !busy
    }

    func beginAuthentication() {
        banner = nil
        step = .email
    }

    func sendCode() async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        email = address
        UserDefaults.standard.set(address, forKey: "draftEmail")
        guard address.contains("@"), address.contains("."), !address.contains(" ") else {
            banner = "Entrez une adresse e-mail valide."
            return
        }
        guard !busy else { return }
        busy = true
        banner = nil
        defer { busy = false }
        do {
            try await client.requestCode(for: address)
            code = ""
            step = .code
        } catch {
            banner = error.localizedDescription
        }
    }

    func confirm() async {
        let token = String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
        guard token.count == 6 else {
            banner = "Le code fait 6 caractères."
            return
        }
        guard !busy else { return }
        busy = true
        banner = nil
        defer { busy = false }
        do {
            try await client.confirm(code: token)
            hasToken = true
            code = ""
            banner = nil
            step = files.isEmpty ? .drop : .compose
        } catch {
            banner = error.localizedDescription
        }
    }

    func signOut() async {
        uploadTask?.cancel()
        uploadTask = nil
        await client.forget()
        hasToken = false
        code = ""
        banner = nil
        downloadURL = nil
        progress = .idle
        step = .welcome
    }

    func pickFiles() {
        guard step != .uploading else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "Ajouter"
        panel.message = "Fichiers à envoyer avec SwissTransfer"
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    func importFiles(_ urls: [URL]) {
        guard step != .uploading else {
            banner = "Un envoi est déjà en cours."
            return
        }
        if step == .done {
            downloadURL = nil
            progress = .idle
        }

        var directories = 0
        var added = 0
        var names = Set(files.map(\.name))
        for url in urls {
            if files.contains(where: { $0.url.path == url.path }) { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                directories += 1
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let base = url.lastPathComponent
            let name = uniqueName(base, used: &names)
            names.insert(name)
            files.append(LocalFile(url: url, name: name, size: Int64(values?.fileSize ?? 0)))
            added += 1
        }

        if added == 0, directories > 0, files.isEmpty {
            banner = "Choisissez des fichiers, pas un dossier."
            return
        }
        guard !files.isEmpty else { return }

        if totalSize > Format.maxBytes {
            banner = "SwissTransfer accepte 50 Go au maximum par transfert."
        } else if added > 0 {
            banner = nil
        }

        if hasToken {
            step = .compose
        }
    }

    func remove(_ file: LocalFile) {
        guard step != .uploading else { return }
        files.removeAll { $0.id == file.id }
        if totalSize <= Format.maxBytes, banner == "SwissTransfer accepte 50 Go au maximum par transfert." {
            banner = nil
        }
        if files.isEmpty, step == .compose {
            step = .drop
        }
    }

    func transfer() {
        guard canTransfer else { return }
        UserDefaults.standard.set(days, forKey: "expiresInDays")
        UserDefaults.standard.set(maxDownloads, forKey: "maxDownloads")
        let request = UploadRequest(
            files: files,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            password: protect ? password : "",
            days: days,
            maxDownloads: maxDownloads
        )
        banner = nil
        progress = UploadProgress(
            detail: "Préparation…",
            bytesSent: 0,
            bytesTotal: totalSize,
            fileName: "",
            fileIndex: 0,
            fileCount: files.count
        )
        step = .uploading
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Envoi SwissTransfer"
        )
        uploadTask?.cancel()
        uploadTask = Task {
            defer { endActivity() }
            do {
                let url = try await client.upload(request) { value in
                    Task { @MainActor in
                        AppModel.shared.progress = value
                    }
                }
                downloadURL = url
                step = .done
                banner = nil
            } catch is CancellationError {
                if step == .uploading { step = .compose }
                banner = "Envoi annulé."
            } catch TransferError.needNewCode {
                hasToken = false
                step = .email
                banner = errorText(TransferError.needNewCode)
            } catch {
                if step == .uploading { step = .compose }
                banner = error.localizedDescription
            }
        }
    }

    func cancelUpload() {
        uploadTask?.cancel()
        Task { await client.cancelUpload() }
    }

    func copyLink() {
        guard let downloadURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(downloadURL, forType: .string)
        linkCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            linkCopied = false
        }
    }

    func openLink() {
        guard let downloadURL, let url = URL(string: downloadURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func newTransfer() {
        files = []
        message = ""
        password = ""
        protect = false
        downloadURL = nil
        banner = nil
        progress = .idle
        step = .drop
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }

    private func errorText(_ error: TransferError) -> String {
        error.localizedDescription
    }

    private func uniqueName(_ base: String, used: inout Set<String>) -> String {
        if !used.contains(base) { return base }
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            if !used.contains(candidate) { return candidate }
            index += 1
        }
    }
}
