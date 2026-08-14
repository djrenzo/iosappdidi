# Photo Server — Backend Specification

Reference specification for the Node backend that serves the **PhotoGalleryFrontend** iOS app.
Derived from the current `server.js` + `auth-routes.js` implementation, cross-checked against the
Swift client in [PhotoGalleryFrontend/Networking/](PhotoGalleryFrontend/Networking/).

Status legend used throughout:

| Mark | Meaning |
|---|---|
| ✅ | Implemented and matches the iOS client |
| ⚠️ | Implemented but the client contract is wrong / fragile |
| ❌ | Missing — the client needs it or security requires it |

---

## 1. Architecture

```
                 ┌──────────────────────────────────────────┐
 iOS app ───────▶│ nginx (:80)                              │
                 │  /api/*      → proxy_pass 127.0.0.1:3000 │
                 │  /thumbs/    → static  (webp, square)    │
                 │  /previews/  → static  (webp, ~2k px)    │
                 │  /originals/ → static  (source files)    │
                 └───────────────┬──────────────────────────┘
                                 │
                    ┌────────────▼─────────────┐      ┌─────────────────┐
                    │ Fastify API (127.0.0.1)  │─────▶│ SQLite index    │
                    │ better-sqlite3, sync I/O │      │ (photos, users, │
                    │ never touches image bytes│      │  albums, tags)  │
                    └──────────────────────────┘      └─────────────────┘
                                 ▲
                    ┌────────────┴─────────────┐
                    │ Indexer (separate proc)  │  scans the photo roots,
                    │ ../indexer/db → openDb() │  writes rows + derivatives
                    └──────────────────────────┘
```

**Design invariant:** the API process returns *paths only*. Image bytes are served by nginx
directly from disk. This keeps the Fastify process light enough to stay responsive on a
Raspberry Pi under load. Never add an endpoint that streams image data through Fastify.

### Runtime

| Item | Value |
|---|---|
| Framework | Fastify (`logger: { level: 'info' }`, `ignoreTrailingSlash: true`) |
| Bind address | `HOST` env, default `127.0.0.1` — nginx-only, not publicly exposed |
| Port | `PORT` env, default `3000` |
| DB driver | `better-sqlite3` via `require('../indexer/db').openDb()` — **synchronous** |
| CORS | `@fastify/cors` with `origin: true` (reflects any Origin) |
| API docs | `@fastify/swagger` + swagger-ui at **`/api/docs`**, OpenAPI 3 dynamic mode |
| Secrets | `JWT_SECRET` from `../config` |

### Serialization behaviour — read this before adding a field

Every route declares a `response` schema, so Fastify uses **fast-json-stringify**. Any property
the handler returns that is **not declared in the response schema is silently stripped**.
This is the cause of the `POST /api/albums` bug in §7.1. Schema-declared `boolean` fields also
coerce SQLite integers, which is why `shared: 1` reaches the client as `true`.

---

## 2. Data model

Inferred from the queries in `server.js` and `auth-routes.js`. Owned by the indexer, not the API.

### `photos`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | sha1 of the relative path — stable across rescans |
| `filename` | TEXT | basename |
| `db` | TEXT | **library name** (the photo root this file belongs to) |
| `folder` | TEXT | path relative to the library root, no filename. Indexed |
| `rel_path` | TEXT | `folder/filename` — used to build `originalUrl` |
| `width`, `height` | INTEGER NULL | |
| `taken_at` | TEXT NULL | ISO datetime from EXIF, mtime fallback |
| `size_bytes` | INTEGER | sortable but **never returned in the JSON payload** |
| `camera_make`, `camera_model` | TEXT NULL | detail endpoint only |
| `favorite` | INTEGER 0/1 | ⚠️ **global, not per-user** — see §7.3 |
| `thumb_ready` | INTEGER 0/1 | thumbnail generation succeeded |
| `thumb_error` | TEXT NULL | last generation error |
| `missing` | INTEGER 0/1 | file vanished from disk; every read filters `missing = 0` |

