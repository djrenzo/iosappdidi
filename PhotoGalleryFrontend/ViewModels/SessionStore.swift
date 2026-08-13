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

    /// The cached user is namespaced per server id, same reasoning as the JWT in
    /// `APIClient` — a cached user from one server has no meaning on another.
    private func cachedUserKey(for serverId: UUID) -> String { "cachedUser_\(serverId.uuidString)" }

    func bootstrap() async {
        guard ServerStore.shared.selectedServer != nil else {
            phase = .needsServer
            return
        }
        if let serverId = ServerStore.shared.selectedServer?.id,
           let data = KeychainHelper.get(key: cachedUserKey(for: serverId))?.data(using: .utf8),
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
            clearCredentials()
            phase = .needsLogin
        } catch {
            // Network or transient error — keep existing state
            if currentUser == nil { phase = .needsLogin }
        }
    }

    /// The first-launch flow: creates and selects a new server, named by the user
    /// (defaults to "Home" from `ServerSetupView`).
    func configureServer(name: String, host: String) {
        let server = ServerStore.shared.addServer(name: name, host: host)
        ServerStore.shared.selectServer(server)
        phase = .needsLogin
    }

    /// Switches the active server (e.g. from the Profile "Server" picker) and re-bootstraps —
    /// this restores that server's saved session if there is one, or asks to log in if not.
    func switchServer(to server: Server) async {
        guard server.id != ServerStore.shared.selectedServerId else { return }
        ServerStore.shared.selectServer(server)
        await reloadForActiveServer()
    }

    /// Deletes a server from Manage Servers. If it was the active one, re-bootstraps for
    /// whichever server (if any) became active in its place.
    func deleteServer(_ server: Server) async {
        let wasSelected = server.id == ServerStore.shared.selectedServerId
        ServerStore.shared.deleteServer(server)
        if wasSelected {
            await reloadForActiveServer()
        }
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
        clearCredentials()
        phase = .needsLogin
    }

    func updateCachedUser(_ user: User) {
        currentUser = user
        cache(user)
    }

    /// Re-runs bootstrap after the active server changes underneath the current session —
    /// clears in-memory state first so nothing from the old server flashes on screen.
    private func reloadForActiveServer() async {
        currentUser = nil
        errorMessage = nil
        phase = .checking
        await bootstrap()
    }

    private func clearCredentials() {
        APIClient.shared.setAuthToken(nil)
        currentUser = nil
        if let serverId = ServerStore.shared.selectedServer?.id {
            KeychainHelper.remove(key: cachedUserKey(for: serverId))
        }
    }

    private func cache(_ user: User) {
        guard let serverId = ServerStore.shared.selectedServer?.id else { return }
        if let data = try? JSONEncoder().encode(user), let string = String(data: data, encoding: .utf8) {
            KeychainHelper.set(string, key: cachedUserKey(for: serverId))
        }
    }
}
