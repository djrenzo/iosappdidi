import SwiftUI

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()
    @State private var current = ""
    @State private var newPassword = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LabeledField(title: "CURRENT PASSWORD", text: $current, isSecure: true)
                LabeledField(title: "NEW PASSWORD", text: $newPassword, isSecure: true)
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
            .navigationTitle("Change Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.changePassword(current: current, newPassword: newPassword)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(newPassword.count < 8 || viewModel.isSaving)
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}