### `users`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | `randomUUID()` |
| `name` | TEXT | display name as typed |
| `name_key` | TEXT UNIQUE | `name.toLowerCase()` — the login lookup key |
| `password_hash` | TEXT | `"<salt-hex>:<hash-hex>"`, scrypt N=16384 r=8 p=1, keylen 32, 16-byte salt |
| `is_admin` | INTEGER 0/1 | first user to sign up becomes admin |
| `must_change_password` | INTEGER 0/1 | set by admin create + admin password reset |
| `avatar_data` | TEXT NULL | base64 image blob, stored inline |
| `created_at` | TEXT | ordering key for the admin user list |

### `user_folders` — the access-control table

| Column | Type | Notes |
|---|---|---|
| `user_id` | TEXT | FK → `users.id` |
| `folder` | TEXT | ⚠️ **misnamed**: holds a *library* name, joined as `p.db = uf.folder` |

Admins bypass this table entirely — `buildUser()` and `/api/libraries` return every distinct
`photos.db` for them. Non-admins see only libraries listed here. A brand-new self-signup user
has **zero rows**, so they log in to a completely empty app (§7.5).

### `albums`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | |
| `name` | TEXT | |
| `created_at` | TEXT | DB default; ordering key |
| `tag` | TEXT NULL | optional "smart album" tag — accepted and stored, never queried |
| `owner_id` | TEXT | FK → `users.id`. Filtered on read, ⚠️ **never enforced on write** |
| `shared` | INTEGER 0/1 | visible to all users when 1 |

### `album_photos`

| Column | Type | Notes |
|---|---|---|
| `album_id` | INTEGER | |
| `photo_id` | TEXT | UNIQUE(album_id, photo_id) — implied by `INSERT OR IGNORE` |
| `position` | INTEGER | ⚠️ read via `ORDER BY position ASC` but **no endpoint ever writes it** — every row takes the column default, so album order is effectively undefined |

### `tags` / `photo_tags`

`tags(id INTEGER PK, name TEXT UNIQUE)`, `photo_tags(photo_id TEXT, tag_id INTEGER)` with a
unique pair. Tags are **global**, not per-user and not per-library.

---

## 3. Authentication

JWT Bearer tokens. No cookies, no server-side session store, no refresh token, no revocation list.

```
POST /api/auth/login   ─┐
POST /api/auth/signup  ─┴─▶ { token, user }   token = HS256, exp 30d
                                              payload: { sub: user.id, name, isAdmin }

Every protected route:  Authorization: Bearer <token>
```

`requireAuth()` verifies the signature, then **re-reads the user row from the DB** and hangs it
on `request.authUser`. The `isAdmin` claim inside the token is therefore never trusted for
authorization — a demoted admin loses access immediately. Good property; keep it.

`requireAdmin()` = `requireAuth()` + `authUser.is_admin`.

Failure responses: `401 {"error":"Unauthorized"}` (missing/malformed/expired/unknown user),
`403 {"error":"Forbidden"}` (authenticated but not admin).

### ⚠️ The data plane is unauthenticated

Only `/api/auth/me*` and `/api/admin/*` carry a `preHandler`. **Everything else — photos,
folders, libraries, albums, tags, favorites — is reachable with no token at all.** Combined with
`cors({ origin: true })` and client-supplied `user_id` query parameters, any device on the LAN
(or any web page a LAN user visits) can enumerate and mutate the entire library. See §7.6.

---

## 4. Static asset contract (nginx)

The API returns these paths; nginx must serve them. **The iOS client fetches them with a bare
`URLSession` and sends no `Authorization` header** ([AsyncPhotoImage.swift](PhotoGalleryFrontend/Views/Shared/AsyncPhotoImage.swift)),
so these locations must remain publicly readable — or the client must be changed first.

| Field | Pattern | Used by the app for |
|---|---|---|
| `thumbUrl` | `/thumbs/{photo.id}.webp` | grid cells |
| `previewUrl` | `/previews/{photo.id}.webp` | full-screen viewer |
| `originalUrl` | `/originals/{db}/{rel_path}` | ❌ never loaded — too large |

`originalUrl` builds as `encodeURIComponent(rel_path).replace(/%2F/g, '/')`. Note `db` is
interpolated **unencoded**, so library names must stay URL-safe.

