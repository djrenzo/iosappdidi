import SwiftUI

struct PhotoThumbnailView: View {
    let photo: Photo
    var isSelected: Bool = false
    var selectionMode: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                AsyncPhotoImage(path: photo.thumbUrl) {
                    Rectangle().fill(Theme.surfaceElevated)
                }
                // Explicit square frame guarantees proper fill-and-clip regardless of image ratio
                .frame(width: geo.size.width, height: geo.size.width)
                .clipped()

                if photo.favorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Theme.favorite, in: Circle())
                        .padding(6)
                }

                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.accent : .white)
                        .background(Circle().fill(isSelected ? .white : .black.opacity(0.3)).padding(1))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 3)
        )
    }
}
