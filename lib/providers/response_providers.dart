import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/models.dart';

/// Penapis skrin Respons.
enum ResponseFilter { all, success, error, rateLimit }

extension ResponseFilterX on ResponseFilter {
  String get label {
    switch (this) {
      case ResponseFilter.all:
        return 'All';
      case ResponseFilter.success:
        return 'Success';
      case ResponseFilter.error:
        return 'Error';
      case ResponseFilter.rateLimit:
        return 'Rate Limit';
    }
  }
}

/// Log respons dalam memori (500 entri terkini; ralat kekal disimpan
/// dalam pangkalan data Sejarah/Gagal).
class ResponseLogNotifier extends StateNotifier<List<ResponseLogEntry>> {
  ResponseLogNotifier() : super(const []);

  void add(ResponseLogEntry entry) {
    final next = <ResponseLogEntry>[entry, ...state];
    if (next.length > AppLimits.responseLogCapacity) {
      next.removeRange(AppLimits.responseLogCapacity, next.length);
    }
    state = next;
  }

  void clear() => state = const [];
}

final responseLogProvider =
    StateNotifierProvider<ResponseLogNotifier, List<ResponseLogEntry>>(
        (ref) => ResponseLogNotifier());

/// Bilangan entri log (untuk banner skrin Hantar).
final responseLogCountProvider = Provider<int>((ref) => ref.watch(responseLogProvider).length);

final responseFilterProvider =
    StateProvider<ResponseFilter>((ref) => ResponseFilter.all);

final responseQueryProvider = StateProvider<String>((ref) => '');

final consoleModeProvider = StateProvider<bool>((ref) => false);

final autoScrollProvider = StateProvider<bool>((ref) => true);

final selectedResponseIdProvider = StateProvider<String?>((ref) => null);

/// Senarai yang telah ditapis (chip + carian).
final filteredResponsesProvider = Provider<List<ResponseLogEntry>>((ref) {
  final list = ref.watch(responseLogProvider);
  final filter = ref.watch(responseFilterProvider);
  final query = ref.watch(responseQueryProvider).trim().toLowerCase();

  Iterable<ResponseLogEntry> out = list;
  switch (filter) {
    case ResponseFilter.all:
      break;
    case ResponseFilter.success:
      out = out.where((e) => e.status == LogStatus.success);
      break;
    case ResponseFilter.error:
      out = out.where((e) => e.status.isError);
      break;
    case ResponseFilter.rateLimit:
      out = out.where((e) => e.status == LogStatus.rateLimited);
      break;
  }
  if (query.isNotEmpty) {
    out = out.where((e) {
      final codeMatch = e.statusCode?.toString() == query;
      final nameMatch = e.fileNames.any((n) => n.toLowerCase().contains(query));
      return codeMatch || nameMatch;
    });
  }
  return out.toList(growable: false);
});

/// Ringkasan statistik atas skrin Respons.
class ResponseSummary {
  const ResponseSummary({
    required this.total,
    required this.success,
    required this.failed,
    required this.avgLatencyMs,
    required this.rateLimitedNow,
  });

  final int total;
  final int success;
  final int failed;
  final int avgLatencyMs;
  final bool rateLimitedNow;
}

final responseSummaryProvider = Provider<ResponseSummary>((ref) {
  final list = ref.watch(responseLogProvider);
  if (list.isEmpty) {
    return const ResponseSummary(
        total: 0, success: 0, failed: 0, avgLatencyMs: 0, rateLimitedNow: false);
  }
  final success = list.where((e) => e.status == LogStatus.success).length;
  final failed = list.where((e) => e.status.isError).length;
  final withLatency = list.where((e) => e.latencyMs > 0).toList();
  final avg = withLatency.isEmpty
      ? 0
      : (withLatency.fold<int>(0, (s, e) => s + e.latencyMs) / withLatency.length).round();
  final latest = list.first;
  return ResponseSummary(
    total: list.length,
    success: success,
    failed: failed,
    avgLatencyMs: avg,
    rateLimitedNow: latest.status == LogStatus.rateLimited,
  );
});
