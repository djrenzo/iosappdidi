import SwiftUI

struct ServerSetupView: View {
    var session: SessionStore
    @State private var name: String = "Home"
    @State private var address: String = "http://127.0.0.1:3000"

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            icon
            VStack(spacing: 8) {
                Text("Connect to Your Photo Server")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Enter the address of the Photo Server on your local network.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SERVER NAME")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Home", text: $name)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("SERVER ADDRESS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("http://192.168.1.10:3000", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
            }
            .padding(.horizontal, 24)

            Button {
                let cleanName = name.trimmingCharacters(in: .whitespaces)
                session.configureServer(name: cleanName.isEmpty ? "Home" : cleanName, host: address)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
    }

    private var icon: some View {
        Image(systemName: "server.rack")
            .font(.system(size: 44))
            .foregroundStyle(Theme.accent)
            .frame(width: 92, height: 92)
            .background(Theme.accentSoft, in: Circle())
    }
}
