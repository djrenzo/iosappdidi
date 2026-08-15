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
  Models/       Album · Photo · Server · User
  Networking/   APIClient · ImageCache · KeychainHelper · PhotoServerAPI · ServerStore
  ViewModels/   AlbumsViewModel · LibraryViewModel · PhotoDetailViewModel
                PhotoGridViewModel · ProfileViewModel · SessionStore
  Views/
    Albums/     AddToAlbumSheet · AlbumDetailView · AlbumListView · CreateAlbumSheet
    Auth/       LoginView · ServerSetupView · SignupView
    Detail/     PhotoDetailPagerView · TagEditorSheets · ZoomableImageView
    Favorites/  FavoritesView
    Gallery/    FolderPickerView · GalleryView · PhotoThumbnailView
    Main/       MainTabView
    Profile/    ChangePasswordSheet · EditProfileSheet · ManageServersView · ProfileView
    Root/       RootView
    Shared/     AsyncPhotoImage · AvatarView · EmptyStateView
public/         PWA/web icons — pwa-512x512.png is the app icon source
```

---

## Multi-server support (`ServerStore`)

The app supports multiple named server connections (Profile → Manage Servers to add/remove,
Profile → Server picker to switch — the picker only appears once 2+ servers exist). `ServerStore`
persists `[Server]` (`id`, `name`, `host`) plus the selected id to `UserDefaults`, as a plain
`@unchecked Sendable` `@Observable` singleton (matching `APIClient`/`ImageCache`'s existing
concurrency pattern rather than `@MainActor`-isolating it, so `APIClient` can read
`selectedServer` synchronously from any context).

**Auth is namespaced per server id** — the Keychain-stored JWT (`authJWT_<serverId>`) and cached
user (`cachedUser_<serverId>`) both key off `ServerStore.shared.selectedServer.id`, since a token
issued by one server's `users` table is meaningless (usually outright invalid) against another.
Practically: switching to a server you've logged into before restores that session instantly;
switching to a new one prompts login. `SessionStore.switchServer(to:)` and `.deleteServer(_:)`
both re-run `bootstrap()` after changing the active server — that transition through
`phase = .checking` is also what makes `RootView` tear down and rebuild `MainTabView` from
scratch, which is what clears out the previous server's stale `LibraryViewModel`/album data
without needing to reset each view model by hand.

A **first-launch install** creates its first `Server` (default name "Home") from
`ServerSetupView` via `SessionStore.configureServer(name:host:)`. An **existing install**
upgrading from before multi-server support migrates automatically — `ServerStore` wraps
whatever was in the old single `serverBaseURL` default into a "Home" entry the first time it
loads — so nothing needs to change from the user's side.

---

## Authentication — JWT Bearer Tokens

The backend issues **JWT Bearer tokens**, not session cookies.

| Endpoint | Response |
|---|---|
| `POST /api/auth/login` | `{ token, user }` |
| `POST /api/auth/signup` | `{ token, user, role }` |
| All protected routes | require `Authorization: Bearer <token>` |

Token lifetime is **30 days**. The client stores the token in the Keychain under a per-server key
(`authJWT_<serverId>`, see above) via `APIClient.setAuthToken()`. `APIClient.rawRequest()`
injects the header automatically on every request.

### Session lifecycle (`SessionStore`)

```
App launch
  └─ bootstrap()
       ├─ no server selected → phase = .needsServer
       ├─ cached user found (for this server) → phase = .authenticated (immediate), then refreshUser()
       └─ no cached user  → refreshUser()