---

## 5. Endpoint reference

Base path `/api`. All error bodies are `{ "error": string }` — matching the client's
`ServerErrorMessage` decoder. Fastify schema-validation failures return its default
`{statusCode, error, message}` shape instead, which the client renders as a generic message.

### 5.1 Health

| | |
|---|---|
| `GET /api/health` | → `{ ok: true }` ✅ Unauthenticated by design. Not used by the app. |

### 5.2 Auth

#### `POST /api/auth/login` ✅
```jsonc
// body
{ "name": "didier", "password": "…" }
// 200
{ "token": "<jwt>", "user": User }
// 401
{ "error": "Incorrect name or password" }
```
Lookup is by `name_key` (`name.trim().toLowerCase()`), so login is case-insensitive.

#### `POST /api/auth/signup` ✅
```jsonc
{ "name": "didier", "password": "at-least-8-chars" }
// 200
{ "token": "<jwt>", "user": User, "role": "admin" | "user" }
```
Rules: name must match `/^[a-zA-Z0-9._-]{2,40}$/`, password ≥ 8 chars, `name_key` unique.
**The first account ever created becomes admin.** All later signups are plain users with no
library grants. Signup is open to anyone who can reach the server — there is no invite code.

400 messages: `"Names use 2-40 letters, numbers, dots, dashes or underscores"`,
`"Password must be at least 8 characters"`, `"That name is already taken"`.

#### `GET /api/auth/me` 🔒 ✅
→ `{ user: User }`. The Swift `User` decoder unwraps the `user` envelope automatically.

#### `PATCH /api/auth/me` 🔒 ✅
```jsonc
{ "name": "newname", "avatarData": "<base64>" | null }   // both optional
// 200
{ "ok": true, "user": User }
```
Both fields are independently optional. `avatarData: null` clears the avatar.

#### `PATCH /api/auth/me/password` 🔒 ✅
```jsonc
{ "currentPassword": "…", "newPassword": "…" }   // currentPassword optional
// 200 → { ok: true }
```
`currentPassword` is **required unless `must_change_password = 1`**, which lets a user
finish a forced reset without knowing the temporary password. A successful change clears
`must_change_password`.

#### The `User` object
```jsonc
{
  "id": "uuid",
  "name": "Didier",
  "nameKey": "didier",
  "isAdmin": false,
  "mustChangePassword": false,
  "avatarData": null,
  "allowedFolders": ["family", "trips"]   // ⚠️ library names, and the client reads "folders"
}
```
None of these routes declare a `response` schema, so `User` is **not** stripped by
fast-json-stringify — it reaches the client whole.

### 5.3 Libraries & folders

#### `GET /api/libraries?user_id=<id>` ⚠️
→ `["family", "trips"]`

Admin (looked up from the **query-param** `user_id`, not the token) gets every distinct
`photos.db`; everyone else gets libraries joined through `user_folders`. **Authorization is
derived from a client-supplied id** — passing another user's id returns their libraries, and
passing an admin's id returns everything. No token required.

#### `GET /api/folders?library=<db>` ✅ (⚠️ no ACL)
→ `["", "2023/summer", "2024/trip"]`

Distinct `folder` values with `missing = 0` in that library, alphabetical. Accepts any library
name from any caller — the `user_folders` grant is not consulted.

#### `GET /api/admin/libraries` 🔒👑 ✅
→ every distinct `photos.db`. Same data as `/api/libraries` for an admin. Unused by the app.

### 5.4 Photos

Favorites moved off a shared column on `photos` onto a per-user `user_favorites` join table
(photo_id, user_id). Every read endpoint below takes an *optional* `user_id` to resolve each
photo's `favorite` flag for that specific user — omit it and every photo comes back with
`favorite: false`, since there's no longer a single global value to fall back to.

