import SwiftUI

/// Loads a photo-server relative URL (thumbUrl/previewUrl/originalUrl) using
/// the configured base URL, since the API returns paths, not absolute URLs.
struct AsyncPhotoImage<Placeholder: View>: View {
    let path: String
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let url = APIClient.shared.absoluteURL(forPath: path) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    ZStack {
                        Theme.surfaceElevated
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.textSecondary)
                    }
                default:
                    placeholder()
                }
            }
        } else {
            placeholder()
        }
    }
}
