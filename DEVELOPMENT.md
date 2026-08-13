# Development Notes

## Stack

| Layer | Technology |
|---|---|
| Language | Swift 6.0, strict concurrency |
| UI | SwiftUI |
| Minimum target | iOS 17.0 |
| Project generation | [XcodeGen](https://github.com/yonaskolb/XcodeGen) via `project.yml` |
| CI/CD | GitHub Actions (`.github/workflows/build-ios.yml`) |

---

## Project Structure

```
PhotoGalleryFrontend/
  App/          PhotoGalleryFrontendApp.swift · Theme.swift
  Models/       Album · Photo · User
  Networking/   APIClient · ImageCache · KeychainHelper · PhotoServerAPI
  ViewModels/   AlbumsViewModel · LibraryViewModel · PhotoDetailViewModel
                PhotoGridViewModel · ProfileViewModel · SessionStore
  Views/
    Albums/     AddToAlbumSheet · AlbumDetailView · AlbumListView · CreateAlbumSheet
    Auth/       LoginView · ServerSetupView · SignupView
    Detail/     PhotoDetailPagerView · TagEditorSheets · ZoomableImageView
    Favorites/  FavoritesView
    Gallery/    FolderPickerView · GalleryView · PhotoThumbnailView
    Main/       MainTabView
    Profile/    ChangePasswordSheet · EditProfileSheet · ProfileView
    Root/       RootView
    Shared/     AsyncPhotoImage · EmptyStateView
public/         PWA/web icons — pwa-512x512.png is the app icon source
```

---

## Authentication — JWT Bearer Tokens

The backend issues **JWT Bearer tokens**, not session cookies.

| Endpoint | Response |
|---|---|
| `POST /api/auth/login` | `{ token, user }` |
| `POST /api/auth/signup` | `{ token, user, role }` |
| All protected routes | require `Authorization: Bearer <token>` |

Token lifetime is **30 days**. The client stores the token in the Keychain under the key `authJWT` via `APIClient.setAuthToken()`. `APIClient.rawRequest()` injects the header automatically on every request.

### Session lifecycle (`SessionStore`)

```
App launch
  └─ bootstrap()
       ├─ no server URL → phase = .needsServer
       ├─ cached user found → phase = .authenticated (immediate), then refreshUser()
       └─ no cached user  → refreshUser()

refreshUser()
  ├─ /me succeeds     → update currentUser, phase = .authenticated
  ├─ 401 / 403        → clear token + cache, phase = .needsLogin
  └─ network error    → keep existing phase (don't log out cached user)
```

---

## Image Loading & Caching

`AsyncPhotoImage` is a custom view backed by `ImageCache` (an `NSCache<NSString, UIImage>` singleton, 150 MB / 300 item limit). It replaces `AsyncImage` to provide reliable in-memory caching between views.

- Images are keyed by their absolute URL string.
- `ImageCache.shared.clear()` wipes the memory cache **and** `URLCache.shared` disk entries.
- A **Clear Image Cache** button is exposed in `ProfileView → Storage`.

### Which URL to use

| Context | Field |
|---|---|
| Grid thumbnail | `photo.thumbUrl` |
| Full-screen viewer | `photo.previewUrl` |
| Never load in-app | `photo.originalUrl` (too large) |

---

## Square Thumbnail Grid

`PhotoThumbnailView` uses `GeometryReader` with an **explicit** `frame(width: geo.size.width, height: geo.size.width)` on the image. This is the only reliable pattern — `frame(maxWidth: .infinity)` on a `Group`-wrapped view does not propagate the square constraint predictably in SwiftUI.

```swift
GeometryReader { geo in
    AsyncPhotoImage(...)
        .frame(width: geo.size.width, height: geo.size.width)
        .clipped()
}
.aspectRatio(1, contentMode: .fit)   // ← must be outside GeometryReader
```

---

## Photo Detail — Swipe & Zoom

`PhotoDetailPagerView` wraps photos in a `TabView(.page)` for horizontal swiping.

`ZoomableImageView` uses `MagnifyGesture` (iOS 17) with focal-point-aware offset math so pinch-zoom centres on the touch point rather than the image centre:

```
ratio  = newScale / lastScale
offset = focal × (1 − ratio) + lastOffset × ratio
```

where `focal` is `(startAnchor − 0.5) × viewSize` (displacement from centre).

The pan `DragGesture` is registered with `.including: scale > 1 ? .all : .none` — when the image is at normal scale the gesture is fully disabled so the `TabView` page-swipe can take over.

---

## Backend

A separate Node service. Full contract, data model and known gaps live in
[BACKEND_SPECIFICATION.md](BACKEND_SPECIFICATION.md) — read that before changing anything in
[Networking/](PhotoGalleryFrontend/Networking/).

| Layer | Technology |
|---|---|
| API | Fastify, bound to `127.0.0.1:3000` (nginx proxies `/api/*`) |
| Storage | SQLite via `better-sqlite3` (synchronous), written by a separate indexer process |
| Image bytes | Served by **nginx**, never by Fastify — `/thumbs/`, `/previews/`, `/originals/` |
| Auth | JWT HS256, 30-day expiry |
| Live docs | Swagger UI at `/api/docs` |

The API only ever returns *paths*. `AsyncPhotoImage` resolves them against the configured base
URL and fetches them with a bare `URLSession` — **no `Authorization` header**, so the static
image locations must stay publicly readable.

### API Reference

All endpoints are relative to the configured base URL. 🔒 = requires a Bearer token.

```
GET    /api/health

🔒 GET  /api/auth/me                → { user }
POST   /api/auth/login              body: { name, password }        → { token, user }
POST   /api/auth/signup             body: { name, password }        → { token, user, role }
🔒 PATCH /api/auth/me               body: { name?, avatarData? }    → { ok, user }
🔒 PATCH /api/auth/me/password      body: { currentPassword?, newPassword }

GET    /api/libraries?user_id=
GET    /api/folders?library=
GET    /api/photos?library=&folder=&limit=&offset=&sort=&order=&favorite=&tag=
GET    /api/photos/:id              → photo + cameraMake/cameraModel/tags
PATCH  /api/photos/:id/favorite     body: { favorite: bool }
POST   /api/photos/:id/tags         body: { tag }
DELETE /api/photos/:id/tags/:tag

GET    /api/albums?user_id=         ← user_id is required
POST   /api/albums                  body: { name, tag?, user_id, shared: 0|1 }
PATCH  /api/albums/:id              body: { shared: 0|1 }   ← only `shared` is updatable
DELETE /api/albums/:id
GET    /api/albums/:id/photos
POST   /api/albums/:id/photos       body: { photoIds: [string] }

🔒👑 GET/POST /api/admin/users · PATCH/DELETE /api/admin/users/:id
🔒👑 POST /api/admin/users/:id/password · GET /api/admin/libraries
```

Only `/api/auth/me*` and `/api/admin/*` are actually protected — every photo, folder, library
and album route is reachable **without a token**, and `user_id` is taken from the query string
rather than the JWT. Treat that as a known hole, not as license to add more of it; see §7.6 of
the spec.

The admin endpoints exist server-side but the app has **no admin UI**, so library grants can
only be made with a direct API call.

### Gotchas that bite the client

- **`AlbumsViewModel.load(userId:)` must always be passed `session.currentUser?.id`** — including
  in `AddToAlbumSheet`. Omitting it returns `400 user_id required`; passing the wrong one
  silently returns someone else's albums.
- **`POST /api/albums` doesn't return `created_at`**, but `Album.createdAt` is non-optional, so
  creating an album *always* fails to decode and shows an error even though the album was
  created. Fix on the backend (return the inserted row) or make the field optional.
- **`allowedFolders` ≠ `folders`.** The backend sends `allowedFolders`;
  [User.swift](PhotoGalleryFrontend/Models/User.swift#L41) decodes `folders`, so it is always `nil`.
- **`favorite` is presence-based** — the backend filters to favorites if the key exists at all,
  whatever its value. Send it only when filtering; `PhotoGridViewModel` already does.
- **`favorite` and tags are global, not per-user.** One user's Favorites tab is everyone's.
- **`shared` is sent as an integer** (`0`/`1`); a JSON boolean is rejected by the schema.
- **Album ordering is undefined.** `album_photos.position` is read but never written.
- **A new self-signup user has no library grants**, so `/api/libraries` returns `[]` and the
  gallery is empty with no in-app way out.
- **Response schemas strip undeclared fields.** If a backend field doesn't reach the app, check
  the route's `response` schema before suspecting the handler.

---

## GitHub Actions Build

### Workflow inputs

| Input | xcodebuild override | Effect |
|---|---|---|
| `version` | `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` | Version shown in the App Store / Settings |
| `app_name` | `PRODUCT_NAME` | Display name under the icon (`CFBundleDisplayName = $(PRODUCT_NAME)`) |
| `bundle_id` | `PRODUCT_BUNDLE_IDENTIFIER` | App bundle ID |

### App icon

The workflow scales `public/pwa-512x512.png` to 1024×1024 via `sips` and writes it to `AppIcon.appiconset/AppIcon.png` before generating the Xcode project. The asset catalog uses the single-image universal format (iOS 17+), so only the 1024×1024 file is required.

The same `AppIcon.png` (at 512×512) is committed to the repo as a local-build placeholder.

### Producing the IPA

The archive is built with `CODE_SIGNING_ALLOWED=NO` (no provisioning profile required). The `.app` bundle is located with `find … -name '*.app'` rather than a hardcoded path so it survives `app_name` renames.