#### `GET /api/photos` ⚠️
| Query | Type | Default | Notes |
|---|---|---|---|
| `library` | string | — | **required** |
| `folder` | string | — | exact match, not a prefix. Omit for all folders |
| `limit` | int 1–1000 | 100 | app uses 60 |
| `offset` | int ≥ 0 | 0 | |
| `sort` | `taken_at`\|`filename`\|`size_bytes` | `taken_at` | whitelist-checked twice |
| `order` | `asc`\|`desc` | `desc` | |
| `tag` | string | — | exact tag name; switches to a 3-way join |
| `user_id` | string | — | optional; resolves `favorite` per-user (see above) |

→ `{ total, items: Photo[] }` where `total` is the count **for the same filter**, not the page.

`additionalProperties: false` — an unknown query key is a 400. The app relies on `total` for its
"N Photos" header and for `hasMore` paging. The old `favorite=true` filter param is gone —
favoriting is handled by the dedicated endpoint below instead.

#### `GET /api/favorites?user_id=<id>` ✅
→ `Photo[]` — every photo the given user has favorited, ordered newest-taken first. **Not
library-scoped** (spans every library the user can see) and **not paginated** — always returns
the complete list in one response, unlike `GET /api/photos`. `user_id` is required.

#### `GET /api/photos/:id` ✅
| Query | Type | Notes |
|---|---|---|
| `user_id` | string | optional; resolves `favorite` per-user |

→ `Photo` + `{ cameraMake, cameraModel, tags: string[] }`, or `404 {"error":"not found"}`.
Not scoped by library or user for *access* — any photo id is readable by anyone regardless of
`user_id`; that param only affects the returned `favorite` value.

#### `PATCH /api/photos/:id/favorite` ✅
```jsonc
{ "favorite": true, "user_id": "uuid" }   // → { ok: true } | 404
```
`user_id` is now **required**. Inserts/deletes the `(photo_id, user_id)` row in `user_favorites`
rather than writing a column on `photos` — favoriting is per-user.

#### The `Photo` object
```jsonc
{
  "id": "9f3a…", "filename": "IMG_0042.jpg",
  "db": "family", "folder": "2024/trip",
  "width": 4032, "height": 3024,
  "takenAt": "2024-07-14T10:22:31.000Z",
  "favorite": false, "thumbReady": true, "thumbError": null,
  "thumbUrl": "/thumbs/9f3a….webp",
  "previewUrl": "/previews/9f3a….webp",
  "originalUrl": "/originals/family/2024/trip/IMG_0042.jpg"
}
```
`favorite` reflects the requesting `user_id`'s own favorites now, not a shared value — see the
note at the top of this section. `size_bytes` is sortable but absent from the payload. `takenAt`
is parsed client-side with `ISO8601DateFormatter` — fractional seconds or a missing `Z` will fail
to parse (silently, to `nil`).

### 5.5 Albums

#### `GET /api/albums?user_id=<id>` ⚠️
→ `Album[]`, ordered `created_at DESC`. Returns albums where `owner_id = user_id` **OR**
`shared = 1`. `user_id` is required → `400 {"error":"user_id required"}` if omitted.

> The client re-sorts by `createdAt` descending anyway. Every call site — including
> `AddToAlbumSheet` — must pass `session.currentUser?.id` or the list comes back filtered to
> shared albums only.

#### `POST /api/albums` ✅
```jsonc
// body
{ "name": "Summer", "tag": "beach", "user_id": "uuid", "shared": 0 }
// 200 — as actually serialized
{ "id": 16, "name": "test", "created_at": "2026-08-14 08:03:39", "tag": null,
  "owner_id": "e8442e19-2048-4bc0-9db0-4ec27b52df11", "shared": false }
```
Fixed (was previously broken — see §7.1 history): the handler now re-selects and returns the
inserted row, with the response schema declaring `created_at`/`owner_id` to match, so it's the
same shape as each item in `GET /api/albums`. Matches `Album.swift`'s `CodingKeys` exactly.

`shared` must be the integer `0` or `1` (a JSON boolean is rejected by the enum).

#### `PATCH /api/albums/:id` ✅
```jsonc
{ "shared": 1 }   // → { id, shared: true } | 404
```
Only `shared` is updatable — there is no rename endpoint. ⚠️ No ownership check.

