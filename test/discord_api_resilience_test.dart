import 'dart:io';

import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/services/discord_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresi bug v1.0.5 (diperbaiki v1.0.6):
///
/// Ralat peringkat RANGKAIAN (tiada sambungan / sambungan ditolak / batal)
/// menghasilkan DioException dengan `response == null`. Kod lama memakai
/// `e.response!.headers.map` dalam _errorEntry/_testError → melontar
/// "Null check operator used on a null value" DI DALAM blok catch →
/// pengecualian keluar terus daripada sendBatch/testWebhook →
/// loop retry enjin mati (cubaan ke-2/ke-3 tidak berlaku) dan rekod
/// Failed tidak pernah ditulis (tab Failed kekal kosong).
///
/// Ujian ini menyasarkan port tempatan yang pasti ditolak sambungannya —
/// tidak memerlukan internet sebenar.
void main() {
  // Port 9 (discard) — sambungan ditolak serta-merta, tiada respons HTTP.
  const deadWebhook = 'https://127.0.0.1:9/webhooks/123456789/abcDEF123';

  Future<File> tempFile(String name) async {
    final dir = await Directory.systemTemp.createTemp('dms_api_test');
    return File('${dir.path}/$name').writeAsBytes(List.filled(16, 2));
  }

  test('sendBatch: ralat rangkaian → kegagalan batch biasa, TIDAK melontar',
      () async {
    final f = await tempFile('a.png');
    final api = DiscordApi();
    final outcome = await api.sendBatch(
      config: const SendConfig(mode: SendMode.webhook, webhookUrl: deadWebhook),
      files: [
        MediaItem(
          id: 'x',
          path: f.path,
          name: 'a.png',
          sizeBytes: 16,
          type: MediaType.image,
          mimeType: 'image/png',
        ),
      ],
      caption: '',
      batchNumber: 1,
      totalBatches: 1,
      attempt: 1,
    );

    expect(outcome.success, isFalse);
    expect(outcome.cancelled, isFalse);
    expect(outcome.errorMessage, isNotNull,
        reason: 'ralat mesti dilaporkan supaya rekod Failed boleh ditulis');
  });

  test('testWebhook: ralat rangkaian → TestResult(ok:false), TIDAK melontar',
      () async {
    final api = DiscordApi();
    final result = await api.testWebhook(deadWebhook);
    expect(result.ok, isFalse);
    expect(result.message, isNotEmpty);
  });

  test('botAuthHeader: token sebenar pada talian; topeng hanya untuk log', () {
    // PUNCA BUG LAMA: Security.maskBotToken() dipakai dalam header HTTP —
    // header menjadi "Bot ****" → mod Bot sentiasa 401.
    expect(DiscordApi.botAuthHeader('AbCdEf.ghIj.KlMn'),
        'Bot AbCdEf.ghIj.KlMn');
    expect(DiscordApi.botAuthHeader('  token123  '), 'Bot token123');
    expect(
        DiscordApi.botAuthHeader('Bot already-prefixed'), 'Bot already-prefixed');
    expect(DiscordApi.botAuthHeader(''), '');
  });
}
