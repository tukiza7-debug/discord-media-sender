import 'package:dio/dio.dart';

/// Translates technical errors into plain, easy-to-understand English,
/// along with suggested fixes.
class ErrorExplanation {
  const ErrorExplanation({
    required this.title,
    required this.detail,
    this.suggestions = const [],
  });

  final String title;
  final String detail;
  final List<String> suggestions;

  @override
  String toString() => title;
}

class ErrorTranslator {
  ErrorTranslator._();

  static const _httpTitles = <int, String>{
    400: 'Invalid request',
    401: 'Invalid token',
    403: 'Access denied',
    404: 'Not found',
    405: 'Method not allowed',
    413: 'Payload too large',
    429: 'Rate limited',
  };

  static const _discordCodes = <int, String>{
    // B07a: kod 0 SENGJAHAH tiada di sini — Discord pulangkan {"message":
    // "401: Unauthorized","code":0} dan seumpamanya; memetakan 0 kepada
    // 'General error' menutup penerangan HTTP yang lebih tepat.
    10003: 'Channel not found',
    10004: 'Server not found',
    10015: 'Unknown webhook',
    10057: 'Invalid webhook channel',
    30007: 'Server reached its maximum number of webhooks',
    40005: 'File exceeds the maximum size',
    50001: 'No access to the channel',
    50006: 'Message cannot be empty',
    50013: 'Insufficient permissions',
    50027: 'Invalid webhook token',
    50035: 'Invalid form body',
    50046: 'Invalid webhook permissions',
    50074: 'Channel does not support file uploads',
  };

