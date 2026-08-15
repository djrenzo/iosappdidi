# TODO

Backend/frontend contract issues found while writing [BACKEND_SPECIFICATION.md](BACKEND_SPECIFICATION.md).
Section refs point there for full detail.

## Bugs (user-visible)

- [x] **Favorites don't update without an app restart.** Two causes, both fixed:
      (1) `PhotoGridViewModel.toggleFavorite` matched photos by full-struct equality and derived
      the new value from a possibly-stale caller-supplied copy, so a second toggle on the same
      photo within one detail-view session silently no-op'd on the in-memory grid (the API call
      still succeeded). Now looks up by `id` and flips the grid's own current value.
      (2) Gallery and Favorites tabs each own a separate `PhotoGridViewModel` loaded once via
      `.task`, so a favorite toggled in one tab never appeared in the other until relaunch. Both
      views now reload `onAppear` (which SwiftUI fires on every tab reselect, not just the first).
- [x] **Album creation always shows an error.** Fixed on the backend — `POST /api/albums` now
      returns the inserted row (including `created_at`/`owner_id`) with a matching response
      schema, e.g. `{"id":16,"name":"test","created_at":"2026-08-14 08:03:39","tag":null,
      "owner_id":"e8442e19-...","shared":false}` — matches `Album.swift`'s `CodingKeys` exactly,
      no client changes needed. (spec §7.1)
- [x] **Folder/tag/library names containing `+` (or `&`, `=`) silently failed to filter.**
      `URLQueryItem`'s plain `queryItems` setter deliberately leaves those characters unescaped
      (Apple's own docs note it can't tell delimiter from data), and an unescaped `+` gets
      decoded back to a space by the server's standard query parser — so a folder like
      "2015/Amerika + Aruba 2015" arrived at the backend as "2015/Amerika   Aruba 2015" and never
      matched, silently returning zero photos. Fixed in `APIClient.rawRequest` by percent-encoding
      every query value ourselves (RFC 3986 unreserved characters only) and assigning
      `percentEncodedQueryItems` directly instead.
- [x] **`allowedFolders` vs `folders` mismatch.** Backend sends `allowedFolders`; `User.swift`
      decoded `folders`, so `User.folders` was always `nil`. Fixed on the Swift side:
      `CodingKeys` now maps `folders = "allowedFolders"`. (spec §7.2)
- [ ] **Possible double-encoding in `removeTag`.** `PhotoServerAPI.removeTag` percent-encodes the
      tag, then `APIClient`'s `appendingPathComponent`/`URLComponents` may encode again — tags
      with spaces or special characters could 404. Needs a device/simulator check.
- [x] **Photo detail swipe gestures were laggy on large folders/"all photos" — confirmed fixed
      on-device.** `TabView(.page)` in `PhotoDetailPagerView` didn't virtualize its
      `ForEach(photos)` the way `LazyVGrid`/`List` do, so SwiftUI's diffing/layout work scaled with
      the *entire* photos array, which only grows as the grid pages in more. Two windowing
      attempts each caused their own regression (hung transitions, then black-flash-on-swipe — see
      git history if resurrecting either matters). Fixed by replacing `TabView(.page)` + `ForEach`
      entirely with a hand-built
      [PagedPhotoView.swift](PhotoGalleryFrontend/Views/Detail/PagedPhotoView.swift) — a
      `UIViewControllerRepresentable` wrapping `UIPageViewController`, with each page a
      `UIHostingController<ZoomableImageView>` created on demand via the datasource's
      before/after-by-index lookups. At most 1–3 pages ever exist regardless of array size, fixing
      the root cause directly instead of working around `TabView(.page)`'s bridging. Page-swiping
      is explicitly disabled while any mounted page is pinch-zoomed (`ZoomableImageView` gained an
      `onScaleChanged` callback, aggregated in the coordinator, toggling the page view controller's
      internal `UIScrollView.isScrollEnabled`, found via a subview search since it isn't exposed
      publicly). Confirmed working: lag gone, left/right swipe works.

- [x] **Swipe-down-to-dismiss background wasn't fading to transparent — confirmed fixed
      on-device.** `.fullScreenCover` doesn't keep the presenting view composited behind it by
      default, so even a genuinely-transparent `Color.black` had nothing behind it to reveal —
      survived two rounds of fixing the opacity math and the crossfade's animation mechanism
      first, since neither touched the actual (presentation-level, not content-level) cause. Fixed
      by adding `.presentationBackground(.clear)` (iOS 16.4+) to `PhotoDetailPagerView`. Confirmed
      working — gallery now visible through the fade during the drag.

