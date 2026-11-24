import Foundation

public enum CommonsAuth: Codable, Equatable, Sendable {
    case botPassword(username: String, password: String)
    case oauth2(token: String)
}

public enum UploadOutcome: Sendable {
    case success(title: String, pageID: Int?, url: String?)
    /// Yayımlanmadı: aynı ad ya da aynı içerikle dosya var.
    case blocked(reason: String)
}

/// Commons API istemcisi: oturum, kategori/dosya adı denetimi, parçalı yükleme, "depicts" verisi.
public actor CommonsClient {
    public static let chunkSize = 4 * 1024 * 1024
    private let api: String
    private let auth: CommonsAuth?
    private let session: URLSession
    private var csrf: String?
    public private(set) var username: String?

    public init(auth: CommonsAuth?, api: String = "https://commons.wikimedia.org/w/api.php") {
        self.auth = auth
        self.api = api
        // Oturum çerezleri yalnızca bellekte tutulur.
        session = URLSession(configuration: .ephemeral)
    }

    private func authorize(_ request: inout URLRequest) {
        if case .oauth2(let token) = auth { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    private func get(_ params: [String: String]) async throws -> [String: Any] {
        var p = params
        p["format"] = "json"; p["formatversion"] = "2"
        var request = URLRequest(url: HTTP.query(api, p))
        authorize(&request)
        return try await HTTP.json(request, session: session)
    }

    private func post(_ params: [String: String]) async throws -> [String: Any] {
        var p = params
        p["format"] = "json"; p["formatversion"] = "2"
        var request = URLRequest(url: URL(string: api)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.query("https://x/", p).query(percentEncoded: true)?.data(using: .utf8)
        authorize(&request)
        return try await HTTP.json(request, session: session)
    }

    private static func apiError(_ d: [String: Any]) -> String? { (d["error"] as? [String: Any])?["info"] as? String }

    @discardableResult
    public func login() async throws -> String {
        if case .botPassword(let user, let password) = auth {
            let t = try await get(["action": "query", "meta": "tokens", "type": "login"])
            let token = ((t["query"] as? [String: Any])?["tokens"] as? [String: Any])?["logintoken"] as? String ?? ""
            let r = try await post(["action": "login", "lgname": user, "lgpassword": password, "lgtoken": token])
            let login = r["login"] as? [String: Any]
            guard login?["result"] as? String == "Success" else {
                throw HTTP.Failure(message: "Oturum açılamadı: \(login?["reason"] as? String ?? login?["result"] as? String ?? "bilinmeyen hata")")
            }
        }
        let d = try await get(["action": "query", "meta": "userinfo|tokens", "uiprop": "rights", "type": "csrf"])
        if let e = Self.apiError(d) { throw HTTP.Failure(message: "Oturum açılamadı: \(e)") }
        let q = d["query"] as? [String: Any] ?? [:]
        let info = q["userinfo"] as? [String: Any] ?? [:]
        guard info["anon"] == nil, let name = info["name"] as? String else { throw HTTP.Failure(message: "Oturum açılamadı: kimlik bilgisi kabul edilmedi") }
        guard (info["rights"] as? [String] ?? []).contains("upload") else { throw HTTP.Failure(message: "Bu kimlik bilgisinin dosya yükleme izni yok") }
        username = name
        csrf = (q["tokens"] as? [String: Any])?["csrftoken"] as? String
        return name
    }

    /// Verilen sayfa başlıklarından hangilerinin var olduğunu döndürür.
    public func existing(_ titles: [String]) async throws -> [String: Bool] {
        var out: [String: Bool] = [:]
        let unique = Array(Set(titles)).sorted()
        for start in stride(from: 0, to: unique.count, by: 50) {
            let d = try await get(["action": "query", "titles": unique[start..<min(start + 50, unique.count)].joined(separator: "|")])
            let q = d["query"] as? [String: Any] ?? [:]
            var back: [String: String] = [:]
            for n in q["normalized"] as? [[String: String]] ?? [] { if let to = n["to"], let from = n["from"] { back[to] = from } }
            for p in q["pages"] as? [[String: Any]] ?? [] {
                guard let title = p["title"] as? String else { continue }
                out[back[title] ?? title] = p["missing"] == nil && p["invalid"] == nil
            }
        }
        return out
    }

    public func searchCategories(_ prefix: String) async throws -> [String] {
        let d = try await get(["action": "query", "list": "prefixsearch", "pssearch": "Category:\(prefix)", "psnamespace": "14", "pslimit": "10"])
        return ((d["query"] as? [String: Any])?["prefixsearch"] as? [[String: Any]] ?? []).compactMap { ($0["title"] as? String)?.replacingOccurrences(of: "Category:", with: "") }
    }

    private func uploadCall(_ fields: [String: String], chunk: Data? = nil, fileName: String = "") async throws -> [String: Any] {
        let boundary = "cdu-\(UUID().uuidString)"
        var body = Data()
        var all = fields
        all["action"] = "upload"; all["format"] = "json"; all["formatversion"] = "2"; all["token"] = csrf ?? ""
        for (k, v) in all.sorted(by: { $0.key < $1.key }) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        if let chunk {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"chunk\"; filename=\"chunk\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(chunk)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: URL(string: api)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        authorize(&request)
        let d = try await HTTP.json(request, session: session)
        if let e = Self.apiError(d) { throw HTTP.Failure(message: e) }
        return d["upload"] as? [String: Any] ?? [:]
    }

    private static let blockingWarnings = ["exists", "exists-normalized", "duplicate", "duplicate-archive", "was-deleted", "badfilename"]

    private static func describe(_ warnings: [String: Any]) -> String? {
        guard let key = blockingWarnings.first(where: { warnings[$0] != nil }) else { return nil }
        switch key {
        case "duplicate":
            let files = (warnings[key] as? [String])?.joined(separator: ", ") ?? ""
            return "Aynı dosya Commons'ta zaten var: \(files)"
        case "exists", "exists-normalized": return "Bu adla bir dosya zaten var"
        case "was-deleted", "duplicate-archive": return "Bu dosya daha önce Commons'tan silinmiş"
        default: return "Dosya adı kabul edilmedi"
        }
    }

    /// Dosyayı parçalar hâlinde yükler. Engelleyici uyarı varsa yayımlamaz.
    public func upload(file: URL, filename: String, text: String, comment: String, progress: (@Sendable (Double) -> Void)? = nil) async throws -> UploadOutcome {
        guard csrf != nil else { throw HTTP.Failure(message: "Önce Commons oturumu açın") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        var offset = 0, fileKey: String?
        var warnings: [String: Any] = [:]
        while offset < size {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            var fields = ["stash": "1", "filename": filename, "filesize": String(size), "offset": String(offset)]
            if let fileKey { fields["filekey"] = fileKey }
            let r = try await uploadCall(fields, chunk: chunk)
            fileKey = r["filekey"] as? String ?? fileKey
            for (k, v) in r["warnings"] as? [String: Any] ?? [:] { warnings[k] = v }
            offset += chunk.count
            progress?(Double(offset) / Double(max(size, 1)))
        }
        if let reason = Self.describe(warnings) { return .blocked(reason: reason) }
        guard let fileKey else { throw HTTP.Failure(message: "Yükleme başlatılamadı") }
        let r = try await uploadCall(["filekey": fileKey, "filename": filename, "text": text, "comment": comment])
        guard r["result"] as? String == "Success" else {
            if let w = r["warnings"] as? [String: Any] { return .blocked(reason: Self.describe(w) ?? "Uyarı: \(w.keys.sorted().joined(separator: ", "))") }
            throw HTTP.Failure(message: "Yükleme tamamlanamadı: \(r["result"] as? String ?? "?")")
        }
        let title = "File:\(r["filename"] as? String ?? filename)"
        let q = try await get(["action": "query", "titles": title, "prop": "info", "inprop": "url"])
        let page = ((q["query"] as? [String: Any])?["pages"] as? [[String: Any]])?.first
        return .success(title: title, pageID: page?["pageid"] as? Int, url: page?["canonicalurl"] as? String)
    }

    /// Yapılandırılmış veri: dosyada görünen kişiler (P180).
    public func addDepicts(pageID: Int, qids: [String]) async throws {
        guard !qids.isEmpty else { return }
        let claims: [[String: Any]] = qids.compactMap { q in
            guard let n = Int(q.dropFirst()) else { return nil }
            return ["type": "statement", "rank": "normal", "mainsnak": ["snaktype": "value", "property": "P180", "datavalue": ["type": "wikibase-entityid", "value": ["entity-type": "item", "numeric-id": n, "id": q]]]]
        }
        let data = String(data: try JSONSerialization.data(withJSONObject: ["claims": claims]), encoding: .utf8)!
        let d = try await post(["action": "wbeditentity", "id": "M\(pageID)", "data": data, "token": csrf ?? "", "summary": "Görünen kişiler eklendi"])
        if let e = Self.apiError(d) { throw HTTP.Failure(message: e) }
    }

    public func createCategory(_ name: String, text: String) async throws {
        let d = try await post(["action": "edit", "title": "Category:\(name)", "text": text, "createonly": "1", "summary": "Maç kategorisi oluşturuldu", "token": csrf ?? ""])
        if let err = d["error"] as? [String: Any], err["code"] as? String != "articleexists" { throw HTTP.Failure(message: err["info"] as? String ?? "Kategori oluşturulamadı") }
    }
}
