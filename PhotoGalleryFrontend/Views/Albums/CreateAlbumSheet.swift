import SwiftUI

struct CreateAlbumSheet: View {
    var session: SessionStore
    var viewModel: AlbumsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LabeledField(title: "ALBUM NAME", text: $name)
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("New Album")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let userId = session.currentUser?.id else { return }
                        Task {
                            isSaving = true
                            await viewModel.createAlbum(name: name, userId: userId)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}