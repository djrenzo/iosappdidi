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
            TabView(selection: $currentId) {
                ForEach(photos) { photo in
                    ZoomableImageView(path: photo.previewUrl)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .task(id: currentId) { await detailVM.load(id: currentId) }

            VStack {
                topBar
                Spacer()
                if showInfo { infoPanel }
                bottomBar
            }
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
        }
        .font(.title2)
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
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