import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case server(status: Int, message: String?)
    case decoding
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address looks invalid."
        case .server(let status, let message):
            return message ?? "The server returned an error (\(status))."
        case .decoding:
            return "Received an unexpected response from the server."
        case .notConfigured:
            return "Connect to a photo server to continue."
        }
    }
}

/// Thin async/await HTTP client for the Photo Server API.
/// Auth uses a JWT Bearer token returned on login and stored in the Keychain.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private let encoder = JSONEncoder()
    private let tokenKey = "authJWT"

    var authToken: String? {
        KeychainHelper.get(key: tokenKey)
    }

    func setAuthToken(_ token: String?) {
        if let token {
            KeychainHelper.set(token, key: tokenKey)
        } else {
            KeychainHelper.remove(key: tokenKey)
        }
    }

    var baseURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: "serverBaseURL"), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    func setBaseURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: "serverBaseURL")
    }

    func absoluteURL(forPath path: String) -> URL? {
        guard let baseURL else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Encodable? = nil
    ) async throws -> T {
        let data = try await rawRequest(path: path, method: method, query: query, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    @discardableResult
    func requestVoid(
        path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Encodable? = nil
    ) async throws -> Data {
        try await rawRequest(path: path, method: method, query: query, body: body)
    }

    private func rawRequest(
        path: String,
        method: String,
        query: [String: String?],
        body: Encodable?
    ) async throws -> Data {
        guard let baseURL else { throw APIError.notConfigured }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        // Percent-encode every query value ourselves and assign percentEncodedQueryItems
        // directly. URLQueryItem's plain `queryItems` setter deliberately leaves characters
        // like "+", "&", "=" unescaped (Apple's docs: it can't tell delimiter from data), and
        // an unescaped "+" gets silently decoded back to a space by the server's standard
        // x-www-form-urlencoded query parser — corrupting values like folder names that
        // contain a literal "+" (e.g. "2015/Amerika + Aruba 2015").
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key.percentEncodedForQueryComponent(), value: value.percentEncodedForQueryComponent())
        }
        if !items.isEmpty { components.percentEncodedQueryItems = items }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let message = try? JSONDecoder().decode(ServerErrorMessage.self, from: data)
            throw APIError.server(status: http.statusCode, message: message?.error)
        }
        return data
    }
}

private extension String {
    /// RFC 3986 "unreserved" characters only — everything else (including "+", "&", "=") is
    /// percent-encoded, so there's no ambiguity left for a server-side parser to misread.
    func percentEncodedForQueryComponent() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

private struct ServerErrorMessage: Decodable { let error: String? }

/// Type-erased wrapper so `Encodable` bodies can be passed as existentials.
private struct AnyEncodable: Encodable {
    private let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
