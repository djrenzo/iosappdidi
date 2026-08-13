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
}
