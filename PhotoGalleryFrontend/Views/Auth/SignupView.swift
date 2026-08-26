import SwiftUI

struct SignupView: View {
    var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Create your account to start browsing your photo library.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    LabeledField(title: "USERNAME", text: $name, textContentType: .username)
                    LabeledField(title: "PASSWORD", text: $password, isSecure: true, textContentType: .newPassword)
                    if let error = session.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(Theme.danger)
                    }
                    Button {
                        Task {
                            isSubmitting = true
                            await session.signup(name: name, password: password)
                            isSubmitting = false
                            if session.phase == .authenticated { dismiss() }
                        }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text("Create Account").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(name.isEmpty || password.isEmpty || isSubmitting)
                }
                .padding(24)
                .frame(maxWidth: 440)
            }
            .background(Theme.background)
            .navigationTitle("Sign Up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
