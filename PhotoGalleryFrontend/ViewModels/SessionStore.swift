import Foundation
import Observation

/// App-wide session/auth state. Restores the JWT token from Keychain on launch
/// and re-validates against `/api/auth/me` to refresh user data.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case checking
        case needsServer
        case needsLogin
        case authenticated
    }

    private(set) var phase: Phase = .checking
    private(set) var currentUser: User?
    var errorMessage: String?

    private let api = PhotoServerAPI()
    private let cachedUserKey = "cachedUser"

    func bootstrap() async {
        guard APIClient.shared.baseURL != nil else {
            phase = .needsServer
            return
        }
        if let data = KeychainHelper.get(key: cachedUserKey)?.data(using: .utf8),
           let cached = try? JSONDecoder().decode(User.self, from: data) {
            currentUser = cached
            phase = .authenticated  // show app immediately; refreshUser validates in the background
        }
        await refreshUser()
    }

    func refreshUser() async {
        do {
            let user = try await api.me()
            currentUser = user
            cache(user)
            phase = .authenticated
        } catch APIError.server(let status, _) where status == 401 || status == 403 {
            // Token expired or revoked — clear credentials and ask to log in
            APIClient.shared.setAuthToken(nil)
            currentUser = nil
            KeychainHelper.remove(key: cachedUserKey)
            phase = .needsLogin
        } catch {
            // Network or transient error — keep existing state
            if currentUser == nil { phase = .needsLogin }
        }
    }

    func configureServer(_ urlString: String) {
        APIClient.shared.setBaseURL(urlString)
        phase = .needsLogin
    }

    func login(name: String, password: String) async {
        errorMessage = nil
        do {
            let response = try await api.login(name: name, password: password)
            APIClient.shared.setAuthToken(response.token)
            currentUser = response.user
            cache(response.user)
            phase = .authenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signup(name: String, password: String) async {
        errorMessage = nil
        do {
            let response = try await api.signup(name: name, password: password)
            APIClient.shared.setAuthToken(response.token)
            currentUser = response.user
            cache(response.user)
            phase = .authenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        APIClient.shared.setAuthToken(nil)
        currentUser = nil
        KeychainHelper.remove(key: cachedUserKey)
        phase = .needsLogin
    }

    func updateCachedUser(_ user: User) {
        currentUser = user
        cache(user)
    }

    private func cache(_ user: User) {
        if let data = try? JSONEncoder().encode(user), let string = String(data: data, encoding: .utf8) {
            KeychainHelper.set(string, key: cachedUserKey)
        }
    }
}