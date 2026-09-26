import CryptoKit
import Foundation
import os

/// Client HTTP du flux décrit dans le backend : session, code e-mail, Altcha, morceaux de 50 Mio.
actor SwissTransferClient {
    private func apiURL(_ path: String) -> URL {
        URL(string: "https://www.swisstransfer.com/api/1/\(path)")!
    }
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    private let chunkSize = 52_428_800
    private let log = Logger(subsystem: "com.selim.swisstransfer", category: "api")

    private let jar: CookieJar
    private let session: URLSession
    private var version = ""
    private var email = ""
    private var emailValidationId = ""
    private var validated = false
    private var refreshedThisLaunch = false

    private var flight = InFlight()
    private var progressHandler: (@Sendable (UploadProgress) -> Void)?
    private var bytesSent: Int64 = 0
    private var bytesTotal: Int64 = 0
    private var detail = ""
    private var fileName = ""
    private var fileIndex = 0
    private var fileCount = 0
    private var lastReport = ContinuousClock.now

    init() {
        let jar = CookieJar()
        let delegate = SessionDelegate(jar: jar)
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 20 * 60
        self.jar = jar
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        if let saved = SessionStore.load() {
            jar.load(saved.cookies)
            version = saved.version
            email = saved.email
            emailValidationId = saved.emailValidationId
            validated = saved.validated
        }
    }

    func requestCode(for address: String) async throws {
        _ = try await ensureSession()
        let (status, data, _) = try await send(
            url: apiURL("email-validations"),
            method: "POST",
            json: ["email": address]
        )
        let body = try parseJSON(data)
        if status >= 400 || body["result"] as? String == "error" {
            throw TransferError.message(friendly(body, fallback: "Impossible d’envoyer le code."))
        }
        guard let id = stringField((body["data"] as? [String: Any])?["id"]) else {
            throw TransferError.message("SwissTransfer n’a pas renvoyé d’identifiant de confirmation.")
        }
        email = address
        emailValidationId = id
        validated = false
        save()
    }

    func confirm(code: String) async throws {
        let id = emailValidationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw TransferError.message("Demandez un code avant de le confirmer.")
        }
        _ = try await ensureSession()
        let token = code.filter { $0.isLetter || $0.isNumber }
        let (status, data, _) = try await send(
            url: apiURL("email-validations/\(pathComponent(id))/confirm"),
            method: "POST",
            json: ["token": token]
        )
        let body = try parseJSON(data)
        let errorCode = (body["error"] as? [String: Any])?["code"] as? String
        if errorCode == "invalid_validation_token" || status >= 400 || body["result"] as? String == "error" {
            throw TransferError.message(friendly(body, fallback: "Ce code n’est pas valide."))
        }
        validated = true
        save()
    }

    func cancelUpload() {
        flight.cancel()
    }

    func upload(_ request: UploadRequest, onProgress: @escaping @Sendable (UploadProgress) -> Void) async throws -> String {
        flight = InFlight()
        progressHandler = onProgress
        bytesSent = 0
        bytesTotal = request.files.reduce(0) { $0 + $1.size }
        fileCount = request.files.count
        detail = "Ouverture de la session…"
        report(force: true)
        defer { progressHandler = nil }

        guard validated, !emailValidationId.isEmpty else { throw TransferError.needNewCode }
        let outcome = try await ensureSession()
        guard outcome == .ready, validated, !emailValidationId.isEmpty else {
            throw TransferError.needNewCode
        }

        detail = "Vérification anti-robot…"
        report(force: true)
        await Task.yield()
        var altcha = try await solveAltcha()
        let created: [String: Any]
        do {
            created = try await createTransfer(request, altcha: altcha)
        } catch TransferError.altcha {
            detail = "Nouvelle vérification anti-robot…"
            report(force: true)
            altcha = try await solveAltcha()
            created = try await createTransfer(request, altcha: altcha)
        }

        let transferId = stringField(created["id"]) ?? ""
        let remoteFiles = created["files"] as? [[String: Any]] ?? []
        guard !transferId.isEmpty, !remoteFiles.isEmpty else {
            throw TransferError.message("SwissTransfer n’a pas accepté les fichiers.")
        }

        for (index, file) in request.files.enumerated() {
            try throwIfUploadCancelled()
            let remote = remoteFiles.first { stringField($0["path"]) == file.name } ?? remoteFiles[index]
            guard let fileId = stringField(remote["id"]) else {
                throw TransferError.message("SwissTransfer n’a pas reconnu \(file.name).")
            }
            fileName = file.name
            fileIndex = index + 1
            try await uploadFile(file, transferId: transferId, fileId: fileId)
        }

        detail = "Finalisation…"
        report(force: true)
        let link = try await finalize(transferId)
        save()
        detail = "Terminé"
        bytesSent = bytesTotal
        report(force: true)
        return link
    }

    // MARK: - Session

    private enum SessionOutcome {
        case ready
        case fresh
    }

    private func ensureSession() async throws -> SessionOutcome {
        if jar.hasXSRF, refreshedThisLaunch, !version.isEmpty {
            return .ready
        }

        if jar.hasXSRF {
            do {
                let html = try await homeHTML()
                let parsed = inertiaVersion(in: html)
                if !parsed.isEmpty { version = parsed }
                refreshedThisLaunch = true
                save()
                return .ready
            } catch let error as TransferError where error.retries == false && isRejected(error) {
                jar.reset()
                version = ""
            }
        }

        let html = try await homeHTML()
        guard jar.hasXSRF else {
            throw TransferError.message("Impossible d’ouvrir une session SwissTransfer.")
        }
        version = inertiaVersion(in: html)
        validated = false
        emailValidationId = ""
        refreshedThisLaunch = true
        save()
        return .fresh
    }

    private func isRejected(_ error: TransferError) -> Bool {
        if case .http = error { return true }
        return false
    }

    private func homeHTML() async throws -> String {
        let url = URL(string: "https://www.swisstransfer.com/en")!
        return try await withRetry {
            let (status, data, _) = try await self.send(
                url: url,
                method: "GET",
                extra: ["Accept": "text/html,application/xhtml+xml"]
            )
            guard status < 400 else { throw TransferError.http(status) }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func save() {
        SessionStore.save(PersistedSession(
            cookies: jar.dump(),
            version: version,
            email: email,
            emailValidationId: emailValidationId,
            validated: validated
        ))
    }

    func forget() {
        flight.cancel()
        jar.reset()
        version = ""
        email = ""
        emailValidationId = ""
        validated = false
        refreshedThisLaunch = false
        SessionStore.clear()
    }

    // MARK: - Transfer

    private func createTransfer(_ request: UploadRequest, altcha: String) async throws -> [String: Any] {
        try throwIfUploadCancelled()
        detail = "Création du transfert…"
        report(force: true)
        var extra: [String: String] = [:]
        if !version.isEmpty { extra["X-Inertia-Version"] = version }
        let files: [[String: Any]] = request.files.map {
            ["path": $0.name, "size": NSNumber(value: $0.size), "mime_type": NSNull()]
        }
        let payload: [String: Any] = [
            "method": "link",
            "title": "",
            "recipients": [String](),
            "email": request.email,
            "message": request.message,
            "password": request.password,
            "language": "fr",
            "max_download": request.maxDownloads,
            "expires_in_days": request.days,
            "files": files,
            "altcha": altcha,
            "email_validation_id": emailValidationId
        ]
        let (status, data, _) = try await send(url: apiURL("transfers"), method: "POST", json: payload, extra: extra)
        let body = (try? parseJSON(data)) ?? [:]
        let blob = String(data: data, encoding: .utf8) ?? ""
        if body["result"] as? String == "error" || status >= 400 {
            log.error("create transfer \(status, privacy: .public) \(blob.prefix(400), privacy: .public)")
            if rejected(body, field: "altcha") { throw TransferError.altcha }
            if blob.contains("verified_email_check_failed") || blob.contains("email_not_verified") {
                validated = false
                emailValidationId = ""
                save()
                throw TransferError.needNewCode
            }
            throw TransferError.message(friendly(body, fallback: "Le transfert a été refusé (\(status))."))
        }
        if let dataObject = body["data"] as? [String: Any] { return dataObject }
        return body
    }

    private func uploadFile(_ file: LocalFile, transferId: String, fileId: String) async throws {
        let chunks = chunkPlan(file.size)
        let direct = chunks.count <= 1
        var etags: [[String: Any]] = []
        for chunk in chunks {
            try throwIfUploadCancelled()
            detail = chunks.count <= 1
                ? "Envoi de \(file.name)"
                : "Envoi de \(file.name) · morceau \(chunk.index + 1)/\(chunks.count)"
            report(force: true)
            let endpoint = direct
                ? "transfers/\(pathComponent(transferId))/files/\(pathComponent(fileId))"
                : "transfers/\(pathComponent(transferId))/files/\(pathComponent(fileId))/chunks/\(chunk.index + 1)"
            let sentBefore = bytesSent
            let etag = try await withRetry(attempts: 4) {
                try self.throwIfUploadCancelled()
                self.bytesSent = sentBefore
                self.report(force: true)
                let uploadURL = try await self.presign(url: self.apiURL(endpoint))
                let data = try self.read(file: file, offset: chunk.offset, size: chunk.size)
                return try await self.put(data, to: uploadURL)
            }
            etags.append(["chunk_index": chunk.index + 1, "etag": etag])
            bytesSent = sentBefore + Int64(chunk.size)
            report(force: true)
        }

        detail = "Assemblage de \(file.name)…"
        report(force: true)
        let body: Any
        if direct {
            body = [String: Any]()
        } else {
            body = ["etags": etags]
        }
        let (status, data, _) = try await send(
            url: apiURL("transfers/\(pathComponent(transferId))/files/\(pathComponent(fileId))"),
            method: "PATCH",
            json: body
        )
        guard status < 400 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            log.error("assemble \(status, privacy: .public) \(text.prefix(300), privacy: .public)")
            throw TransferError.message("Impossible d’assembler \(file.name).")
        }
    }

    private func presign(url: URL) async throws -> URL {
        let (status, data, _) = try await send(url: url, method: "POST", json: [String: Any]())
        let body = try parseJSON(data)
        if status >= 500 { throw TransferError.retryable("Lien d’envoi indisponible (\(status)).") }
        if status >= 400 || body["result"] as? String == "error" {
            throw TransferError.message(friendly(body, fallback: "Impossible de préparer l’envoi."))
        }
        guard let raw = (body["data"] as? [String: Any])?["url"] as? String, let uploadURL = URL(string: raw) else {
            throw TransferError.retryable("Lien d’envoi manquant.")
        }
        return uploadURL
    }

    private func finalize(_ transferId: String) async throws -> String {
        var last = TransferError.message("Impossible de terminer le transfert.")
        for attempt in 1...5 {
            try throwIfUploadCancelled()
            do {
                let (status, data, _) = try await send(
                    url: apiURL("transfers/\(pathComponent(transferId))"),
                    method: "PATCH",
                    json: ["status": "completed"]
                )
                let text = String(data: data, encoding: .utf8) ?? ""
                if text.contains("transfer_incomplete") {
                    throw TransferError.message("Le transfert est incomplet. Réessayez l’envoi.")
                }
                if status >= 500 {
                    throw TransferError.retryable("Finalisation indisponible (\(status)).")
                }
                if status >= 400 {
                    throw TransferError.message("Impossible de terminer le transfert (\(status)).")
                }
                let body = try parseJSON(data)
                if let url = downloadLink(from: body) { return url }
                throw TransferError.message("SwissTransfer n’a pas renvoyé de lien.")
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as TransferError where error.retries == false {
                throw error
            } catch {
                last = (error as? TransferError) ?? .message(error.localizedDescription)
                if attempt == 5 { break }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
            }
        }
        throw last
    }

    private func downloadLink(from body: [String: Any]) -> String? {
        let data = body["data"] as? [String: Any]
        let link = data?["link"] as? [String: Any]
        if let url = link?["download_url"] as? String, !url.isEmpty { return url }
        if let id = stringField(link?["id"]) { return "https://www.swisstransfer.com/dl/\(id)" }
        return nil
    }

    // MARK: - HTTP

    private func send(
        url: URL,
        method: String,
        json: Any? = nil,
        extra: [String: String] = [:],
        timeout: TimeInterval = 60,
        redirects: Int = 0
    ) async throws -> (Int, Data, HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        var headers = [
            "User-Agent": userAgent,
            "Accept-Language": "en-GB,en;q=0.9",
            "Origin": "https://www.swisstransfer.com",
            "Referer": "https://www.swisstransfer.com/en"
        ]
        if let cookie = jar.header() { headers["Cookie"] = cookie }
        if let token = jar.xsrf() { headers["X-XSRF-TOKEN"] = token }
        if let json {
            headers["Content-Type"] = "application/json"
            headers["Accept"] = "application/json"
            headers["X-Requested-With"] = "XMLHttpRequest"
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        for (key, value) in extra { headers[key] = value }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || flight.cancelled { throw CancellationError() }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw TransferError.message("Réponse invalide de SwissTransfer.")
        }
        jar.absorb(http)
        if (300..<400).contains(http.statusCode),
           redirects < 8,
           let location = http.value(forHTTPHeaderField: "Location"),
           let next = URL(string: location, relativeTo: url)?.absoluteURL {
            return try await send(
                url: next,
                method: "GET",
                extra: ["Accept": extra["Accept"] ?? "text/html,application/xhtml+xml"],
                timeout: timeout,
                redirects: redirects + 1
            )
        }
        return (http.statusCode, data, http)
    }

    private func put(_ data: Data, to url: URL) async throws -> String {
        let flight = self.flight
        let agent = userAgent
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ChunkUploader(flight: flight, continuation: continuation) { delta in
                    Task { await self.addBytes(delta) }
                }.start(url: url, data: data, userAgent: agent)
            }
        } onCancel: {
            flight.cancel()
        }
    }

    private func addBytes(_ delta: Int64) {
        guard !flight.cancelled else { return }
        bytesSent += delta
        report()
    }

    private func withRetry<T: Sendable>(
        attempts: Int = 3,
        _ work: nonisolated(nonsending) () async throws -> T
    ) async throws -> T {
        var last: Error = TransferError.message("Échec réseau.")
        for attempt in 1...attempts {
            try Task.checkCancellation()
            do {
                return try await work()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                last = error
                guard Self.retries(error), attempt < attempts else { throw error }
                try await Task.sleep(nanoseconds: UInt64(600 * (1 << (attempt - 1))) * 1_000_000)
            }
        }
        throw last
    }

    private static func retries(_ error: Error) -> Bool {
        if let transfer = error as? TransferError { return transfer.retries }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .resourceUnavailable, .badServerResponse,
                 .cannotParseResponse:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func throwIfUploadCancelled() throws {
        try Task.checkCancellation()
        if flight.cancelled { throw CancellationError() }
    }

    private func report(force: Bool = false) {
        let now = ContinuousClock.now
        if !force, now - lastReport < .milliseconds(80) { return }
        lastReport = now
        progressHandler?(UploadProgress(
            detail: detail,
            bytesSent: bytesSent,
            bytesTotal: bytesTotal,
            fileName: fileName,
            fileIndex: fileIndex,
            fileCount: fileCount
        ))
    }

    private func read(file: LocalFile, offset: Int64, size: Int) throws -> Data {
        if size == 0 { return Data() }
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: size) ?? Data()
        guard data.count == size else {
            throw TransferError.message("Lecture incomplète de \(file.name).")
        }
        return data
    }

    private func chunkPlan(_ size: Int64) -> [(index: Int, offset: Int64, size: Int)] {
        if size == 0 { return [(0, 0, 0)] }
        var chunks: [(index: Int, offset: Int64, size: Int)] = []
        var offset: Int64 = 0
        var index = 0
        while offset < size {
            let length = min(Int64(chunkSize), size - offset)
            chunks.append((index, offset, Int(length)))
            offset += length
            index += 1
        }
        return chunks
    }

    // MARK: - Altcha

    private func solveAltcha() async throws -> String {
        let (status, data, _) = try await send(
            url: apiURL("altcha-challenge"),
            method: "GET",
            extra: ["Accept": "application/json", "X-Requested-With": "XMLHttpRequest"]
        )
        guard status < 400 else { throw TransferError.message("Impossible de récupérer la vérification anti-robot.") }
        let body = try parseJSON(data)
        let algorithm = stringField(body["algorithm"]) ?? "SHA-256"
        let challenge = stringField(body["challenge"]) ?? ""
        let salt = stringField(body["salt"]) ?? ""
        let signature = stringField(body["signature"]) ?? ""
        let maxNumber = intField(body["maxNumber"]) ?? intField(body["maxnumber"]) ?? 1_000_000
        guard !challenge.isEmpty, !salt.isEmpty, !signature.isEmpty else {
            throw TransferError.message("Vérification anti-robot incomplète.")
        }
        return try await Task.detached(priority: .userInitiated) {
            try Altcha.solve(
                algorithm: algorithm,
                challenge: challenge,
                salt: salt,
                signature: signature,
                maxNumber: maxNumber
            )
        }.value
    }

    // MARK: - JSON

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransferError.message("Réponse inattendue de SwissTransfer.")
        }
        return object
    }

    private func friendly(_ body: [String: Any], fallback: String) -> String {
        let code = (body["error"] as? [String: Any])?["code"] as? String
        switch code {
        case "email_validation_rate_limit_error", "email_validation_request_locked":
            return "Trop de codes ont été demandés. Attendez un moment avant de réessayer."
        case "invalid_validation_token":
            return "Ce code n’est pas valide. Vérifiez le dernier e-mail reçu."
        default:
            break
        }
        if let error = body["error"] as? [String: Any] {
            if let errors = error["errors"] as? [[String: Any]], !errors.isEmpty {
                let text = errors.compactMap { $0["description"] as? String }.joined(separator: " ")
                if !text.isEmpty { return text }
            }
            if let description = error["description"] as? String, !description.isEmpty, description != "Validation failed" {
                return description
            }
        }
        return fallback
    }

    private func rejected(_ body: [String: Any], field: String) -> Bool {
        let errors = (body["error"] as? [String: Any])?["errors"] as? [[String: Any]] ?? []
        return errors.contains { ($0["context"] as? [String: Any])?["attribute"] as? String == field }
    }
}

