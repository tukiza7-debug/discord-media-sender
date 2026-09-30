import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/config_providers.dart';
import 'providers/upload_providers.dart';
import 'services/database_service.dart';
import 'services/foreground_manager.dart';
import 'services/media_service.dart';
import 'services/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mod imersif penuh (hormati notch & bar gerak).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Latar belakang sistem mengikut latar skrin (elak flash putih).
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  // Orientasi lalai: BENARKAN SEMUA (auto-rotate ikut sensor).
  // Tetapan pengguna (Auto/Potret/Landscape) digunakan selepas dimuatkan.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Foreground service untuk hantaran latar belakang (2a).
  // B06: dilindungi — kegagalan plugin tidak boleh menggantung app.
  try {
    ForegroundManager.ensureInit();
  } catch (_) {}
  // 2c: daftar port komunikasi main isolate (event task → UI).
  try {
    ForegroundManager.initCommunicationPort();
  } catch (_) {}

  final container = ProviderContainer();

  // 2d: pulihkan sesi 'running' yang MATI (servis tidak berjalan + denyar
  // basi). Sesi dgn baris pending TIDAK dibatalkan senyap — senarai
  // "Resume sending?" dipaparkan oleh UI selepas frame pertama.
  try {
    final serviceAlive = await ForegroundManager.isServiceRunning();
    final resumable =
        await DatabaseService.instance.healStaleSessions(serviceAlive: serviceAlive);
    container.read(resumableSessionsProvider.notifier).state = resumable;
  } catch (_) {}

  // 2d: buang folder sementara ZIP yang tertinggal — folder milik sesi
  // yang masih 'running' (boleh disambung semula) DILINDUNGI.
  try {
    await MediaService.cleanupZipTemp();
  } catch (_) {}

  // 1d: buang baki fail kemas kini daripada cubaan sebelumnya.
  try {
    await UpdateService.clearDownloadedFiles();
  } catch (_) {}

  // Muat konfigurasi & tetapan SEBELUM UI pertama (elak kelipan).
  // B06: kedua-dua muat dilindungi — jika storan selamat rosak
  // (auto-backup restore, reinstall, keystone reset), data dibuang dan
  // app terus HIDUP dengan nilai lalai (dulu: tergantung/crash di splash).
  try {
    await container.read(configProvider.notifier).load();
  } catch (_) {}
  try {
    await container.read(settingsProvider.notifier).load();
  } catch (_) {}

  runApp(UncontrolledProviderScope(container: container, child: const DmsApp()));
}
