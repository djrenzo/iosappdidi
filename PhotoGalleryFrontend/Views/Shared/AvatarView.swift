import SwiftUI

/// Renders a user's avatar from base64-encoded `User.avatarData`, falling back to a
/// placeholder glyph when it's missing or fails to decode.
struct AvatarView: View {
    let avatarData: String?
    var size: CGFloat = 48

    private var uiImage: UIImage? {
        guard let avatarData, !avatarData.isEmpty else { return nil }
        var payload = Substring(avatarData)
        if avatarData.hasPrefix("data:"), let comma = avatarData.firstIndex(of: ",") {
            payload = avatarData[avatarData.index(after: comma)...]
        }
        guard let data = Data(base64Encoded: String(payload)) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(Theme.accent)
                .frame(width: size, height: size)
        }
    }
}
