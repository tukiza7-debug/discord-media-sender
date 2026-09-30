## [1.0.8] — 2026-09-30

### Kemas Kini
- **NEW — No file count limit** — the 5,000-file cap is gone; folders and
  ZIPs of any size can be queued (app stays stable: lists are lazy, ZIP
  extraction stays streamed per-entry)
- **NEW — 5 GB ZIP support** — both the ZIP input limit (was 1 GB) and the
  extracted-total safety cap (was 2 GB) are raised to 5 GB; the limit
  messages are derived from the constants so they can never drift again
- **FIX — No image is silently dropped** — more image formats recognised
  (HEIC/HEIF, TIFF, JFIF/JPE, APNG, SVG, ICO); unsupported files are now
  counted and summarised ("N files ignored (unsupported type)") instead of
  vanishing; only known junk (.thumbnails/.trash*/__MACOSX, ._*, .nomedia)
  is skipped so dot-prefixed photos like ".photo.jpg" or images inside
  ".Camera" folders are picked up; ZIP entries containing ".." are accepted
  safely using the base name; one corrupt ZIP entry no longer aborts the
  whole ZIP (it is reported per entry and the rest still extract)
- **FIX — Failure records are never pruned** — the Failed list no longer
  truncates at 1,000 rows or loses old entries to housekeeping; every failed
  image stays retryable no matter how large the session
- **FIX — Oversized files are never silent** — files above the per-file
  limit stay visible with the "Too large" note, are counted in the session
  result, get a clear Failed entry, and become sendable again as soon as
  the limit is raised in Settings (no re-pick needed)
- **NEW — Session Details explains every outcome** — cancelled, partial and
  failed sessions now always show a Reason block: user cancel (with sent /
  not-sent counts), Discord rejection (HTTP + Discord code, translated),
  retries exhausted, rate-limit waits exhausted, watchdog timeout/stall,
  unexpected errors, and skipped-file summaries (missing / over the size
  limit); the failure rows now show the full error message
- **FIX — Accounting invariant** — success + failed always equals the
  session total; on cancel the unsent files are reported with a count and
  marked re-sendable, never silently forgotten

## [1.0.7] — 2026-09-30

### Kemas Kini
- **FIX — Rate-limit (429) handling** — Discord's `retry_after` is seconds, not
  milliseconds: a 1.5 s wait used to burn in 2 ms and fail the batch. The wait
  now uses the correct unit (header `Retry-After` first), is clamped to a sane
  range, can be CANCELLED mid-wait (no duplicate POST after cancel), and the
  response log shows the real countdown
- **FIX — Size limits follow Discord server tiers** — new "Max file size per
  upload" setting (10 / 20 / 50 / 100 MB, default 20 MB) replaces the old
  25 MB-image / 1 GB-video assumptions; batches are now capped by BOTH file
  count (10) AND cumulative bytes, so requests can no longer exceed the server
  limit; single files above the limit are skipped upfront instead of failing
  with HTTP 413 after 3 pointless retries
- **FIX — Smarter retries** — permanent errors (400/401/403/404/413 and
  Discord codes 40005/50013/50001/10003/10015) now fail fast and are recorded
  once; only network errors, timeouts, stalls, 5xx and 429 are retried; the
  per-attempt timeout scales with batch size (large videos get more than
  15 minutes)
- **FIX — Double-tap Send no longer corrupts the session** — a synchronous
  guard rejects the second start with NO side effects (previously it stopped
  the foreground service and reset the UI while the first upload ran)
- **FIX — Retry cleans up old failure records** — successful retries now
  remove the old Failed rows; a failure that repeats updates the existing row
  instead of adding duplicates (all in a DB transaction)
- **NEW — Queue status tracking** — sent files are marked "Sent", failed
  batches "Failed", and after Cancel the remaining files are "Cancelled" and
  still resendable; per-tile badges + a "Clear sent" action; the cancel dialog
  now describes the real behaviour
- **FIX — App can no longer hang on the splash screen** — corrupted secure
  storage (auto-backup restore / reinstall / keystore reset) is wiped and the
  app boots with defaults; backup of sensitive prefs is disabled
  (`android:allowBackup="false"`)
