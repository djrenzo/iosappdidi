import SwiftUI

/// Create/delete screen for configured servers. Switching the *active* server is a
/// separate control — the "Server" picker on the Profile tab — this screen is CRUD only.
struct ManageServersView: View {
    var session: SessionStore
    private let serverStore = ServerStore.shared
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(serverStore.servers) { server in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name).foregroundStyle(Theme.textPrimary)
                        Text(server.host).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if server.id == serverStore.selectedServerId {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let server = serverStore.servers[index]
                    Task { await session.deleteServer(server) }
                }
            }
        }
        .navigationTitle("Manage Servers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddServerSheet()
        }
    }
}

private struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LabeledField(title: "NAME", text: $name)
                LabeledField(title: "HOST", text: $host, textContentType: .URL, keyboardType: .URL)
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Add Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        ServerStore.shared.addServer(
                            name: name.trimmingCharacters(in: .whitespaces),
                            host: host.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
