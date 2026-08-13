import SwiftUI

struct TagEditorSheet: View {
    var viewModel: PhotoDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let tags = viewModel.detail?.tags, !tags.isEmpty {
                    FlowTagList(tags: tags) { tag in
                        Task { await viewModel.removeTag(tag) }
                    }
                } else {
                    Text("No tags yet. Add one below.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 20)
                }
                Spacer()
                HStack {
                    TextField("Add a tag", text: $newTag)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    Button("Add") {
                        Task { await viewModel.addTag(newTag); newTag = "" }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct FlowTagList: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(.footnote.weight(.medium))
                        Button { onRemove(tag) } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                        }
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accentSoft, in: Capsule())
                }
            }
        }
    }
}
