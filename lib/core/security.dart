import 'dart:convert';

/// Lapisan keselamatan: SEBARANG token/URL webhook penuh tidak boleh
/// dipapar, disalin, atau dieksport. Semua output log/cURL melalui kelas ini.
class Security {
  Security._();

  static final _webhookRe =
      RegExp(r'(https?://[^/]+(?:/[^/]+)*?)/webhooks/(\d+)/([A-Za-z0-9_-]+)');

  /// Tapiskan URL webhook: .../webhooks/1234****/xxxx****
  static String maskWebhookUrl(String url) {
    final m = _webhookRe.firstMatch(url.trim());
    if (m == null) return 'webhooks/****';
    final id = m.group(2)!;
    final idMasked =
        id.length > 4 ? '${id.substring(0, 4)}****' : '****';
    return '${m.group(1)}/webhooks/$idMasked/xxxx****';
  }

  /// Token bot sentiasa diganti sepenuhnya.
  static String maskBotToken(String token) =>
      token.trim().isEmpty ? '' : 'Bot ****';

  /// Sapukan JSON secara rekursif: kunci yang mengandungi rahsia
  /// ditapis sebelum dipapar/dieksport.
  static Object? sanitizeJson(Object? node) {
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((k, v) {
        final key = k.toString();
        out[key] = _sanitizeValue(key, v);
      });
      return out;
    }
    if (node is List) {
      return node.map(sanitizeJson).toList();
    }
    return node;
  }

  static Object? _sanitizeValue(String key, Object? value) {
    final lower = key.toLowerCase();
    if (value is String) {
      if (lower.contains('token') || lower.contains('authorization')) {
        return '****';
      }
      if (lower == 'url' && value.contains('/webhooks/')) {
        return maskWebhookUrl(value);
      }
      if (value.contains('/api/webhooks/')) {
        return maskWebhookUrl(value);
      }
      return value;
    }
    return sanitizeJson(value);
  }

  /// Bina arahan cURL yang BOLEH dikongsi (rahsia ditapis).
  static String buildCurl({
    required bool isWebhook,
    required String endpoint,
    required List<String> fileNames,
    String? payloadJson,
  }) {
    final sb = StringBuffer("curl -X POST '");
    if (isWebhook) {
      sb.write(maskWebhookUrl(endpoint));
    } else {
      sb.write(endpoint); // /channels/{id}/messages — tiada rahsia
    }
    sb.write("' \\\n  -H 'Content-Type: multipart/form-data' ");
    if (!isWebhook) {
      sb.write("\\\n  -H 'Authorization: Bot ****' ");
    }
    if (payloadJson != null && payloadJson.isNotEmpty) {
      final masked = sanitizeJson(jsonDecode(payloadJson));
      final encoded = jsonEncode(masked).replaceAll("'", r"'\''");
      sb.write("\\\n  -F 'payload_json=$encoded' ");
    }
    for (var i = 0; i < fileNames.length; i++) {
      final name = fileNames[i].replaceAll("'", '');
      sb.write("\\\n  -F 'files[$i]=@$name'");
      if (i != fileNames.length - 1) sb.write(' ');
    }
    return sb.toString();
  }

  /// Pastikan teks bebas (log txt) tidak mengandungi URL webhook penuh.
  static String sanitizeText(String text) {
    return text.replaceAllMapped(_webhookRe, (m) => maskWebhookUrl(m.group(0)!));
  }
}
