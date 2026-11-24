import Foundation

public enum HTTP {
    public static let userAgent = "CommonsDiversifiedUploader/0.1 (macOS; native app)"

    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    static func query(_ base: String, _ params: [String: String]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // "+" sorgu dizgisinde boşluk sayılır; açıkça kodla.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    /// Geçici hatalarda (429, 5xx, bağlantı) artan beklemeyle yeniden dener.
    static func json(_ request: URLRequest, session: URLSession = .shared, retries: Int = 3) async throws -> [String: Any] {
        var request = request
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        var last: Error = Failure(message: L("İstek başarısız"))
        for attempt in 0...retries {
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 429 || status >= 500 { throw Failure(message: "HTTP \(status)") }
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(message: L("Beklenmeyen yanıt")) }
                if let code = (obj["error"] as? [String: Any])?["code"] as? String, code == "maxlag" || code == "ratelimited" { throw Failure(message: code) }
                return obj
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                last = error
                if attempt < retries { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_500_000_000) }
            }
        }
        throw last
    }

    static func getJSON(_ base: String, _ params: [String: String], session: URLSession = .shared) async throws -> [String: Any] {
        try await json(URLRequest(url: query(base, params)), session: session)
    }
}
