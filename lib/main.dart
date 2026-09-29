import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/config_providers.dart';
import 'services/foreground_manager.dart';

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
  ForegroundManager.ensureInit();

  // Muat konfigurasi & tetapan SEBELUM UI pertama (elak kelipan).
  final container = ProviderContainer();
  await container.read(configProvider.notifier).load();
  await container.read(settingsProvider.notifier).load();

  runApp(UncontrolledProviderScope(container: container, child: const DmsApp()));
}