private enum Altcha {
    struct Payload: Encodable {
        var algorithm: String
        var challenge: String
        var number: Int
        var salt: String
        var signature: String
    }

    static func solve(algorithm: String, challenge: String, salt: String, signature: String, maxNumber: Int) throws -> String {
        let normalized = algorithm.uppercased().replacingOccurrences(of: "-", with: "")
        guard normalized == "SHA256" else {
            throw TransferError.message("Algorithme anti-robot non pris en charge.")
        }
        guard let expected = hex(challenge) else {
            throw TransferError.message("Défi anti-robot illisible.")
        }
        for number in 0...maxNumber {
            let digest = SHA256.hash(data: Data((salt + String(number)).utf8))
            if Data(digest) == expected {
                let payload = Payload(
                    algorithm: algorithm,
                    challenge: challenge,
                    number: number,
                    salt: salt,
                    signature: signature
                )
                let data = try JSONEncoder().encode(payload)
                return data.base64EncodedString()
            }
        }
        throw TransferError.message("Impossible de résoudre la vérification anti-robot.")
    }

    static func hex(_ value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

private func stringField(_ value: Any?) -> String? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

private func intField(_ value: Any?) -> Int? {
    switch value {
    case let number as Int:
        return number
    case let number as NSNumber:
        return number.intValue
    default:
        return nil
    }
}

private func pathComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
}

private func inertiaVersion(in html: String) -> String {
    guard let regex = try? NSRegularExpression(
        pattern: "<script[^>]*data-page=\"app\"[^>]*>(.*?)</script>",
        options: [.dotMatchesLineSeparators]
    ) else { return "" }
    let range = NSRange(html.startIndex..., in: html)
    guard let match = regex.firstMatch(in: html, options: [], range: range),
          match.numberOfRanges > 1,
          let slice = Range(match.range(at: 1), in: html),
          let object = try? JSONSerialization.jsonObject(with: Data(html[slice].utf8)) as? [String: Any]
    else { return "" }
    return object["version"] as? String ?? ""
}

private final class CookieJar: @unchecked Sendable {
    private let lock = NSLock()
    private var cookies: [String: String] = [:]

