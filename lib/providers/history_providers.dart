import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/database_service.dart';

/// Senarai sesi sejarah (dikelompokkan mengikut tarikh di UI).
class HistoryNotifier extends StateNotifier<AsyncValue<List<SessionRecord>>> {
  HistoryNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final list = await DatabaseService.instance.sessions();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteSession(int id) async {
    await DatabaseService.instance.deleteSession(id);
    await load();
  }

  Future<void> clearAll() async {
    await DatabaseService.instance.clearSessions();
    await load();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, AsyncValue<List<SessionRecord>>>(
        (ref) => HistoryNotifier());

/// Senarai kegagalan (merentas sesi).
class FailedNotifier extends StateNotifier<AsyncValue<List<FailedRecord>>> {
  FailedNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final list = await DatabaseService.instance.failures();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteFailure(int id) async {
    await DatabaseService.instance.deleteFailure(id);
    await load();
  }

  Future<void> clearAll() async {
    await DatabaseService.instance.clearFailures();
    await load();
  }
}

final failedProvider =
    StateNotifierProvider<FailedNotifier, AsyncValue<List<FailedRecord>>>(
        (ref) => FailedNotifier());

/// Sesi terpilih untuk master-detail (landscape).
final selectedSessionIdProvider = StateProvider<int?>((ref) => null);

/// Kegagalan terpilih untuk master-detail (landscape).
final selectedFailedIdProvider = StateProvider<int?>((ref) => null);