- **FIX — Error explanations** — Discord code 0 no longer hides the better
  HTTP explanation ("Invalid token"); fixed broken interpolation producing
  "Payload too large.title - ..."; added mappings for 10015 (Unknown
  webhook), 50027 (Invalid Webhook Token), 50035 (Invalid Form Body)
- **FIX — Release pipeline hardening** — the Release workflow now FAILS when
  the stable keystore secret is missing (no more per-VM debug signatures on
  published APKs), runs flutter analyze + flutter test before publishing,
  validates the version input against injection, and uses the correct Gradle
  wrapper cache path; dev-build artifacts are labelled when debug-signed
- **UI/UX fixes** — Pause during a batch no longer flips back to "Running"
  (honest "Pausing after current batch..."), lists no longer flash "No
  failures" while reloading, snackbars/colors now reflect the real outcome,
  the caption survives rotation and is cleared after a completed send,
  config fields validate inline and Send/Test stay disabled until valid,
  test-connection logs appear in Responses before the first upload
- **ZIP import** — extraction runs in a background isolate (no UI freeze),
  reads from disk instead of loading the whole archive, rejects
  path-traversal entries (`../evil.png`), de-duplicates same-named files
  deterministically ("IMG (1).jpg"), enforces a 2 GB extracted-size safety
  cap, reports skipped reasons, and cleans up temp folders
- **Bot/Webhook extras** — server list paginates beyond 100 guilds,
  announcement channels (type 5) are selectable, channel names are
  sanitized/validated, caption mentions are disabled by default
  (allowed_mentions), folder scans skip hidden/system dirs and explain
  limited media access, and Settings gained "Clear saved credentials",
  battery-optimization shortcut and the upload-size selector

## [1.0.6] — 2026-09-30

### Kemas Kini
- **FIX — The 3 automatic retry attempts now really happen**
  - A network-level failure (no internet, connection refused, request
    cancelled) used to crash the send engine internally after the FIRST
    attempt, so attempts 2 and 3 never ran; the engine now survives any
    API-layer exception and always completes the full 3 attempts per batch
    (with the normal backoff between them)
  - A watchdog-cancelled attempt (stall/timeout) is retried properly too
- **FIX — Failed files now really appear in the Failed screen**
  - Because the engine could die before reporting the batch failure, the
    failure records were never saved and the Failed screen stayed empty;
    now every batch that exhausts its attempts is reported and written to
    the Failed screen immediately, even while the session is still running
- **FIX — Bot mode authentication (HTTP 401)**
  - The Bot-mode requests used a masked token placeholder ("Bot ****") in
    the real Authorization header by mistake, so every Bot-mode send/test/
    channel listing failed with 401 Unauthorized; the real token is now
    used on the wire (masking stays in place for logs and screens)
- New regression tests: exactly-3-attempts retry, retry-then-success,
  exception-during-attempt retry, and network-error resilience

## [1.0.5] — 2026-09-30

### Kemas Kini
- **FIX — Stop/Cancel now really stops the send session**
  - The progress card and the "Sending..." indicator no longer stay stuck at
    0/0 with 0.0% — live progress (files, bytes, percent, speed) is streamed
    to the screen in real time while the send is running
  - Tapping Cancel now shows "Cancelling..." immediately and the session card
    disappears as soon as the engine stops — no more session that stays alive
    until the app is closed
- **FIX — History no longer shows "running" forever**
  - If any unexpected error happened mid-send (e.g. a file disappeared or
    became unreadable), the session used to stay "running" forever because
    the engine died silently; the engine is now crash-proof: any failure
    ends the session with a clear status (cancelled/failed/completed)
  - Sessions stuck at "running" from previous app closes are automatically
    marked as "Cancelled" the next time the app starts
- **NEW — Upload watchdog (anti-freeze)**
  - A stalled connection (no data moved for 90 seconds) is detected and the
    attempt is retried automatically instead of hanging forever
  - A single attempt can never take longer than 15 minutes
  - Missing/unreadable files are reported to the Failed screen before the
    send starts, instead of silently killing the session
