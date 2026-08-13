import Foundation
import Observation

/// Persists the list of configured photo servers and which one is active.
///
/// Not `@MainActor`-isolated — deliberately mirrors `APIClient`/`ImageCache`'s existing
/// `@unchecked Sendable` singleton pattern (backed by plain, synchronous UserDefaults reads/
/// writes) so `APIClient` can read `selectedServer` directly from any execution context
/// without an actor hop.
@Observable
final class ServerStore: @unchecked Sendable {
    static let shared = ServerStore()

    private(set) var servers: [Server] = []
    private(set) var selectedServerId: UUID?

    private let serversKey = "photoServers"
    private let selectedServerIdKey = "selectedServerId"
    /// Where the server address lived before multi-server support — migrated into a
    /// "Home" entry below so existing installs don't need to reconfigure from scratch.
    private let legacyBaseURLKey = "serverBaseURL"

    var selectedServer: Server? {
        servers.first { $0.id == selectedServerId }
    }

    private init() {
        load()
        migrateLegacyServerIfNeeded()
    }

    /// Adds a server to the list. Does not switch to it — callers that want the new
    /// server to become active call `selectServer(_:)` explicitly.
    @discardableResult
    func addServer(name: String, host: String) -> Server {
        let server = Server(id: UUID(), name: name, host: host)
        servers.append(server)
        persist()
        return server
    }

    /// Removes a server. If it was the active one, falls back to the first remaining
    /// server, or to no selection at all if none are left (the app's normal `.needsServer`
    /// flow then takes over, exactly as on a fresh install).
    func deleteServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        if selectedServerId == server.id {
            selectedServerId = servers.first?.id
        }
        persist()
    }

    func selectServer(_ server: Server) {
        guard servers.contains(where: { $0.id == server.id }) else { return }
        selectedServerId = server.id
        persist()
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([Server].self, from: data) {
            servers = decoded
        }
        if let idString = defaults.string(forKey: selectedServerIdKey) {
            selectedServerId = UUID(uuidString: idString)
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: serversKey)
        }
        defaults.set(selectedServerId?.uuidString, forKey: selectedServerIdKey)
    }

    private func migrateLegacyServerIfNeeded() {
        guard servers.isEmpty else { return }
        guard let legacyHost = UserDefaults.standard.string(forKey: legacyBaseURLKey), !legacyHost.isEmpty else { return }
        let server = Server(id: UUID(), name: "Home", host: legacyHost)
        servers = [server]
        selectedServerId = server.id
        persist()
    }
}
