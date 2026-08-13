import SwiftUI

struct ProfileView: View {
    var session: SessionStore
    var library: LibraryViewModel
    private let serverStore = ServerStore.shared
    @State private var showEdit = false
    @State private var showPassword = false

    private var librarySelection: Binding<String> {
        Binding(
            get: { library.selectedLibrary ?? library.libraries.first ?? "" },
            set: { newValue in Task { await library.selectLibrary(newValue) } }
        )
    }

    private var serverSelection: Binding<UUID> {
        Binding(
            get: { serverStore.selectedServerId ?? serverStore.servers.first?.id ?? UUID() },
            set: { newId in
                guard let server = serverStore.servers.first(where: { $0.id == newId }) else { return }
                Task { await session.switchServer(to: server) }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(avatarData: session.currentUser?.avatarData, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.currentUser?.name ?? "Unknown")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            if session.currentUser?.isAdmin == true {
                                Text("Administrator").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Button("Edit Profile") { showEdit = true }
                    Button("Change Password") { showPassword = true }
                    NavigationLink("Manage Servers") {
                        ManageServersView(session: session)
                    }
                }
                if !library.libraries.isEmpty || serverStore.servers.count > 1 {
                    Section("Library") {
                        if library.libraries.count > 1 {
                            Picker("Library", selection: librarySelection) {
                                ForEach(library.libraries, id: \.self) { lib in
                                    Text(lib).tag(lib)
                                }
                            }
                        } else if let only = library.libraries.first {
                            HStack {
                                Text("Library")
                                Spacer()
                                Text(only).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if serverStore.servers.count > 1 {
                            Picker("Server", selection: serverSelection) {
                                ForEach(serverStore.servers) { server in
                                    Text(server.name).tag(server.id)
                                }
                            }
                        }
                    }
                }
                Section("Storage") {
                    Button("Clear Image Cache", role: .destructive) {
                        ImageCache.shared.clear()
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) { session.logout() }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showEdit) { EditProfileSheet(session: session) }
            .sheet(isPresented: $showPassword) { ChangePasswordSheet() }
        }
    }
}