refreshUser()
  ├─ /me succeeds     → update currentUser, phase = .authenticated
  ├─ 401 / 403        → clear token + cache, phase = .needsLogin
  └─ network error    → keep existing phase (don't log out cached user)
```

---

## Image Loading & Caching

`AsyncPhotoImage` is a custom view backed by `ImageCache`, a two-tier cache: an `NSCache<NSString, UIImage>` (150 MB / 300 item limit) for fast in-session reuse, backed by a disk directory under the app's Caches folder so images survive relaunches. It replaces `AsyncImage` to provide reliable caching between views and across launches.

- Images are keyed by their absolute URL string, hashed (SHA256) into the on-disk filename — URL
  strings aren't filename-safe as-is, and hashing sidesteps escaping edge cases entirely.
- `ImageCache.image(for:)` is a synchronous, memory-only lookup (safe on a hot path like grid
  scrolling); `ImageCache.diskImage(for:)` is the `async`, disk-backed fallback on a memory miss —
  deliberately not `@MainActor`, so a disk read never blocks `AsyncPhotoImage`'s `@MainActor`
  loader. `AsyncPhotoImage.loadImage()` checks memory, then disk, then the network, in that order.
- `store(_:data:for:)` takes the original response `Data`, not a re-encoded `UIImage` — writing
  the exact bytes the server sent avoids re-encoding cost/quality loss and preserves the source
  format (webp, etc.).
- Nothing evicts the disk tier automatically. It only shrinks via `ImageCache.shared.clear()`,
  which wipes the memory cache, the on-disk directory, **and** `URLCache.shared`. A **Clear Image
  Cache** button triggering this is exposed in `ProfileView → Storage`. Since disk entries persist
  indefinitely otherwise, this cache can grow unbounded over time for a large library — there's no
  automatic size cap or LRU eviction on the disk tier, by design (persist-until-manually-cleared).

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
- **Favoriting requires a `userId`.** `PATCH /api/photos/:id/favorite` needs `user_id` in the
  body, and `GET /api/photos`, `GET /api/photos/:id`, `GET /api/albums/:id/photos` all need it as
  a query param to resolve `favorite` correctly per-user — omit it and every photo comes back
  `favorite: false`. Favorites themselves are per-user now; **tags are still global** across
  every user.
- **The Favorites tab hits a different, non-paginated endpoint.** `GET /api/favorites?user_id=`
  returns a flat `Photo[]` (newest-taken first, not library-scoped) — no `limit`/`offset`, no
  `{ total, items }` wrapper, unlike `GET /api/photos`. `PhotoGridViewModel.hasMore` is hardcoded
  `false` in favorites mode for exactly this reason.
- **`shared` is sent as an integer** (`0`/`1`); a JSON boolean is rejected by the schema.
- **Album ordering is undefined.** `album_photos.position` is read but never written.
- **A new self-signup user has no library grants**, so `/api/libraries` returns `[]` and the
  gallery is empty with no in-app way out.
- **Response schemas strip undeclared fields.** If a backend field doesn't reach the app, check
  the route's `response` schema before suspecting the handler.
- **Running the indexer can make the whole API unresponsive** — the app will see this as
  timeouts/hangs on every request, not an error tied to anything the client did. It's a known
  characteristic of the current backend (synchronous `better-sqlite3` + a shared SQLite file with
  the indexer, likely without WAL mode) — see spec §9 before chasing it as a client bug.

---

## GitHub Actions Build

### Workflow inputs

| Input | xcodebuild override | Effect |
|---|---|---|
| `version` | `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` | Version shown in the App Store / Settings |
| `app_name` | `PRODUCT_NAME` | Display name under the icon (`CFBundleDisplayName = $(PRODUCT_NAME)`) |
| `bundle_id` | `PRODUCT_BUNDLE_IDENTIFIER` | App bundle ID |

### App icon

The workflow renders `public/icon.svg` straight to 1024×1024 via `rsvg-convert` (installed via
`brew install librsvg` in the same step) and writes it to `AppIcon.appiconset/AppIcon.png` before
generating the Xcode project — rendering from the vector source instead of upscaling the smaller
PWA PNG (the old approach) avoids the blur an upscale would produce. The asset catalog uses the
single-image universal format (iOS 17+), so only the 1024×1024 file is required.

The same `AppIcon.png` is committed to the repo as a local-build placeholder — regenerate it with
`rsvg-convert -w 1024 -h 1024 public/icon.svg -o PhotoGalleryFrontend/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
if `icon.svg` changes, since nothing does that automatically outside CI.

### Producing the IPA

The archive is built with `CODE_SIGNING_ALLOWED=NO` (no provisioning profile required). The `.app` bundle is located with `find … -name '*.app'` rather than a hardcoded path so it survives `app_name` renames.
