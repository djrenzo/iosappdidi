import SwiftUI

struct LoginView: View {
    var session: SessionStore
    @State private var name = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var showSignup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                formFields
                if let error = session.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }
                submitButton
                Button("Need an account? Sign up") { showSignup = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
            }
            .padding(24)
            .padding(.top, 40)
        }
        .background(Theme.background)
        .sheet(isPresented: $showSignup) { SignupView(session: session) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
                .frame(width: 88, height: 88)
                .background(Theme.accentSoft, in: Circle())
            Text("Welcome Back")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Sign in to browse your photo library")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var formFields: some View {
        VStack(spacing: 12) {
            LabeledField(title: "USERNAME", text: $name, textContentType: .username)
            LabeledField(title: "PASSWORD", text: $password, isSecure: true, textContentType: .password)
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                isSubmitting = true
                await session.login(name: name, password: password)
                isSubmitting = false
            }
        } label: {
            HStack {
                if isSubmitting { ProgressView().tint(.white) }
                Text("Sign In").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(name.isEmpty || password.isEmpty || isSubmitting)
    }
}

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var textContentType: UITextContentType?
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(textContentType)
            .keyboardType(keyboardType)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
    }
}
