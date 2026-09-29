# Changelog — Discord Media Sender

Semua kemas kini ketara setiap versi didokumenkan di sini.
Format: `## [versi] — tarikh`. Nota release di GitHub dibina daripada fail ini.

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
