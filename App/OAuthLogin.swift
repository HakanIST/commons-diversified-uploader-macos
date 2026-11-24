import AuthenticationServices
import UploaderCore

/// Herkese açık OAuth 2.0 istemcisinin kimliği (gizli değildir). Meta-Wiki'de
/// Special:OAuthConsumerRegistration üzerinden kaydedilir; geri dönüş adresi
/// `OAuth.redirectURI` olmalıdır. Boşsa "Commons ile giriş yap" düğmesi gösterilmez.
enum OAuthConfig {
    static let clientID = ""
    static var isAvailable: Bool { !clientID.isEmpty }
}

/// Yetkilendirme sayfasını sistemin güvenli tarayıcı penceresinde açar ve geri dönüş adresini bekler.
@MainActor
final class OAuthLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    /// Kullanıcı pencereyi kapatırsa `nil` döner.
    func signIn() async throws -> CommonsAuth? {
        let request = OAuth.makeRequest(clientID: OAuthConfig.clientID)
        let callback: URL? = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: request.url, callbackURLScheme: OAuth.callbackScheme) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(returning: nil) }
        }
        session = nil
        guard let callback else { return nil }
        let code = try OAuth.code(from: callback, expecting: request)
        let tokens = try await OAuth.exchange(clientID: OAuthConfig.clientID, code: code, request: request)
        return .oauth(clientID: OAuthConfig.clientID, tokens: tokens)
    }
}