  /// Interpret an error from the HTTP status + Discord error code + error type.
  static ErrorExplanation explain({
    int? statusCode,
    int? discordCode,
    Object? error,
  }) {
    // Network / Dio errors.
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.cancel:
          return const ErrorExplanation(
            title: 'Request cancelled',
            detail: 'The upload was stopped before it finished.',
          );
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const ErrorExplanation(
            title: 'Connection timed out',
            detail: 'Discord took too long to respond.',
            suggestions: ['Check your internet connection', 'Try again later'],
          );
        case DioExceptionType.connectionError:
          return const ErrorExplanation(
            title: 'No internet connection',
            detail: 'The device could not reach Discord.',
            suggestions: [
              'Check Wi-Fi or mobile data',
              'Make sure no VPN/firewall blocks discord.com',
            ],
          );
        case DioExceptionType.badCertificate:
          return const ErrorExplanation(
            title: 'Untrusted certificate',
            detail: 'The HTTPS connection to Discord could not be verified.',
            suggestions: ['Check the device date & time'],
          );
        default:
          break;
      }
    }

    // Discord-specific codes.
    // B07a: kod 0 diabaikan — ia hanya mengulangi status HTTP
    // (cth. {"message":"401: Unauthorized","code":0}); peta HTTP
    // memberi penerangan yang lebih tepat (cth. 'Invalid token').
    if (discordCode != null &&
        discordCode > 0 &&
        _discordCodes.containsKey(discordCode)) {
      return _forDiscordCode(discordCode);
    }

    // HTTP status.
    if (statusCode != null) {
      if (statusCode == 429) {
        return const ErrorExplanation(
          title: 'Discord rate limit',
          detail: 'Too many requests in a short time. '
              'The app will wait as instructed by Discord before retrying.',
          suggestions: ['Reduce the number of files or try again later'],
        );
      }
      if (statusCode >= 500) {
        return ErrorExplanation(
          title: 'Discord server problem ($statusCode)',
          detail: 'Discord servers are having a temporary issue.',
          suggestions: ['Retry in a few minutes', 'Check the Discord status page'],
        );
      }
      final t = _httpTitles[statusCode];
      if (t != null) return _forHttpTitle(statusCode, t);
      return ErrorExplanation(
        title: 'HTTP error $statusCode',
        detail: 'Discord rejected this request.',
        suggestions: ['Check the configuration and files, then retry'],
      );
    }

    return const ErrorExplanation(
      title: 'Unknown error',
      detail: 'Something unexpected happened while sending.',
      suggestions: ['Try again; if it persists, check the response log'],
    );
  }

  static ErrorExplanation _forDiscordCode(int code) {
    switch (code) {
      case 10003:
        return const ErrorExplanation(
          title: 'Channel not found',
          detail: 'The given Channel ID does not exist or the bot is not there.',
          suggestions: ['Check the Channel ID', 'Make sure the bot was added to that server'],
        );
      case 10004:
        return const ErrorExplanation(
          title: 'Server not found',
          detail: 'The server (guild) does not exist or is not accessible.',
        );
      case 10015:
        return const ErrorExplanation(
          title: 'Unknown webhook',
          detail: 'This webhook no longer exists (it may have been deleted).',
          suggestions: [
            'Create a new webhook and update the URL in the app',
          ],
        );
      case 30007:
        return const ErrorExplanation(
          title: 'Webhook limit reached',
          detail: 'This server has reached its maximum number of webhooks.',
        );
      case 40005:
        return const ErrorExplanation(
          title: 'File too large',
          detail: 'The file size exceeds the limit Discord allows for this server.',
          suggestions: ['Compress the video/image', 'Use a smaller file'],
        );
      case 50001:
        return const ErrorExplanation(
          title: 'Missing access',
          detail: 'The bot lacks permission to view/send in this channel.',
          suggestions: [
            'Make sure the bot has Send Messages & Attach Files permissions',
            'Check channel-specific permission overrides',
          ],
        );
      case 50006:
        return const ErrorExplanation(
          title: 'Empty message',
          detail: 'No text or file was included in this request.',
        );
      case 50013:
        return const ErrorExplanation(
          title: 'Insufficient permissions',
          detail: "The bot's role is missing the required permissions.",
          suggestions: [
            'Move the bot role higher in the role list',
            'Allow Send Messages, Attach Files and Embed Links',
          ],
        );
      case 50027:
        return const ErrorExplanation(
          title: 'Invalid webhook token',
          detail: 'The webhook URL/token is wrong or outdated.',
          suggestions: [
            'Copy the webhook URL again from Discord',
            'Re-create the webhook if it was regenerated',
          ],
        );
      case 50035:
        return const ErrorExplanation(
          title: 'Invalid form body',
          detail: 'Discord rejected the request payload as malformed.',
          suggestions: [
            'Check the caption for invalid characters',
            'Make sure the files are valid media files',
          ],
        );
      case 50046:
        return const ErrorExplanation(
          title: 'Invalid webhook permissions',
          detail: 'The webhook does not have the required permissions.',
        );
      case 50074:
        return const ErrorExplanation(
          title: 'Channel does not support files',
          detail: 'This channel does not allow attachments.',
        );
      default:
        return ErrorExplanation(
          title: 'Discord error (code $code)',
          detail: 'Discord returned this specific error code.',
        );
    }
  }

  static ErrorExplanation _forHttpTitle(int status, String title) {
    switch (status) {
      case 400:
        return const ErrorExplanation(
          title: 'Invalid request',
          detail: 'Discord did not accept the request format.',
          suggestions: [
            'Make sure the webhook URL is correct',
            'Make sure the file type is supported',
          ],
        );
      case 401:
        return const ErrorExplanation(
          title: 'Invalid token',
          detail: 'The bot token or webhook credentials were rejected. '
              'The token may be wrong, reset, or deleted.',
          suggestions: [
            'Re-check the bot token in the Developer Portal',
            'If the token was just reset, update it in the app',
            'Make sure there are no spaces at the start/end of the token',
          ],
        );
      case 403:
        return const ErrorExplanation(
          title: 'Access denied',
          detail: 'The token is valid but lacks permission for this action.',
          suggestions: [
            'Check the bot permissions on the target channel',
            'Make sure the webhook still exists and was not deleted',
          ],
        );
      case 404:
        return const ErrorExplanation(
          title: 'Not found',
          detail: 'The webhook or channel no longer exists (it may have been deleted).',
          suggestions: ['Check the webhook URL / Channel ID'],
        );
      case 413:
        return const ErrorExplanation(
          title: 'Payload too large',
          detail: 'The total request size exceeds the Discord limit.',
          suggestions: ['Reduce the size or number of files per batch'],
        );
      default:
        return ErrorExplanation(title: title, detail: 'HTTP error $status from Discord.');
    }
  }

  /// One-line summary for snackbars/lists.
  static String shortReason({int? statusCode, int? discordCode, Object? error}) =>
      explain(statusCode: statusCode, discordCode: discordCode, error: error).title;
}
