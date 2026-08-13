import SwiftUI

struct ProfileView: View {
    var session: SessionStore
    @State private var showEdit = false
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)
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
