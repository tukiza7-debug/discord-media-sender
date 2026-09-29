import 'package:discord_media_sender/core/error_translator.dart';
import 'package:discord_media_sender/core/formatters.dart';
import 'package:discord_media_sender/core/security.dart';
import 'package:discord_media_sender/core/validators.dart';
import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/services/upload_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Security — penapisan rahsia', () {
    test('maskWebhookUrl mengikut format spesifikasi', () {
      const url =
          'https://discord.com/api/webhooks/123456789012345678/AbCdEfGh1234567890';
      expect(
        Security.maskWebhookUrl(url),
        'https://discord.com/api/webhooks/1234****/xxxx****',
      );
    });

    test('maskWebhookUrl selamat untuk input jahat', () {
      expect(Security.maskWebhookUrl('bukan-url'), 'webhooks/****');
      expect(Security.maskWebhookUrl(''), 'webhooks/****');
    });

    test('maskBotToken tidak mendedahkan apa-apa', () {
      const token = 'Aa1Bb2Cc3Dd4Ee5Ff6Gg77.Hh2Ii3.Jj4Kk5Ll6Mm7Nn8Oo9Pp0Qq1Rr2';
      final masked = Security.maskBotToken(token);
      expect(masked, 'Bot ****');
      expect(masked.contains(token), isFalse);
    });

    test('sanitizeJson menapis kunci sensitif', () {
      final out = Security.sanitizeJson({
        'id': 1,
        'name': 'webhook ujian',
        'url': 'https://discord.com/api/webhooks/123456789/SECRET_TOKEN',
        'token': 'SUPER_SECRET',
        'nested': {'authorization': 'Bearer xyz', 'safe': 'nilai'},
      }) as Map<String, dynamic>;

      expect(out['url'], 'https://discord.com/api/webhooks/1234****/xxxx****');
      expect(out['token'], '****');
      final nested = out['nested'] as Map<String, dynamic>;
      expect(nested['authorization'], '****');
      expect(nested['safe'], 'nilai');
    });

    test('sanitizeText membuang URL webhook penuh', () {
      const raw = 'permintaan ke https://discord.com/api/webhooks/987654321/TOKENRAHSIA gagal';
      final out = Security.sanitizeText(raw);
      expect(out.contains('TOKENRAHSIA'), isFalse);
      expect(out.contains('987654321'), isFalse);
    });

    test('buildCurl (webhook) tiada rahsia', () {
      const webhook =
          'https://discord.com/api/webhooks/123456789012345678/AbCdEfGh1234567890';
      final curl = Security.buildCurl(
        isWebhook: true,
        endpoint: webhook,
        fileNames: const ['gambar.png', 'video.mp4'],
        payloadJson: '{"content":"hello"}',
      );
      expect(curl.contains(webhook), isFalse);
      expect(curl.contains('AbCdEfGh1234567890'), isFalse);
      expect(curl.contains('files[0]=@gambar.png'), isTrue);
      expect(curl.contains('payload_json'), isTrue);
    });

    test('buildCurl (bot) token diganti ****', () {
      final curl = Security.buildCurl(
        isWebhook: false,
        endpoint: 'discord.com/api/v10/channels/123/messages',
        fileNames: const ['a.png'],
      );
      expect(curl.contains('Bot ****'), isTrue);
    });
  });

  group('Validators', () {
    test('URL webhook sah', () {
      expect(
        Validators.webhookUrl(
            'https://discord.com/api/webhooks/123456789012345678/abcDEF-_'),
        isNull,
      );
    });

    test('URL webhook tidak sah', () {
      expect(Validators.webhookUrl('http://discord.com/api/webhooks/123/abc'), isNotNull);
      expect(Validators.webhookUrl('https://contoh.com/api/webhooks/123/abc'), isNotNull);
      expect(Validators.webhookUrl(''), isNotNull);
    });

    test('Token bot sah', () {
      expect(
        Validators.botToken('Aa1Bb2Cc3Dd4Ee5Ff6Gg77.Hh2Ii3.Jj4Kk5Ll6Mm7Nn8Oo9Pp0Qq1Rr2'),
        isNull,
      );
      expect(Validators.botToken('pendek'), isNotNull);
    });

    test('Channel ID', () {
      expect(Validators.channelId('1234567890123456789'), isNull);
      expect(Validators.channelId('abc'), isNotNull);
      expect(Validators.channelId('123'), isNotNull);
    });
  });

  group('Formatters', () {
    test('formatBytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1572864), '1.5 MB');
      expect(formatBytes(1288490188), contains('GB'));
    });

    test('formatMs', () {
      expect(formatMs(320), '320ms');
      expect(formatMs(1250), '1.25s');
    });

    test('formatRelativeDay', () {
      final now = DateTime.now();
      expect(formatRelativeDay(now), 'Hari Ini');
      expect(formatRelativeDay(now.subtract(const Duration(days: 1))), 'Semalam');
    });
  });

  group('Enjin hantaran — pengelompokan', () {
    test('chunk bahagi ikut saiz batch', () {
      final items = List<MediaItem>.generate(23, (i) => MediaItem(
            id: 'x$i',
            path: '/p/f$i.png',
            name: 'f$i.png',
            sizeBytes: 100,
            type: MediaType.image,
            mimeType: 'image/png',
          ));
      final chunks = UploadEngine.chunkItems(items, 10);
      expect(chunks.length, 3);
      expect(chunks[0].length, 10);
      expect(chunks[1].length, 10);
      expect(chunks[2].length, 3);
    });

    test('chunk senarai kosong', () {
      expect(UploadEngine.chunkItems<MediaItem>(const [], 10), isEmpty);
    });
  });

  group('ErrorTranslator', () {
    test('401 diterjemah jelas', () {
      final e = ErrorTranslator.explain(statusCode: 401);
      expect(e.title, contains('Token tidak sah'));
      expect(e.suggestions, isNotEmpty);
    });

    test('kod Discord 50001', () {
      final e = ErrorTranslator.explain(statusCode: 403, discordCode: 50001);
      expect(e.title, contains('kebenaran'));
    });

    test('429 rate limit', () {
      final e = ErrorTranslator.explain(statusCode: 429);
      expect(e.title, contains('Had kadar'));
    });

    test('5xx pelayan', () {
      final e = ErrorTranslator.explain(statusCode: 502);
      expect(e.title, contains('pelayan'));
    });
  });

  group('Model', () {
    test('MediaItem JSON bulat penuh', () {
      final item = MediaItem(
        id: 'm-1',
        path: '/p/gambar.png',
        name: 'gambar.png',
        sizeBytes: 1234,
        type: MediaType.image,
        mimeType: 'image/png',
      );
      final copy = MediaItem.fromJson(item.toJson());
      expect(copy.id, item.id);
      expect(copy.name, item.name);
      expect(copy.type, MediaType.image);
    });

    test('FailedRecord.toMediaItem mengekalkan jenis', () {
      final rec = FailedRecord(
        fileName: 'klip.mp4',
        filePath: '/storage/klip.mp4',
        sizeBytes: 999,
        batchIndex: 2,
        httpCode: 413,
        errorMessage: 'terlalu besar',
        mode: 'webhook',
        target: '#webhook',
        createdAt: DateTime.now(),
      );
      final item = rec.toMediaItem();
      expect(item.type, MediaType.video);
      expect(item.mimeType, 'video/mp4');
      expect(item.name, 'klip.mp4');
    });

    test('SendConfig sedia hantar', () {
      const empty = SendConfig();
      expect(empty.readyToSend, isFalse);
      const wh = SendConfig(mode: SendMode.webhook, webhookUrl: 'https://discord.com/api/webhooks/1/a');
      expect(wh.readyToSend, isTrue);
      const bot = SendConfig(mode: SendMode.bot, botToken: 't', channelId: '123');
      expect(bot.readyToSend, isTrue);
    });
  });
}