#### `DELETE /api/albums/:id` ⚠️
→ `{ ok: true }` | `404`. ⚠️ No ownership check — any caller can delete any album.
Cascade-deletes `album_photos` rows only if the FK is declared `ON DELETE CASCADE` in the
indexer schema; otherwise the membership rows are orphaned.

#### `GET /api/albums/:id/photos` ⚠️
Accepts an optional `user_id` (see §5.4) to resolve each photo's `favorite` per-user.
→ `Photo[]`, `missing = 0`, `ORDER BY album_photos.position ASC` — which is a no-op today
because nothing writes `position`. No share/ownership check.

#### `POST /api/albums/:id/photos` ⚠️
```jsonc
{ "photoIds": ["9f3a…", "b71c…"] }   // → { ok: true }
```
`INSERT OR IGNORE` inside a transaction, so it is idempotent. **Always returns `ok: true`** —
unknown album ids and unknown photo ids are indistinguishable from success, and there is no
per-id result. No ownership check.

#### `DELETE /api/albums/:id/photos` ✅
```jsonc
{ "photoIds": ["9f3a…", "b71c…"] }   // → { ok: true }
```
Added after this doc's first pass (§8 originally listed it as missing) to back
`AlbumDetailView`'s "Select Photos" / "Remove N from Album" flow
(`PhotoServerAPI.removePhotos(albumId:photoIds:)`). Exact semantics (idempotency, per-id result,
ownership scoping) weren't re-verified against the implementation — worth confirming it matches
`POST /api/albums/:id/photos`'s behavior above, particularly whether it's restricted to the
album's owner per §7.6.

#### The `Album` object
```jsonc
{ "id": 12, "name": "Summer", "created_at": "2024-07-14 10:22:31",
  "tag": null, "owner_id": "uuid", "shared": false }
```
snake_case here (unlike `Photo`), which the Swift model maps explicitly.

### 5.6 Tags

| | |
|---|---|
| `POST /api/photos/:id/tags` | body `{ tag }` → `{ ok: true }`. Upserts into `tags`, links via `photo_tags`. ⚠️ Returns `ok` even for a nonexistent photo id |
| `DELETE /api/photos/:id/tags/:tag` | → `{ ok: true }`, `404 {"error":"tag not found"}` if the tag doesn't exist, `404 {"error":"not found"}` if the photo isn't tagged with it |

⚠️ A tag containing `/` cannot be deleted — it breaks the route path. Tag names are otherwise
unvalidated: no trimming (the client trims), no length cap, no case folding, and orphaned
`tags` rows are never garbage-collected.

❌ There is no `GET /api/tags` — the app cannot offer tag autocomplete or browse-by-tag, even
though `GET /api/photos?tag=` supports filtering.

### 5.7 Admin 🔒👑

All require an admin token. **None of these are used by the iOS app** — there is no admin UI.

| Endpoint | Body | Notes |
|---|---|---|
| `GET /api/admin/users` | — | → `{ users: User[] }`, `created_at ASC` |
| `POST /api/admin/users` | `{ name, password, isAdmin?, folders?, mustChangePassword? }` | `mustChangePassword` defaults to **true**. `folders` (library names) are only inserted for non-admins. ⚠️ no `minLength` on `password` here, unlike signup |
| `PATCH /api/admin/users/:id` | `{ isAdmin?, folders?, mustChangePassword? }` | ⚠️ **no body schema** — unvalidated. `folders` is a full replace (DELETE-then-INSERT). Refuses to remove your own admin role |
| `POST /api/admin/users/:id/password` | `{ password }` (min 8) | Forces `must_change_password = 1` |
| `DELETE /api/admin/users/:id` | — | Refuses self-deletion. ⚠️ Orphans that user's albums and `user_folders` rows unless the FKs cascade |

---

## 6. Client → endpoint map

