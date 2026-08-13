import SwiftUI

struct PhotoDetailPagerView: View {
    let photos: [Photo]
    let startPhoto: Photo
    var onFavoriteToggled: (Photo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentId: String
    @State private var detailVM = PhotoDetailViewModel()
    @State private var showTagEditor = false
    @State private var showInfo = false
    @State private var dismissProgress: CGFloat = 0
    @State private var toastMessage: String?

    init(photos: [Photo], startPhoto: Photo, onFavoriteToggled: @escaping (Photo) -> Void) {
        self.photos = photos
        self.startPhoto = startPhoto
        self.onFavoriteToggled = onFavoriteToggled
        _currentId = State(initialValue: startPhoto.id)
    }

    private var currentPhoto: Photo? { photos.first { $0.id == currentId } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(1 - Double(dismissProgress) * 0.6)
            TabView(selection: $currentId) {
                ForEach(photos) { photo in
                    ZoomableImageView(
                        path: photo.previewUrl,
                        thumbnailPath: photo.thumbUrl,
                        onDismissProgress: { dismissProgress = $0 },
                        onDismiss: { dismiss() }
                    )
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task(id: currentId) {
                dismissProgress = 0
                await detailVM.load(id: currentId)
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
                Task { await detailVM.toggleFavorite() }
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
        VStack(alignment: .leading, spacing: 6) {
            if let detail = detailVM.detail {
                Text(detail.filename).font(.headline).foregroundStyle(.white)
                if let make = detail.cameraMake, let model = detail.cameraModel {
                    Text("\(make) \(model)").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                if let taken = detail.takenAt {
                    Text(taken).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                if let width = detail.width, let height = detail.height {
                    Text("\(width) × \(height)").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}