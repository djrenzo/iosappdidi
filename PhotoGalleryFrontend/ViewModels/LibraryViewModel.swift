import Foundation
import Observation

/// Owns the current library/folder selection shared across gallery tabs.
@MainActor
@Observable
final class LibraryViewModel {
    private(set) var libraries: [String] = []
    private(set) var folders: [String] = []
    var selectedLibrary: String?
    var selectedFolder: String?
    var isLoading = false
    var errorMessage: String?

    private let api = PhotoServerAPI()

    func load(userId: String) async {
        isLoading = true
        errorMessage = nil
        // Clear the previous selection up front — matters when this is re-called after
        // switching servers, so the old server's library/folder names don't linger on
        // screen while the new fetch is still in flight.
        libraries = []
        selectedLibrary = nil
        folders = []
        selectedFolder = nil
        defer { isLoading = false }
        do {
            libraries = try await api.libraries(userId: userId)
            selectedLibrary = libraries.first
            if let library = selectedLibrary {
                folders = try await api.folders(library: library)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectLibrary(_ library: String) async {
        selectedLibrary = library
        selectedFolder = nil
        do {
            folders = try await api.folders(library: library)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Top-level folder names (the part before the first "/"), descending — e.g. so a
    /// year-numbered library shows the most recent year first. `/api/folders` returns full
    /// paths like "1970/Jeugd Taco" for every level, so this collapses that into just the
    /// roots for a first-level picker.
    var topLevelFolders: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for folder in folders {
            let top = folder.split(separator: "/", maxSplits: 1).first.map(String.init) ?? folder
            if seen.insert(top).inserted {
                result.append(top)
            }
        }
        return result.sorted(by: >)
    }

    /// Full folder paths nested directly under `topLevel`, e.g. "1969 en eerder/jeugd cjh".
    /// Ascending, same order `/api/folders` already returns them in.
    func subfolders(of topLevel: String) -> [String] {
        folders.filter { $0.hasPrefix(topLevel + "/") }
    }
}