| iOS surface | Calls |
|---|---|
| `ServerSetupView` | — (stores base URL in `UserDefaults`) |
| `LoginView` / `SignupView` | `POST /api/auth/login`, `/signup` |
| `SessionStore.bootstrap` | `GET /api/auth/me` (401/403 ⇒ logout; network error ⇒ keep cache) |
| `MainTabView` → `LibraryViewModel` | `GET /api/libraries`, `GET /api/folders` |
| `GalleryView` | `GET /api/photos` (paged, 60/page, `user_id` for favorite resolution), `PATCH …/favorite` |
| `FavoritesView` | `GET /api/favorites?user_id=` (flat, not paginated, not library-scoped) |
| `PhotoDetailPagerView` | `GET /api/photos/:id?user_id=`, `PATCH …/favorite` (body now requires `user_id`) |
| `TagEditorSheet` | `POST /api/photos/:id/tags`, `DELETE /api/photos/:id/tags/:tag` |
| `AlbumListView` / `AddToAlbumSheet` | `GET /api/albums?user_id=`, `POST /api/albums`, `POST /api/albums/:id/photos` |
| `AlbumDetailView` | `GET /api/albums/:id/photos`, `PATCH /api/albums/:id`, `DELETE /api/albums/:id` |
| `EditProfileSheet` / `ChangePasswordSheet` | `PATCH /api/auth/me`, `PATCH /api/auth/me/password` |
| `AsyncPhotoImage` | nginx `/thumbs/`, `/previews/` — **no auth header** |

---

## 7. Known contract gaps

Ordered by impact. §7.1–7.2 are user-visible bugs; §7.3–7.6 are design/security.

### 7.1 ✅ `POST /api/albums` omitted `created_at` — album creation always reported failure
**Fixed.** The response schema previously declared only `id`, `name`, `tag`, `shared`; Swift's
`Album` requires `created_at`, so `JSONDecoder` threw → `APIError.decoding` → the new album
never appeared in the list until the view was reloaded, and the user saw an error for an
operation that had actually succeeded.

**Fix applied (backend):** return the inserted row and declare it fully — same shape as each
item in `GET /api/albums`.
```js
const result = db.prepare('INSERT INTO albums (name, tag, owner_id, shared) VALUES (?,?,?,?)')
                 .run(name, tag ?? null, user_id, sharedValue);
return db.prepare('SELECT * FROM albums WHERE id = ?').get(result.lastInsertRowid);
```
…with `created_at` and `owner_id` added to the response schema. **Fix (frontend alternative):**
make `Album.createdAt` optional. Do one or the other, not neither.