- [x] **Gallery frozen/unresponsive for ~1s right after dismissing — fixed, unverified.** Once
      transparency was fixed above, a leftover workaround from *before* that fix became actively
      harmful: `dismissGesture`'s commit path wrapped `onDismiss()` in a `Task { try? await
      Task.sleep(50ms) }` and `PhotoDetailPagerView` wrapped `dismiss()` in
      `withTransaction(Transaction(animation: nil))` — both added to avoid the system's dismiss
      transition snapshotting a stale opaque frame, which is no longer a concern now that
      `.presentationBackground(.clear)` handles transparency at the presentation level rather than
      depending on catching our content's latest rendered frame. Forcing a zero-duration dismiss
      via `withTransaction(animation: nil)` is a known way to get UIKit's transition coordinator
      into an inconsistent state about when a transition is "complete" and safe to re-enable
      interaction for — a plausible match for the freeze. Removed both; `onDismiss()` and
      `dismiss()` are now called directly, letting the system's normal (now-correct) dismiss
      handling run. Not yet re-tested on-device.

## Security (data plane has no auth)

- [ ] Require a Bearer token on all of `/api/photos*`, `/api/folders`, `/api/libraries`,
      `/api/albums*` — today only `/api/auth/me*` and `/api/admin/*` are protected.
- [ ] Stop taking `user_id` from the query string (`/api/libraries`, `/api/albums`,
      `POST /api/albums`); derive identity from `request.authUser.id` instead.
- [ ] Add a `canAccessLibrary(user, db)` check and apply it to `/api/folders`, `/api/photos`,
      `/api/photos/:id`.
- [ ] Enforce `owner_id` on album writes (`PATCH`, `DELETE`, `POST /:id/photos`) and reads
      (`GET /:id/photos` — owner or `shared = 1`).
- [ ] Decide on auth for image bytes (`/thumbs/`, `/previews/`, `/originals/` are unauthenticated
      at the nginx layer) — signed URLs or `auth_request`, plus teaching `AsyncPhotoImage` to
      send a header if needed.
- [ ] Tighten CORS from `origin: true` to real origins.
- [ ] Turn on TLS on nginx — app currently ships `NSAllowsArbitraryLoads: true` and defaults to
      plain `http://`, so the JWT travels in cleartext on the LAN.
      (spec §7.6 has the full ordered plan; steps 1–2 are breaking client changes)

## Design gaps

- [x] **Favorites are now per-user.** Backend moved `favorite` off the shared `photos` column
      onto a `user_favorites` join table: new `GET /api/favorites?user_id=` (flat array, newest-
      taken first, not library-scoped), `PATCH /api/photos/:id/favorite` now requires `user_id`
      in the body, and `GET /api/photos`, `GET /api/photos/:id`, `GET /api/albums/:id/photos` all
      accept an optional `user_id` to resolve each photo's `favorite` flag per-user. Client fully
      updated — `PhotoGridViewModel` branches between the paginated grid endpoint and the flat
      favorites endpoint; `PhotoDetailViewModel`/`AlbumDetailViewModel` thread `userId` through.
      **Tags are still global** — this only covers the favorites half of §7.3.
- [x] `favorite=true` filter param on `GET /api/photos` removed (superseded by the dedicated
      `/api/favorites` endpoint above) — the presence-vs-value bug from §7.4 no longer applies
      since the param doesn't exist anymore.
- [ ] Give new self-signup users either a default library grant, an invite/approval flow, or an
      admin UI — right now they land in a permanently empty gallery. (spec §7.5)
- [ ] Write `album_photos.position` on insert (or drop the `ORDER BY position` pretence) — album
      photo order is currently undefined.
- [ ] 404 `POST /api/photos/:id/tags` and `POST /api/albums/:id/photos` for nonexistent parent
      ids instead of always returning `ok: true`.
- [ ] Add a body schema to `PATCH /api/admin/users/:id` (currently unvalidated).
- [ ] Guard `verifyPassword` against a malformed stored hash (`timingSafeEqual` throws on
      mismatched lengths → 500 instead of 401).
- [ ] Allow deleting tags containing `/` (move tag name off the URL path for `DELETE`).

## Missing endpoints

- [ ] `GET /api/tags` (optionally `?library=`) — needed for tag autocomplete / browse-by-tag.
- [x] **`DELETE /api/albums/:id/photos`, body `{ photoIds: [string] }`.** Added on the backend —
      the app's "Select Photos" / "Remove N from Album" flow in `AlbumDetailView`
      (`PhotoServerAPI.removePhotos(albumId:photoIds:)`) is now live end-to-end. Worth a quick
      on-device check that it's actually scoped to the album's owner per §7.6, since that
      restriction isn't visible from the client side.
- [ ] `PATCH /api/albums/:id` accepting `name` — album rename.
- [ ] **`limit` param on `GET /api/albums/:id/photos`** (e.g. `?limit=4`). `AlbumCard` now
      renders a 4-thumbnail collage cover (client-side, see `AlbumListView.AlbumCoverView`), but
      since this route always returns the full album with no limit support, building one cover
      fetches every photo in every album just to keep the first 4 — fine for small albums, wasteful
      for large ones. A `limit` param (and ideally a lightweight cover endpoint on `GET /api/albums`
      itself) would let the album grid load without full per-album fetches, and would also give
      `AlbumCard` a real photo count for free.
- [ ] `GET /api/photos?q=` search over filename/folder/tags.
- [ ] `POST /api/auth/logout` / token revocation — sign-out is client-side only today; a stolen
      JWT stays valid for its full 30-day lifetime.

## Operational

- [ ] **The API hangs entirely while the indexer runs.** Confirmed expected given the current
      architecture: `better-sqlite3` is synchronous (blocks the API's whole event loop per
      query), and the API + indexer are separate processes sharing one SQLite file via the same
      `openDb()`. Without WAL mode, the indexer's write transaction(s) hold an exclusive lock the
      API's reads either block on or get `SQLITE_BUSY` from — freezing every endpoint for every
      client, not just one request. Needs verifying against the indexer/`db.js` source (not in
      this repo) and likely fixing with `PRAGMA journal_mode = WAL`, a `busy_timeout` pragma on
      the API's connection, and/or having the indexer commit in smaller batches instead of one
      transaction per scan. See spec §9 for the full writeup.

## Housekeeping

- [ ] Rename `photos.db` / `user_folders.folder` — both hold a *library* name, not a filesystem
      folder, which is confusing next to `photos.folder` which really is one.
- [ ] Add `'Libraries'` to the Swagger `tags` array (currently renders ungrouped).
- [ ] Remove unused `path` import in `server.js`.
- [ ] Build an admin UI in the app — the backend already has `/api/admin/*` but nothing calls it.
