import SwiftUI

struct PhotoDetailPagerView: View {
    let photos: [Photo]
    let startPhoto: Photo
    var onFavoriteToggled: (Photo) -> Void
    let userId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var currentId: String
    @State private var detailVM = PhotoDetailViewModel()
    @State private var showTagEditor = false
    @State private var showInfo = false
    @State private var dismissProgress: CGFloat = 0
    @State private var toastMessage: String?

    init(photos: [Photo], startPhoto: Photo, onFavoriteToggled: @escaping (Photo) -> Void, userId: String?) {
        self.photos = photos
        self.startPhoto = startPhoto
        self.onFavoriteToggled = onFavoriteToggled
        self.userId = userId
        _currentId = State(initialValue: startPhoto.id)
    }

    private var currentPhoto: Photo? { photos.first { $0.id == currentId } }

    /// `TabView(.page)` doesn't virtualize its `ForEach` the way `LazyVGrid`/`List` do — handing
    /// it the *entire* photos array (which only ever grows as the grid pages in more) makes
    /// SwiftUI's diffing/layout work scale with total library size, and since gesture tracking
    /// rides the same render loop, swipes and the dismiss drag get progressively choppier the
    /// more has been scrolled through. Windowing to a handful of photos around the current one —
    /// recomputed each time `currentId` lands on a new photo — keeps the TabView's child count
    /// constant no matter how large the underlying array is.
    private var windowedPhotos: [Photo] {
        guard let currentIndex = photos.firstIndex(where: { $0.id == currentId }) else {
            return [startPhoto]
        }
        let radius = 3
        let lower = max(0, currentIndex - radius)
        let upper = min(photos.count - 1, currentIndex + radius)
        return Array(photos[lower...upper])
    }

    var body: some View {
        ZStack {
            // Must reach fully transparent (not just dimmed) by dismissProgress == 1 — the
            // dismiss gesture forces progress to 1 right as it triggers dismiss(), and anything
            // still visible here at that instant gets caught in the fullScreenCover's own
            // system dismiss transition, showing up as a separate black backdrop sliding away
            // after the drag has already finished.
            Color.black.ignoresSafeArea()
                .opacity(1 - Double(dismissProgress))
            TabView(selection: $currentId) {
                ForEach(windowedPhotos) { photo in
                    ZoomableImageView(
                        path: photo.previewUrl,
                        thumbnailPath: photo.thumbUrl,
                        onDismissProgress: { dismissProgress = $0 },
                        onDismiss: {
                            // The drag already animated the photo off-screen interactively —
                            // letting the fullScreenCover *also* run its own default dismiss
                            // transition on top just replays a second, redundant animation and
                            // keeps the gallery underneath non-interactive until it finishes.
                            withTransaction(Transaction(animation: nil)) {
                                dismiss()
                            }
                        }
                    )
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task(id: currentId) {
                dismissProgress = 0
                await detailVM.load(id: currentId, userId: userId)
            }

            VStack {
                topBar
                Spacer()
                if let toastMessage {
                    Text(toastMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if showInfo { infoPanel }
                bottomBar
            }
            .opacity(max(0, 1 - Double(dismissProgress) * 2))
            .animation(.easeOut(duration: 0.2), value: toastMessage)
        }
        .sheet(isPresented: $showTagEditor) { TagEditorSheet(viewModel: detailVM) }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline)
            }
            Spacer()
            Button { showInfo.toggle() } label: {
                Image(systemName: "info.circle")
            }
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(20)
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var bottomBar: some View {
        HStack(spacing: 36) {
            Button {
                guard let photo = currentPhoto else { return }
                onFavoriteToggled(photo)
                Task { await detailVM.toggleFavorite(userId: userId) }
            } label: {
                Image(systemName: (detailVM.detail?.favorite ?? currentPhoto?.favorite ?? false) ? "heart.fill" : "heart")
                    .foregroundStyle((detailVM.detail?.favorite ?? currentPhoto?.favorite ?? false) ? Theme.favorite : .white)
            }
            Button { showTagEditor = true } label: {
                Image(systemName: "tag")
            }
            Button {
                Task { await downloadOriginal() }
            } label: {
                if detailVM.isDownloading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .disabled(detailVM.isDownloading)
        }
        .font(.title2)
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }

    private func downloadOriginal() async {
        await detailVM.downloadOriginal(fallbackOriginalUrl: currentPhoto?.originalUrl)
        toastMessage = detailVM.downloadSucceeded ? "Saved to Photos" : detailVM.errorMessage
        detailVM.errorMessage = nil
        guard toastMessage != nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        toastMessage = nil
    }

    private var infoPanel: some View {
        Group {
            if let detail = detailVM.detail {
                VStack(alignment: .leading, spacing: 14) {
                    Text(detail.filename)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    VStack(alignment: .leading, spacing: 9) {
                        if let dateText = detail.takenAtDate?.formatted(date: .long, time: .shortened) {
                            infoRow(icon: "calendar", text: dateText)
                        }
                        infoRow(icon: "folder", text: folderDisplayText(detail))
                        if let make = detail.cameraMake, let model = detail.cameraModel {
                            infoRow(icon: "camera", text: "\(make) \(model)")
                        }
                        if let width = detail.width, let height = detail.height {
                            infoRow(icon: "aspectratio", text: "\(width) × \(height)")
                        }
                    }
                }
                .padding(18)
            } else {
                ProgressView().tint(.white).padding(18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func folderDisplayText(_ detail: PhotoDetail) -> String {
        var parts: [String] = []
        if let db = detail.db, !db.isEmpty { parts.append(db) }
        if !detail.folder.isEmpty { parts.append(detail.folder) }
        return parts.isEmpty ? "Library Root" : parts.joined(separator: " › ")
    }
}