    var hasXSRF: Bool { value(for: "SWISSTRANSFER-API-XSRF-TOKEN") != nil }

    func header() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
    }

    func value(for name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cookies[name]
    }

    func xsrf() -> String? {
        guard let raw = value(for: "SWISSTRANSFER-API-XSRF-TOKEN") else { return nil }
        return raw.removingPercentEncoding ?? raw
    }

    func absorb(_ response: HTTPURLResponse) {
        guard let raw = response.allHeaderFields.first(where: {
            String(describing: $0.key).caseInsensitiveCompare("Set-Cookie") == .orderedSame
        }).map({ String(describing: $0.value) }) else { return }
        var found: [String: String] = [:]
        for line in splitSetCookie(raw) {
            let pair = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let name = pair[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair[pair.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { found[String(name)] = String(value) }
        }
        guard !found.isEmpty else { return }
        lock.lock()
        for (key, value) in found { cookies[key] = value }
        lock.unlock()
    }

    func dump() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return cookies
    }

    func load(_ data: [String: String]) {
        lock.lock()
        cookies = data
        lock.unlock()
    }

    func reset() {
        lock.lock()
        cookies.removeAll()
        lock.unlock()
    }
}

private func splitSetCookie(_ header: String) -> [String] {
    let chars = Array(header)
    var parts: [String] = []
    var current = ""
    var index = 0
    while index < chars.count {
        if chars[index] == "," {
            var next = index + 1
            while next < chars.count, chars[next] == " " { next += 1 }
            var end = next
            while end < chars.count, chars[end] != ";", chars[end] != ",", chars[end] != "=" {
                end += 1
            }
            if end < chars.count, chars[end] == "=", end > next {
                parts.append(current)
                current = ""
                index = next
                continue
            }
        }
        current.append(chars[index])
        index += 1
    }
    if !current.isEmpty { parts.append(current) }
    return parts
}

private final class SessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let jar: CookieJar
    init(jar: CookieJar) { self.jar = jar }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        jar.absorb(response)
        let method = task.originalRequest?.httpMethod ?? "GET"
        guard method == "GET" || method == "HEAD" else {
            completionHandler(nil)
            return
        }
        var next = request
        if let cookie = jar.header() { next.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let token = jar.xsrf() { next.setValue(token, forHTTPHeaderField: "X-XSRF-TOKEN") }
        completionHandler(next)
    }
}

