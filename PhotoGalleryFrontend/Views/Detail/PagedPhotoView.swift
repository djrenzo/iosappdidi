import SwiftUI
import UIKit

/// A manually-controlled `UIPageViewController` wrapper for swiping between photos, replacing
/// SwiftUI's `TabView(.page)`. `TabView(.page)` doesn't virtualize its `ForEach` — handing it a
/// large photos array made its diffing/layout cost (and, since gesture tracking rides the same
/// render loop, swipe/dismiss responsiveness) scale with total library size, and two separate
/// attempts at windowing the `ForEach` down each caused their own distinct regressions (see
/// TODO.md). `UIPageViewController` only ever keeps 1–3 pages alive via its datasource,
/// regardless of array size — this fixes the root cause directly instead of working around
/// SwiftUI's bridging.
struct PagedPhotoView: UIViewControllerRepresentable {
    let photos: [Photo]
    @Binding var currentId: String
    let onDismissProgress: (CGFloat) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.view.backgroundColor = .clear

        if let startController = context.coordinator.makeController(forId: currentId) {
            pageViewController.setViewControllers([startController], direction: .forward, animated: false)
        }
        context.coordinator.scrollView = Self.findScrollView(in: pageViewController.view)
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        // The coordinator reads `parent` fresh on every callback (see PhotoPageViewController's
        // closures below), so this is the only wiring needed to keep it pointed at the latest
        // closures/photos across SwiftUI re-renders — no need to push `currentId` back into the
        // page view controller here, since the only thing that ever changes it is this view's
        // own delegate callback in the first place.
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// `UIPageViewController` doesn't expose its internal scroll view publicly, but with
    /// `.scroll` transition style it always backs its content with exactly one — this is a
    /// long-standing, widely-used technique to reach it. Used to disable page-swiping while
    /// zoomed in, so pinch/pan on the photo doesn't compete with turning the page.
    private static func findScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedPhotoView
        weak var scrollView: UIScrollView?
        /// Photo ids of currently-mounted pages that report themselves as zoomed in —
        /// page-swiping is disabled while this isn't empty. Keyed by id (rather than a plain
        /// count) so each page's `ZoomableImageView` can report its own state idempotently via
        /// `Set.insert`/`.remove`, without needing to track "was I zoomed before" itself.
        private var zoomedPhotoIds: Set<String> = []

        init(parent: PagedPhotoView) {
            self.parent = parent
        }

        fileprivate func makeController(forId id: String) -> PhotoPageViewController? {
            guard let photo = parent.photos.first(where: { $0.id == id }) else { return nil }
            return PhotoPageViewController(photo: photo, coordinator: self)
        }

        private func controller(offsetBy offset: Int, from viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? PhotoPageViewController,
                  let index = parent.photos.firstIndex(where: { $0.id == current.photoId }) else {
                return nil
            }
            let targetIndex = index + offset
            guard parent.photos.indices.contains(targetIndex) else { return nil }
            return PhotoPageViewController(photo: parent.photos[targetIndex], coordinator: self)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            controller(offsetBy: -1, from: viewController)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            controller(offsetBy: 1, from: viewController)
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let visible = pageViewController.viewControllers?.first as? PhotoPageViewController else { return }
            parent.currentId = visible.photoId
        }

        /// Called by a page's `ZoomableImageView` whenever its zoom state changes — disables
        /// page-swiping while any mounted page is zoomed in, so panning around a zoomed photo
        /// doesn't compete with turning the page.
        fileprivate func setZoomed(_ isZoomed: Bool, for photoId: String) {
            if isZoomed {
                zoomedPhotoIds.insert(photoId)
            } else {
                zoomedPhotoIds.remove(photoId)
            }
            scrollView?.isScrollEnabled = zoomedPhotoIds.isEmpty
        }
    }
}

/// A `UIHostingController` wrapping one photo's `ZoomableImageView`, tagged with its photo id so
/// the coordinator can look up neighbors by array index without holding a reference back to a
/// specific `Photo` value.
private final class PhotoPageViewController: UIHostingController<ZoomableImageView> {
    let photoId: String

    init(photo: Photo, coordinator: PagedPhotoView.Coordinator) {
        self.photoId = photo.id
        // `super.init` hasn't run yet at this point, so nothing here can capture `self`
        // (including `self.photoId`, just assigned above) — this local copy is what the
        // closure below captures instead.
        let photoId = photo.id
        super.init(rootView: ZoomableImageView(
            path: photo.previewUrl,
            thumbnailPath: photo.thumbUrl,
            onDismissProgress: { [weak coordinator] progress in coordinator?.parent.onDismissProgress(progress) },
            onDismiss: { [weak coordinator] in coordinator?.parent.onDismiss() },
            onScaleChanged: { [weak coordinator] zoomed in
                coordinator?.setZoomed(zoomed, for: photoId)
            }
        ))
        view.backgroundColor = .clear
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
