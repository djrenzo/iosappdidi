import SwiftUI

struct FolderPickerView: View {
    var library: LibraryViewModel

    var body: some View {
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
                ForEach(library.folders, id: \.self) { folder in
                    Button(folder) { library.selectedFolder = folder }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(library.selectedFolder ?? "All Folders")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: Capsule())
        }
    }
}
