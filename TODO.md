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

## Housekeeping

- [ ] Rename `photos.db` / `user_folders.folder` — both hold a *library* name, not a filesystem
      folder, which is confusing next to `photos.folder` which really is one.
- [ ] Add `'Libraries'` to the Swagger `tags` array (currently renders ungrouped).
- [ ] Remove unused `path` import in `server.js`.
- [ ] Build an admin UI in the app — the backend already has `/api/admin/*` but nothing calls it.
