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
- [ ] **Album creation always shows an error.** `POST /api/albums` doesn't return `created_at`
      (and its response schema would strip it even if it did). `Album.createdAt` is non-optional
      in Swift, so the decode throws right after the album was actually created. Fix on the
      backend — return the inserted row and declare `created_at`/`owner_id` in the schema — or
      make `Album.createdAt` optional in Swift. (spec §7.1)
- [ ] **`allowedFolders` vs `folders` mismatch.** Backend sends `allowedFolders`; `User.swift`
      decodes `folders`, so `User.folders` is always `nil`. Rename one side. (spec §7.2)
- [ ] **Possible double-encoding in `removeTag`.** `PhotoServerAPI.removeTag` percent-encodes the
      tag, then `APIClient`'s `appendingPathComponent`/`URLComponents` may encode again — tags
      with spaces or special characters could 404. Needs a device/simulator check.

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

- [ ] Make favorites and tags per-user instead of global columns on `photos` — right now one
      user's Favorites tab is everyone's. (spec §7.3)
- [ ] Fix `favorite` query filtering to be value-based, not presence-based
      (`?favorite=false` currently returns favorites). (spec §7.4)
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
- [ ] **`DELETE /api/albums/:id/photos`, body `{ photoIds: [string] }`.** The app now has a
      "Select Photos" / "Remove N from Album" flow in `AlbumDetailView` that calls
      `PhotoServerAPI.removePhotos(albumId:photoIds:)` against this route — it 404s until the
      backend adds it. Mirror `POST /api/albums/:id/photos`: delete matching
      `(album_id, photo_id)` rows from `album_photos`, return `{ ok: true }`, and (per §7.6)
      restrict to the album's owner.
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

## Housekeeping

- [ ] Rename `photos.db` / `user_folders.folder` — both hold a *library* name, not a filesystem
      folder, which is confusing next to `photos.folder` which really is one.
- [ ] Add `'Libraries'` to the Swagger `tags` array (currently renders ungrouped).
- [ ] Remove unused `path` import in `server.js`.
- [ ] Build an admin UI in the app — the backend already has `/api/admin/*` but nothing calls it.
