# Discord Media Sender

[![Build APK](https://github.com/tukiza7-debug/discord-media-sender/actions/workflows/build-apk.yml/badge.svg)](https://github.com/tukiza7-debug/discord-media-sender/actions/workflows/build-apk.yml)
[![Release](https://github.com/tukiza7-debug/discord-media-sender/actions/workflows/release.yml/badge.svg)](https://github.com/tukiza7-debug/discord-media-sender/actions/workflows/release.yml)
![Platform](https://img.shields.io/badge/platform-Android-green)
![Flutter](https://img.shields.io/badge/Flutter-3.47%20stable-5865F2)

Aplikasi Android untuk **menghantar media pukal ke Discord** melalui **Webhook** atau **Bot** — dibina dengan Flutter (Dart 3), Material 3, Riverpod, dan reka bentuk yang kemas (mod gelap lalai, aksen blurple).

## Muat Turun Release Terkini

Pergi ke halaman [**Releases**](https://github.com/tukiza7-debug/discord-media-sender/releases/latest) dan muat turun APK mengikut peranti anda:

| Fail | Peranti |
|------|---------|
| `DiscordMediaSender-vX.Y.Z-universal.apk` | Semua peranti (saiz lebih besar) |
| `DiscordMediaSender-vX.Y.Z-arm64-v8a.apk` | Kebanyakan telefon moden (disyorkan) |
| `DiscordMediaSender-vX.Y.Z-armeabi-v7a.apk` | Telefon lama |
| `DiscordMediaSender-vX.Y.Z-x86_64.apk` | Emulator / tablet Intel |

Fail `SHA256SUMS.txt` mengandungi checksum untuk pengesahan integriti.

## Ciri-ciri

- **Dua mod hantaran** — Webhook (URL + nama bot + avatar) atau Bot (token + channel ID, pemilih channel dari senarai server, cipta channel baru). Uji Sambungan untuk kedua-dua mod. Konfigurasi disimpan dalam **flutter_secure_storage**.
- **Pilih media** — gambar/video (PNG, JPG, GIF, WebP, BMP, AVIF; MP4, WebM, MOV, MKV, AVI, MPEG, OGG, 3GP), **folder penuh** (imbas semua subfolder), dan **ZIP** (diekstrak automatik). Had saiz per fail boleh ditetapkan dalam Tetapan (10 / 20 / 50 / 100 MB, lalai 20 MB mengikut tier server Discord); fail melebihi had dilangkau dengan sebab jelas.
- **Bulk send** — kelompok 10 fail/mesej (had Discord), kapsyen maks 2,000 aksara pada batch pertama, pratonton mesej ala Discord.
- **Progres masa nyata** — bar animasi, kiraan berjaya/gagal, kelajuan, batch semasa, **Jeda/Sambung/Batal**.
- **Auto-retry 3 kali** dengan backoff eksponensial + hormat rate limit Discord (HTTP 429, `Retry-After`).
- **Foreground service + enjin dalam servis** — notifikasi progres dengan **butang Stop**; enjin hantaran berjalan DI DALAM task isolate servis — swipe dari recents, backgrounding, skrin padam, dan rotasi TIDAK menghentikan sesi; servis direstasi automatik oleh sistem selepas proses mati dan baris pending diteruskan (fail yang sudah dihantar tidak dihantar semula).
- **Kemas kini automatik dari GitHub** — semakan sekurang-kurangnya sekali setiap 6 jam (tidak pernah semasa sesi hantaran), dialog nota keluaran, muat turun ikut ABI peranti (fallback universal), **pengesahan SHA-256 + saiz (fail-closed)** terhadap `SHA256SUMS.txt` sebelum pemasang sistem dibuka; semakan manual di Tetapan → Tentang.
- **Skrin Respons** — log masa nyata setiap permintaan: lencana status HTTP berwarna, masa respons (ms), saiz & kelajuan muat naik, bilangan cubaan, header rate limit, JSON berwarna boleh lipat, penerangan ralat dalam Bahasa Inggeris + cadangan penyelesaian, **Salin JSON / Salin cURL** (sentiasa ditapis), kad khas 429 dengan kira detik, penapis chip + carian, mod konsol (monospace), auto-scroll, eksport log .txt/.json.
- **Sejarah & Gagal** — sesi direkod dalam SQLite (dikumpul ikut tarikh), kegagalan selepas 3 cubaan dipaparkan dengan kod HTTP & mesej, **Cuba Semula** (satu fail / satu sesi / semua), swipe untuk padam, tarik-untuk-muat-semula.
- **Adaptif penuh** — navigasi bawah (potret) / NavigationRail (landscape), dua lajur di skrin Hantar, master-detail di skrin Respons/Sejarah/Gagal, tetapan orientasi Auto/Potret/Landscape. Semua state dalam Riverpod — tiada data hilang semasa rotasi.
- **Onboarding 3 skrin** kali pertama (cara dapat webhook, bot token, pilih folder), ikon & splash tersuai.

## Keselamatan

- Token bot & URL webhook **TIDAK PERNAH** dipapar, disalin, dieksport, atau di-log — semua output melalui lapisan penapisan (`Security`) yang menghasilkan bentuk `.../webhooks/1234****/xxxx****`.
- Kelayakan disimpan dalam **Android EncryptedSharedPreferences** (flutter_secure_storage).
- Tiada kebenaran storan dibenarkan — pemilihan media menggunakan SAF. Tiada telemetri; data hanya dihantar ke Discord.
- Kunci tandatangan tidak pernah berada dalam repo (lihat `.gitignore`).

## Cara Push ke GitHub & Bina

Repositori ini sudah lengkap dengan dua workflow GitHub Actions:

1. **Build APK** (`.github/workflows/build-apk.yml`) — berjalan pada setiap push ke `main`, pull request, atau cetusan manual. Langkah: pub get → `flutter analyze` → `flutter test` → bina 4 APK (universal + 3 ABI) → muat naik sebagai artifact.

2. **Release** (`.github/workflows/release.yml`) — berjalan apabila tag `v*` di-push atau cetusan manual dengan input `version`. Menghasilkan APK bertandatangan + `SHA256SUMS.txt` + `VERSION.txt` + GitHub Release yang **notanya diambil daripada `CHANGELOG.md`** (tiada pautan "Full Changelog" — setiap versi menyatakan kemas kininya dengan jelas).

### Push pertama (contoh)

```bash
git clone https://github.com/tukiza7-debug/discord-media-sender.git
cd discord-media-sender
git add .
git commit -m "Ciri pertama saya"
git push origin main
```

### Cipta release baru

1. Naikkan versi dalam `pubspec.yaml` (contoh: `version: 1.0.3+1`).
2. Tambah seksyen baharu dalam `CHANGELOG.md` yang menerangkan kemas kini versi tersebut:

   ```markdown
   ## [1.0.3] — 2026-10-01

   ### Kemas Kini
   - <nyatakan kemas kini di sini>
   ```

3. Commit, kemudian tag dan push:

   ```bash
   git add .
   git commit -m "Naik taraf 1.0.3"
   git tag v1.0.3
   git push origin main --follow-tags
   ```

   Atau secara berasingan: `git tag v1.0.3 && git push origin v1.0.3`.

Tunggu workflow Release siap (5-10 minit), kemudian muat turun APK dari tab **Releases**.

> **Penting**: setiap release mesti guna versi baharu — workflow akan GAGAL sekiranya tag versi itu sudah pernah diterbitkan. Jika seksyen `CHANGELOG.md` tiada untuk versi tersebut, nota release automatik dijana daripada senarai commit sejak tag sebelumnya.

Anda juga boleh cetus release manual: tab **Actions → Release → Run workflow**, masukkan versi (contoh `1.2.0`).

## Hantar di Latar Belakang (Background sending)

Sesi hantaran berjalan dalam foreground service (jenis `dataSync`) dan hanya BERAKHIR apabila:

- pengguna menekan **Stop** dalam app atau **dalam notifikasi**, atau
- sesi tamat dengan sendirinya, atau
- dasar kegagalan enjin sendiri berlaku (ralat tidak boleh di-retry / cubaan habis).

Tutup app, swipe dari recents, backgrounding, skrin padam, dan rotasi **tidak menghentikan** sesi. Setiap fail sesi disimpan dalam pangkalan data (`session_files`) — jika proses terbunuh, servis direstasi dan baris **pending sahaja** diteruskan; fail yang sudah dihantar tidak pernah dihantar semula (satu batch dalam penerbangan mungkin terhantar dua kali — direkodkan dalam sebab sesi). Sesi yang mati tidak dibatalkan senyap: app akan bertanya **"Resume sending?"** (Sambung / Buang).

**Perkara yang tiada app boleh elak** (semuanya berakhir dengan prompt "Resume sending?", bukan kehilangan senyap):

- **Force Stop** dari System Settings — servis dan proses dibunuh; sesi diteruskan selepas app dibuka semula.
- **Pembunuh bateri vendor** yang agresif (sone OEM mematikan app tanpa amaran) — benarkan pengecualian pengoptimuman bateri (app akan bertanya sekali; boleh diubah di Tetapan → Battery optimization).
- **Reboot** — sesi kekal 'running' dan ditawarkan sambung semula pada app dibuka.

Had Android 15+ untuk servis `dataSync` (~6 jam/24 jam) dinyatakan dalam Risiko pada laporan pembangunan.

## Kemas Kini Dalam App

App menyemak keluaran terkini GitHub (tiada token, tiada telemetri). Jika versi lebih baharu wujud dan sesi hantaran tidak aktif, dialog memaparkan nota keluaran dengan butang **Update now / Later / Skip this version**. "Update now" akan:

1. Memilih APK mengikut ABI peranti (`arm64-v8a` → `armeabi-v7a` → `x86_64`, fallback `universal`).
2. Memuat turun ke cache app (dengan kemajuan & butang Batal).
3. **Mengesahkan integriti secara fail-closed**: saiz mesti sepadan dengan metadata aset DAN SHA-256 mesti sepadan dengan baris dalam `SHA256SUMS.txt` keluaran yang sama. Sekiranya fail checksum tiada, entri tiada, atau nilai tidak sepadan — fail dibuang dan pemasangan **TIDAK** diteruskan.
4. Meminta kebenaran "install unknown apps" dan membuka pemasang sistem.

Muat turun hanya dibenarkan dari `https://github.com` atau host release-asset rasmi GitHub. Semakan manual (mengabaikan throttle 6 jam & versi dilangkau) ada di **Tetapan → Tentang → Check for updates**.

## Kemas Kini APK ke Versi Baharu

APK yang sudah terpasang boleh terus dikemas kini:

- `applicationId` (`com.dmsender.discord_media_sender`) tidak berubah antara versi, dan `versionCode` meningkat secara automatik pada setiap build (mengikut nombor run GitHub Actions) — Android akan menerima APK baharu sebagai kemas kini.
- Pasang APK versi baharu terus di atas yang lama (data & tetapan kekal).
- **Ambil perhatian**: APK **Release** WAJIB ditandatangani dengan kunci stabil (`KEYSTORE_BASE64` dst. dalam repo secrets) — workflow Release akan GAGAL dengan ralat jelas sekiranya keystore tiada (debug key pada runner dijana baharu setiap VM dan menyebabkan "App not installed / signature conflict"). Build dev/PR (`Build APK`) mungkin debug-signed dan dilabel sedemikian dalam `BUILD_INFO.txt`; jangan edarkannya.

## Tandatangan APK (WAJIB untuk Release)

APK release hanya dibina sekiranya keystore stabil disediakan dalam repo secrets (debug fallback dinyahaktifkan untuk workflow Release). Cara menyediakannya:

### 1. Jana keystore

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### 2. Tukar ke base64

Linux/macOS:
```bash
base64 -w0 upload-keystore.jks > keystore_base64.txt
```
Windows (PowerShell):
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Out-File keystore_base64.txt
```

### 3. Tambah GitHub Secrets

Pergi ke **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Nilai |
|--------|-------|
| `KEYSTORE_BASE64` | Kandungan penuh `keystore_base64.txt` |
| `KEY_ALIAS` | `upload` |
| `KEY_PASSWORD` | Kata laluan kunci |
| `STORE_PASSWORD` | Kata laluan keystore |

Workflow akan decode keystore ke `android/app/upload-keystore.jks` dan menjana `android/key.properties` secara automatik semasa build. **Jangan commit fail-fail ini.**

## Struktur Projek

```
lib/
├── main.dart                  # Titik masuk + init foreground service
├── app.dart                   # Tema + gerbang onboarding
├── root_shell.dart            # Navigasi adaptif (bar/rail)
├── core/
│   ├── app_theme.dart         # Token reka bentuk (warna, ruang, radius)
│   ├── constants.dart         # Had & katalog media
│   ├── security.dart          # Penapisan token/webhook + cURL
│   ├── validators.dart        # Validasi input (BM)
│   ├── error_translator.dart  # Ralat HTTP/Discord -> BM
│   ├── formatters.dart        # Saiz, masa, kelajuan
│   └── secure_store.dart      # flutter_secure_storage
├── models/models.dart         # Semua model data
├── services/
│   ├── discord_api.dart       # Klien API Discord (webhook/bot)
│   ├── media_service.dart     # Pilih/imbas/ekstrak media
│   ├── upload_engine.dart     # Enjin bulk (batch, retry, jeda/batal)
│   ├── database_service.dart  # SQLite sejarah & gagal
│   └── foreground_manager.dart# Notifikasi latar belakang
├── providers/                 # Riverpod state (5 fail)
├── screens/                   # Hantar, Respons, Sejarah, Gagal, Tetapan, Onboarding
└── widgets/                   # Kad, badge, empty state, JSON viewer
```

## Teknologi

Flutter stable (Dart 3) • Material 3 • Riverpod • dio • sqflite • flutter_secure_storage • archive • file_picker 13 (SAF — tanpa kebenaran storan) • flutter_video_thumbnail_plus • flutter_foreground_task • google_fonts (Inter + JetBrains Mono) • lucide_icons_flutter

## Lesen

MIT
