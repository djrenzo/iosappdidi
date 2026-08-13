import SwiftUI

struct EditProfileSheet: View {
    var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()
    @State private var name: String

    init(session: SessionStore) {
        self.session = session
        _name = State(initialValue: session.currentUser?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LabeledField(title: "NAME", text: $name)
                if let error = viewModel.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
                if let success = viewModel.successMessage {
                    Text(success).font(.footnote).foregroundStyle(Theme.accent)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.updateProfile(name: name, session: session)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving)
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
