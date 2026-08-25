import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:androidircx/irc/parser/interactive_message_parser.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';

class IrcFormattedText extends StatelessWidget {
  const IrcFormattedText(
    this.text, {
    super.key,
    this.baseStyle,
    this.maxLines,
    this.overflow,
    this.leading,
    this.knownNicks = const <String>{},
    this.channelPrefixes = '#&',
    this.nickPrefixes = '~&@%+',
    this.contextNick,
    this.onNickTap,
    this.onNickLongPress,
    this.onChannelTap,
  });

  final String text;
  final TextStyle? baseStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Inline spans (e.g. sender + timestamp) rendered before the content so the
  /// message flows on one line and only wraps when it is long.
  final List<InlineSpan>? leading;
  final Set<String> knownNicks;
  final String channelPrefixes;
  final String nickPrefixes;
  final String? contextNick;
  final ValueChanged<String>? onNickTap;
  final ValueChanged<String>? onNickLongPress;
  final ValueChanged<String>? onChannelTap;

  @override
  Widget build(BuildContext context) {
    final segments = parseInteractiveMessageTokens(
      text,
      knownNicks: knownNicks,
      channelPrefixes: channelPrefixes,
      nickPrefixes: nickPrefixes,
      contextNick: contextNick,
    );
    final contentSpans = segments.isEmpty
        ? <InlineSpan>[TextSpan(text: text, style: baseStyle)]
        : segments.map<InlineSpan>(_spanForToken).toList(growable: false);

    return Text.rich(
      TextSpan(children: [...?leading, ...contentSpans]),
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  InlineSpan _spanForToken(InteractiveMessageToken token) {
    final style = _resolveTextStyle(baseStyle, token);
    switch (token.type) {
      case InteractiveMessageTokenType.url:
        return TextSpan(
          text: token.text,
          style: style,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openExternalUrl(token.url!),
        );
      case InteractiveMessageTokenType.channel:
        final target = token.value;
        if (target == null || onChannelTap == null) {
          return TextSpan(text: token.text, style: style);
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => onChannelTap!(target),
            child: RichText(
              text: TextSpan(text: token.text, style: style),
            ),
          ),
        );
      case InteractiveMessageTokenType.nick:
      case InteractiveMessageTokenType.hostmask:
      case InteractiveMessageTokenType.userHost:
        final target = token.value;
        if (target == null || (onNickTap == null && onNickLongPress == null)) {
          return TextSpan(text: token.text, style: style);
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onNickTap == null ? null : () => onNickTap!(target),
            onLongPress: onNickLongPress == null
                ? null
                : () => onNickLongPress!(target),
            child: RichText(
              text: TextSpan(text: token.text, style: style),
            ),
          ),
        );
      case InteractiveMessageTokenType.text:
        return TextSpan(text: token.text, style: style);
    }
  }

  TextStyle _resolveTextStyle(
    TextStyle? base,
    InteractiveMessageToken segment,
  ) {
    final style = segment.style;
    final isLink =
        segment.type == InteractiveMessageTokenType.url ||
        segment.type == InteractiveMessageTokenType.channel ||
        segment.type == InteractiveMessageTokenType.nick ||
        segment.type == InteractiveMessageTokenType.hostmask ||
        segment.type == InteractiveMessageTokenType.userHost;
    var foregroundHex =
        style.colorHex ??
        (style.color == null ? null : getIrcColorHex(style.color!));
    var backgroundHex =
        style.backgroundHex ??
        (style.background == null ? null : getIrcColorHex(style.background!));

    if (style.reverse && foregroundHex != null && backgroundHex != null) {
      final swappedForeground = backgroundHex;
      backgroundHex = foregroundHex;
      foregroundHex = swappedForeground;
    } else if (style.reverse && foregroundHex != null) {
      backgroundHex = foregroundHex;
      foregroundHex = null;
    } else if (style.reverse && backgroundHex != null) {
      foregroundHex = backgroundHex;
      backgroundHex = null;
    }

    var textStyle = base ?? const TextStyle();
    if (foregroundHex != null) {
      textStyle = textStyle.copyWith(color: _parseHexColor(foregroundHex));
    }
    if (backgroundHex != null) {
      textStyle = textStyle.copyWith(
        backgroundColor: _parseHexColor(backgroundHex),
      );
    }
    if (style.bold) {
      textStyle = textStyle.copyWith(fontWeight: FontWeight.bold);
    }
    if (style.italic) {
      textStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
    }
    if (style.monospace) {
      textStyle = textStyle.copyWith(fontFamily: 'monospace');
    }

    final decorations = <TextDecoration>{};
    if (style.underline || isLink) {
      decorations.add(TextDecoration.underline);
    }
    if (style.strikethrough) {
      decorations.add(TextDecoration.lineThrough);
    }
    if (decorations.isNotEmpty) {
      textStyle = textStyle.copyWith(
        decoration: TextDecoration.combine(decorations.toList(growable: false)),
      );
    }

    if (isLink && foregroundHex == null) {
      textStyle = textStyle.copyWith(color: const Color(0xFF1565C0));
    }

    return textStyle;
  }

  Color _parseHexColor(String value) {
    final normalized = value.replaceFirst('#', '');
    return Color(int.parse('FF$normalized', radix: 16));
  }
}

Future<void> _openExternalUrl(String value) async {
  final uri = Uri.tryParse(value.startsWith('http') ? value : 'https://$value');
  if (uri == null) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