- Smoother progress bar: byte-by-byte upload progress with live speed

## [1.0.4] — 2026-09-29

### Kemas Kini
- **Language change — the entire app UI is now in English**
  - Navigation, all screens, dialogs, snackbars, error explanations, notifications and the onboarding guide
- **FIX — updates no longer require uninstalling the old app**
  - Audit finding: every previous CI build was signed with a fresh, random debug key
    (v1.0.1, v1.0.2 and v1.0.3 each had a DIFFERENT signing certificate), so Android
    rejected every update until the old version was uninstalled
  - Releases are now signed with a fixed release key stored securely in GitHub Secrets
  - IMPORTANT (one time only): the old throwaway keys cannot be recovered, so please
    uninstall the previously installed version once, then install v1.0.4
  - From v1.0.4 onward, every future update installs directly over the previous
    version — no more uninstall, ever
- `SIGNING.txt` is now included in every release as proof of the signing
  certificate SHA-256 and the APK version — if the SHA-256 is the same across
  releases, updates install without uninstalling
- Legacy (Malay) session status values stored by older versions are normalised on load

## [1.0.3] — 2026-09-29

### Kemas Kini
- FIX: paparan landscape — ikon Tetapan tidak lagi hilang
  - Rail navigasi kiri kini boleh discrol (scroll down/up) apabila tinggi skrin tidak cukup
  - Mod padat automatik pada skrin landscape: label hanya pada tab terpilih supaya kelima-lima menu (termasuk Tetapan) terlihat tanpa perlu skrol
  - Skrin tinggi (potret/tablet) kekal berlabel penuh — tiada perubahan
- 5 ujian widget baharu meliputi rail landscape (390dp, 360dp, 320dp) & potret berlabel penuh

## [1.0.2] — 2026-09-29

### Kemas Kini
- Nota release kini menyenaraikan kemas kini secara jelas bagi setiap versi — tiada lagi pautan "Full Changelog" sahaja
- Versi release diselaraskan automatik dengan `pubspec.yaml` dan dijaga keunikannya: versi yang sudah diterbitkan tidak boleh diterbitkan semula
- APK binaan CI kini mempunyai versi dinamik (versionName ikut pubspec, versionCode ikut nombor build) supaya APK lama sentiasa boleh dikemas kini ke versi akan datang
- Fail `VERSION.txt` dimasukkan dalam setiap release sebagai rekod versionName/versionCode

## [1.0.1] — 2026-09-29

### Kemas Kini
- FIX: paparan media kini muncul serta-merta selepas folder dipilih
  - Kebenaran baca media (foto & video) diminta sebelum imbasan
  - Imbasan folder dipindahkan ke isolate latar — UI tidak lagi membeku
  - Penunjuk "Mengimbas media…" muncul segera; butang pilih dilumpuhkan sementara
- Mesej jelas untuk folder kosong / kebenaran ditolak / folder tidak dapat dibaca
- Fail tersembunyi diabaikan; subfolder tidak boleh baca dilangkau tanpa menggagalkan imbasan
- Snackbar senarai langkau dirumuskan supaya tidak memenuhi skrin
- 7 ujian unit baharu untuk imbasan folder

## [1.0.0] — 2026-09-29

### Ciri Pertama
- Dual mod penghantaran: Webhook (URL + nama bot/avatar) dan Bot (token + channel ID / pilih dari senarai server)
- Pemilihan media: fail tunggal, folder rekursif, ZIP automatik — sehingga 5,000 fail
- Hantaran berbatch (10 lampiran/mesej, had Discord) dengan jeda/sambung/batal, semula automatik 3×, patuh rate limit 429 (Retry-After)
- Sejarah sesi (SQLite), tab Gagal dengan Cuba Semula, skrin Respons dengan log penuh (HTTP, masa, kelajuan, JSON, Salin cURL — token sentiasa ditapis)
- UI Discord-style gelap, sokongan potret/landskap penuh (NavigationRail, master-detail), onboarding 3 skrin
