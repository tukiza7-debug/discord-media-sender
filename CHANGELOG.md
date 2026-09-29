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
