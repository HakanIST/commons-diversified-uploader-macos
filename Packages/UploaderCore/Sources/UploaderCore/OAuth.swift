import CryptoKit
import Foundation

/// OAuth 2.0 ile alınan belirteçler. Erişim belirteci kısa ömürlüdür; yenileme belirteci her kullanımda değişir.
public struct OAuthTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Süresi dolmak üzereyse yenilenmelidir.
    public var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 300 }
}

/// Wikimedia hesabıyla oturum: yetkilendirme kodu + PKCE (gizli anahtarı olmayan, herkese açık istemci).
public enum OAuth {
    /// İstemci kaydındaki geri dönüş adresiyle birebir aynı olmalıdır.
    public static let callbackScheme = "tr.tall.commonsdiversifieduploader"
    public static let redirectURI = "\(callbackScheme)://oauth/callback"
    static let endpoint = "https://commons.wikimedia.org/w/rest.php/oauth2"

    public struct Request: Sendable {
        public let url: URL
        public let verifier: String
        public let state: String
    }

    static func randomToken(bytes: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Tarayıcıda açılacak yetkilendirme adresini ve onunla eşleşen doğrulayıcıyı üretir.
    public static func makeRequest(clientID: String) -> Request {
        let verifier = randomToken(), state = randomToken(bytes: 16)
        let url = HTTP.query("\(endpoint)/authorize", [
            "client_id": clientID, "response_type": "code", "redirect_uri": redirectURI,
            "code_challenge": challenge(for: verifier), "code_challenge_method": "S256", "state": state,
        ])
        return Request(url: url, verifier: verifier, state: state)
    }

    /// Geri dönüş adresinden yetkilendirme kodunu çıkarır; durum değeri eşleşmelidir.
    public static func code(from callback: URL, expecting request: Request) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw HTTP.Failure(message: L("Oturum açılamadı: \(value("error_description") ?? error)")) }
        guard value("state") == request.state, let code = value("code"), !code.isEmpty else {
            throw HTTP.Failure(message: L("Oturum açılamadı: kimlik bilgisi kabul edilmedi"))
        }
        return code
    }

    private static func token(_ fields: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "\(endpoint)/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.query("https://x/", fields).query(percentEncoded: true)?.data(using: .utf8)
        let d = try await HTTP.json(request, session: URLSession(configuration: .ephemeral), retries: 1)
        guard let access = d["access_token"] as? String else {
            let reason = d["error_description"] as? String ?? d["message"] as? String ?? d["hint"] as? String ?? d["error"] as? String ?? L("bilinmeyen hata")
            throw HTTP.Failure(message: L("Oturum açılamadı: \(reason)"))
        }
        let lifetime = (d["expires_in"] as? Double) ?? 3600
        return OAuthTokens(accessToken: access, refreshToken: d["refresh_token"] as? String, expiresAt: Date().addingTimeInterval(lifetime))
    }

    public static func exchange(clientID: String, code: String, request: Request) async throws -> OAuthTokens {
        try await token(["grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI, "client_id": clientID, "code_verifier": request.verifier])
    }

    public static func refresh(clientID: String, refreshToken: String) async throws -> OAuthTokens {
        try await token(["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID])
    }
}
