import SwiftUI

/// Two cascading pickers: the first lists top-level folders only; selecting one that has
/// subfolders reveals a second picker, to its right, scoped to just that folder's children.
/// Both open as a scrollable sheet rather than a native pull-down menu — a `Menu` gives no
/// control over scroll position, and these lists can run to 50+ entries, so each sheet
/// scrolls itself to the current selection on open instead of always starting at the top.
struct FolderPickerView: View {
    var library: LibraryViewModel
    @State private var showTopLevelPicker = false
    @State private var showSubfolderPicker = false

    private var selectedTopLevel: String? {
        library.selectedFolder?.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    private var subfolders: [String] {
        guard let selectedTopLevel else { return [] }
        return library.subfolders(of: selectedTopLevel)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { showTopLevelPicker = true } label: {
                pickerLabel(selectedTopLevel ?? "All Folders")
            }
            .sheet(isPresented: $showTopLevelPicker) {
                TopLevelFolderSheet(library: library)
            }

            if let selectedTopLevel, !subfolders.isEmpty {
                Button { showSubfolderPicker = true } label: {
                    pickerLabel(subfolderLabel(selectedTopLevel: selectedTopLevel))
                }
                .sheet(isPresented: $showSubfolderPicker) {
                    SubfolderSheet(library: library, topLevel: selectedTopLevel, subfolders: subfolders)
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

/// A selectable row shared by both folder sheets below.
private struct FolderRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

/// The sentinel id for the "All ..." row, since it has no natural string key of its own.
private let allRowId = "__all__"

private struct TopLevelFolderSheet: View {
    var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private var selectedTopLevel: String? {
        library.selectedFolder?.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    FolderRow(label: "All Folders", isSelected: library.selectedFolder == nil) {
                        library.selectedFolder = nil
                        dismiss()
                    }
                    .id(allRowId)
                    ForEach(library.topLevelFolders, id: \.self) { folder in
                        FolderRow(label: folder, isSelected: folder == selectedTopLevel) {
                            library.selectedFolder = folder
                            dismiss()
                        }
                        .id(folder)
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    Task { @MainActor in
                        proxy.scrollTo(selectedTopLevel ?? allRowId, anchor: .top)
                    }
                }
            }
            .navigationTitle("Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SubfolderSheet: View {
    var library: LibraryViewModel
    let topLevel: String
    let subfolders: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    FolderRow(label: "All in \(topLevel)", isSelected: library.selectedFolder == topLevel) {
                        library.selectedFolder = topLevel
                        dismiss()
                    }
                    .id(allRowId)
                    ForEach(subfolders, id: \.self) { folder in
                        FolderRow(label: String(folder.dropFirst(topLevel.count + 1)), isSelected: folder == library.selectedFolder) {
                            library.selectedFolder = folder
                            dismiss()
                        }
                        .id(folder)
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    Task { @MainActor in
                        let target = library.selectedFolder == topLevel ? allRowId : (library.selectedFolder ?? allRowId)
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
            .navigationTitle(topLevel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
