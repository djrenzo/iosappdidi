import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var isSaving = false
    var errorMessage: String?
    var successMessage: String?

    private let api = PhotoServerAPI()

    func updateProfile(name: String, session: SessionStore) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let user = try await api.updateProfile(name: name, avatarData: nil)
            session.updateCachedUser(user)
            successMessage = "Profile updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func changePassword(current: String, newPassword: String) async {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }
        do {
            try await api.changePassword(current: current.isEmpty ? nil : current, newPassword: newPassword)
            successMessage = "Password changed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}