### 7.2 ✅ `allowedFolders` vs `folders`
**Fixed (frontend).** The backend emits `allowedFolders`;
[User.swift](PhotoGalleryFrontend/Models/User.swift#L13) previously decoded a `folders` key that
never existed in the response, so `User.folders` was always `nil`. `CodingKeys` now maps
`folders = "allowedFolders"`. `nameKey` is still sent and ignored — harmless, nothing reads it.

### 7.3 ✅ Favorites are now per-user (tags are still global)
**Fixed, favorites half only.** `photos.favorite` is gone; favoriting is now a
`user_favorites(user_id, photo_id)` join table, with `favorite` resolved per the requesting
`user_id` on every read (§5.4). The client is fully updated to match. **`photo_tags` is
unchanged** — tags are still global across all users, the other half of this gap.

### 7.4 ✅ `favorite` presence-based filtering — resolved by removal
The old `?favorite=true` query param on `GET /api/photos` (`if (favorite !== undefined) ...` —
`?favorite=false` incorrectly returned favorites) is gone entirely, superseded by the dedicated
`GET /api/favorites` endpoint in §5.4. Nothing to fix — the buggy param no longer exists.

### 7.5 New self-signup users land in a dead end
A non-first signup gets no `user_folders` rows, so `/api/libraries` returns `[]`, no library is
selected, and the gallery is permanently empty with no in-app way to request access — and no
admin UI to grant it. Either close signup behind an invite/admin-create flow, or add a default
grant, or build the admin screen (§8).

### 7.6 The data plane has no authentication or authorization
Concretely, with **no token**:
- `GET /api/photos?library=family` — read anyone's library
- `GET /api/libraries?user_id=<any-admin-uuid>` — enumerate every library
- `DELETE /api/albums/7` — delete another user's album
- `PATCH /api/photos/<id>/favorite` — mutate shared state

And `/thumbs/`, `/previews/`, `/originals/` are unauthenticated at the nginx layer by design,
so image bytes are readable by anything on the LAN that can guess or list an id.

**Recommended remediation**, in dependency order:
1. Register `preHandler: auth` on the whole `apiRoutes` plugin, exempting
   `/api/health`, `/api/auth/login`, `/api/auth/signup`, `/api/docs`.
2. Delete every `user_id` **query/body parameter** and read the identity from
   `request.authUser.id` instead — `/api/libraries`, `/api/albums`, `POST /api/albums`.
3. Add a `canAccessLibrary(user, db)` helper (admin ⇒ true, else a `user_folders` lookup) and
   apply it in `/api/folders`, `/api/photos`, `/api/photos/:id`.
4. Enforce `owner_id` on album write paths (`PATCH`, `DELETE`, `POST /:id/photos`) and read
   paths (`GET /:id/photos` — owner or `shared = 1`).
5. Decide on image-byte auth: either signed/expiring URLs, or an nginx `auth_request` against a
   token-validating endpoint — which requires teaching `AsyncPhotoImage` to send the header.
6. Tighten CORS from `origin: true` to the actual origins in use.

Steps 1–2 are breaking changes for the client and should ship together with an app update.

### 7.7 Smaller items
- **`album_photos.position` is never written** — album ordering is undefined despite the
  `ORDER BY`. Set `position` to `(SELECT COALESCE(MAX(position), 0) + 1 …)` on insert, or drop
  the pretence and order by `photo_id`/`taken_at`.
- **`POST /api/photos/:id/tags` and `POST /api/albums/:id/photos` return `ok: true` for
  nonexistent ids** — validate the parent row and 404.
- **`PATCH /api/admin/users/:id` has no body schema** — arbitrary input reaches the handler.
- **`verifyPassword` can throw on a malformed stored hash** (`timingSafeEqual` requires equal
  lengths) producing a 500 rather than a 401. Guard on `derived.length`.
- **`'Libraries'` tag isn't declared** in the Swagger `tags` array, so it renders ungrouped.
- **`path` is imported but unused** in `server.js`.
- **Tags with `/` are undeletable**; move the tag to the request body or query for `DELETE`.
- **No `size_bytes` in the payload** even though it is an allowed sort key — the app can offer
  "sort by file size" but can never display it.

---

## 8. Endpoints the frontend would use but that don't exist

| Missing | Unblocks |
|---|---|
| `GET /api/tags` (optionally `?library=`) | tag autocomplete in `TagEditorSheet`, browse-by-tag |
| `PATCH /api/albums/:id` accepting `name` | album rename |
| `PUT /api/albums/:id/order` | using the `position` column |
| `limit` param on `GET /api/albums/:id/photos` (or a cover/count field on `GET /api/albums`) | `AlbumCard` now builds its 4-thumbnail collage cover client-side by fetching each album's *entire* photo list just to keep the first 4 — fine for small albums, wasteful for large ones |
| `GET /api/photos?q=` full-text search over filename/folder/tags | a search UI |
| `GET /api/stats` (counts, date range, per-library totals) | a library overview screen |
| per-user favorites (§7.3) | a correct Favorites tab |
| `POST /api/auth/logout` / token revocation | real sign-out; today logout is client-side only and the JWT stays valid for its full 30 days |

---

## 9. Operational notes

- **`better-sqlite3` is synchronous** — every query blocks the event loop. Fine for an indexed
  SQLite read on a Pi; do not add unbounded scans or large `IN` lists to a hot path.
- **The `db` column is a library name, and `user_folders.folder` also holds a library name.**
  Neither is a filesystem folder. `photos.folder` *is* one. Rename these before the confusion
  causes a real bug.
- **Bind stays on `127.0.0.1`.** Exposing Fastify directly would bypass nginx and, given §7.6,
  publish the whole library.
- **The iOS app ships `NSAllowsArbitraryLoads: true`** and defaults to `http://127.0.0.1:3000`,
  so tokens travel in cleartext over the LAN. TLS on nginx is the fix.
- **Swagger UI at `/api/docs`** is unauthenticated and enumerates the entire API surface.
