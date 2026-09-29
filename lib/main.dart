import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/config_providers.dart';
import 'services/database_service.dart';
import 'services/foreground_manager.dart';
import 'services/media_service.dart';

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

  // Foreground service untuk hantaran latar belakang.
  // B06: dilindungi — kegagalan plugin tidak boleh menggantung app.
  try {
    ForegroundManager.ensureInit();
  } catch (_) {}

  // Pulihkan sesi yang tersangkut 'running' (app ditutup semasa hantar)
  // menjadi 'cancelled' — Sejarah tidak lagi memaparkan status lama salah.
  try {
    await DatabaseService.instance.healStaleSessions();
  } catch (_) {}

  // B10: buang folder sementara ekstrak ZIP yang tertinggal.
  try {
    MediaService.cleanupZipTemp();
  } catch (_) {}

  // Muat konfigurasi & tetapan SEBELUM UI pertama (elak kelipan).
  // B06: kedua-dua muat dilindungi — jika storan selamat rosak
  // (auto-backup restore, reinstall, keystone reset), data dibuang dan
  // app terus HIDUP dengan nilai lalai (dulu: tergantung/crash di splash).
  final container = ProviderContainer();
  try {
    await container.read(configProvider.notifier).load();
  } catch (_) {}
  try {
    await container.read(settingsProvider.notifier).load();
  } catch (_) {}

  runApp(UncontrolledProviderScope(container: container, child: const DmsApp()));
}