private final class InFlight: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private(set) var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func attach(_ task: URLSessionTask) {
        lock.lock()
        let shouldCancel = cancelled
        if !shouldCancel { self.task = task }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }
}

private final class ChunkUploader: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let flight: InFlight
    private let onBytes: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<String, Error>?
    private let lock = NSLock()
    private var resumed = false
    private var received = Data()
    private var pending: Int64 = 0
    private var session: URLSession?

    init(flight: InFlight, continuation: CheckedContinuation<String, Error>, onBytes: @escaping @Sendable (Int64) -> Void) {
        self.flight = flight
        self.continuation = continuation
        self.onBytes = onBytes
    }

    func start(url: URL, data: Data, userAgent: String) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15 * 60
        config.timeoutIntervalForResource = 15 * 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 15 * 60
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue("", forHTTPHeaderField: "Expect")
        request.setValue("close", forHTTPHeaderField: "Connection")
        let task = session.uploadTask(with: request, from: data)
        flight.attach(task)
        if flight.cancelled {
            finish(.failure(CancellationError()))
            session.invalidateAndCancel()
            return
        }
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        pending += bytesSent
        if pending >= 256 * 1024 {
            let delta = pending
            pending = 0
            onBytes(delta)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if pending > 0 { onBytes(pending) }
        session.finishTasksAndInvalidate()
        if let error {
            if flight.cancelled || (error as? URLError)?.code == .cancelled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(TransferError.retryable(error.localizedDescription)))
            }
            return
        }
        let http = task.response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: received, encoding: .utf8) ?? ""
            finish(.failure(TransferError.retryable("Le stockage a répondu \(status). \(text.prefix(140))")))
            return
        }
        let etag = normalizeEtag(http?.value(forHTTPHeaderField: "ETag") ?? "")
        guard !etag.isEmpty else {
            finish(.failure(TransferError.retryable("Le stockage n’a pas renvoyé d’empreinte.")))
            return
        }
        finish(.success(etag))
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private func normalizeEtag(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.lowercased().hasPrefix("w/") {
        value = String(value.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    value = value.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty else { return "" }
    return "\"\(value)\""
}
