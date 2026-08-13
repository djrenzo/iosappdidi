import Foundation
import Observation

/// App-wide session/auth state. Restores a cached user on launch and
/// re-validates against `/api/auth/me` since the real session lives in a
/// server-issued cookie, not something this app can inspect directly.
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
        }
        await refreshUser()
    }

    func refreshUser() async {
        do {
            let user = try await api.me()
            currentUser = user
            cache(user)
            phase = .authenticated
        } catch {
            currentUser = nil
            phase = .needsLogin
        }
    }

    func configureServer(_ urlString: String) {
        APIClient.shared.setBaseURL(urlString)
        phase = .needsLogin
    }

    func login(name: String, password: String) async {
        errorMessage = nil
        do {
            let user = try await api.login(name: name, password: password)
            currentUser = user
            cache(user)
            phase = .authenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signup(name: String, password: String) async {
        errorMessage = nil
        do {
            let user = try await api.signup(name: name, password: password)
            currentUser = user
            cache(user)
            phase = .authenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        currentUser = nil
        KeychainHelper.remove(key: cachedUserKey)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
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