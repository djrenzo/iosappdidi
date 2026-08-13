import SwiftUI

/// Two cascading pickers: the first lists top-level folders only; selecting one that has
/// subfolders reveals a second picker, to its right, scoped to just that folder's children.
struct FolderPickerView: View {
    var library: LibraryViewModel

    private var selectedTopLevel: String? {
        library.selectedFolder?.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    private var subfolders: [String] {
        guard let selectedTopLevel else { return [] }
        return library.subfolders(of: selectedTopLevel)
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if library.libraries.count > 1 {
                    Section("Library") {
                        ForEach(library.libraries, id: \.self) { lib in
                            Button(lib) { Task { await library.selectLibrary(lib) } }
                        }
                    }
                }
                Section("Folder") {
                    Button("All Folders") { library.selectedFolder = nil }
                    ForEach(library.topLevelFolders, id: \.self) { folder in
                        Button(folder) { library.selectedFolder = folder }
                    }
                }
            } label: {
                pickerLabel(selectedTopLevel ?? "All Folders")
            }

            if let selectedTopLevel, !subfolders.isEmpty {
                Menu {
                    Button("All in \(selectedTopLevel)") { library.selectedFolder = selectedTopLevel }
                    ForEach(subfolders, id: \.self) { folder in
                        Button(String(folder.dropFirst(selectedTopLevel.count + 1))) {
                            library.selectedFolder = folder
                        }
                    }
                } label: {
                    pickerLabel(subfolderLabel(selectedTopLevel: selectedTopLevel))
                }
            }
        }
    }

    private func subfolderLabel(selectedTopLevel: String) -> String {
        guard let selectedFolder = library.selectedFolder, selectedFolder != selectedTopLevel else {
            return "All"
        }
        return String(selectedFolder.dropFirst(selectedTopLevel.count + 1))
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: Capsule())
        .frame(maxWidth: 130)
    }
}
