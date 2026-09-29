import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_theme.dart';

/// Papar JSON cantik dengan syntax highlighting + boleh lipat.
/// Fon monospace (JetBrains Mono) hanya digunakan untuk kod/JSON.
class JsonView extends StatefulWidget {
  const JsonView({super.key, required this.json, this.initiallyExpanded = true});
  final Object? json;
  final bool initiallyExpanded;

  @override
  State<JsonView> createState() => _JsonViewState();
}

class _JsonViewState extends State<JsonView> {
  late bool _expanded = widget.initiallyExpanded;
  late final String _pretty;

  @override
  void initState() {
    super.initState();
    _pretty = _prettyPrint(widget.json);
  }

  String _prettyPrint(Object? json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(json);
    } catch (_) {
      return json?.toString() ?? 'null';
    }
  }

  List<InlineSpan> _highlight(String src) {
    final spans = <InlineSpan>[];
    final regex = RegExp(
      r'"(\\.|[^"\\])*"(?=\s*:)' // kunci
      r'|"(\\.|[^"\\])*"' // nilai string
      r'|-?\d+(\.\d+)?([eE][+-]?\d+)?' // nombor
      r'|\b(true|false|null)\b',
      multiLine: true,
    );
    var last = 0;
    for (final m in regex.allMatches(src)) {
      if (m.start > last) {
        spans.add(TextSpan(text: src.substring(last, m.start)));
      }
      final t = m.group(0)!;
      Color c;
      if (t.startsWith('"') && _isKey(m, src)) {
        c = AppColors.blurpleBright;
      } else if (t.startsWith('"')) {
        c = const Color(0xFF7BD88F);
      } else if (t == 'true' || t == 'false' || t == 'null') {
        c = const Color(0xFFC792EA);
      } else {
        c = const Color(0xFFF78C6C);
      }
      spans.add(TextSpan(text: t, style: TextStyle(color: c)));
      last = m.end;
    }
    if (last < src.length) spans.add(TextSpan(text: src.substring(last)));
    return spans;
  }

  bool _isKey(RegExpMatch m, String src) {
    var i = m.end;
    while (i < src.length &&
        (src[i] == ' ' || src[i] == '\n' || src[i] == '\t' || src[i] == '\r')) {
      i++;
    }
    return i < src.length && src[i] == ':';
  }

  TextStyle _mono(TextStyle? base) => GoogleFonts.jetBrainsMono(textStyle: base);
  @override
  Widget build(BuildContext context) {
    final label = _mono(Theme.of(context).textTheme.labelSmall);
    final body = _mono(Theme.of(context).textTheme.bodySmall);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.consoleBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Text(
                    'RESPONSE BODY (JSON)',
                    style: label.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: SingleChildScrollView(
                        child: SelectableText.rich(
                          TextSpan(
                            style: body.copyWith(
                                color: AppColors.consoleText, height: 1.5, fontSize: 12.5),
                            children: _highlight(_pretty),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Blok teks monospace ringkas (untuk endpoint/cURL).
class MonoBlock extends StatelessWidget {
  const MonoBlock(this.text, {super.key, this.maxLines});
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.jetBrainsMono(
      textStyle: Theme.of(context).textTheme.bodySmall,
    ).copyWith(color: AppColors.consoleText, fontSize: 12, height: 1.5);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.consoleBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.5)),
      ),
      child: SelectableText(
        text,
        style: style,
        maxLines: maxLines,
        minLines: 1,
      ),
    );
  }
}
