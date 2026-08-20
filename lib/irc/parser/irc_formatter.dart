class IrcFormatCodes {
  static const int bold = 0x02;
  static const int hexColor = 0x04;
  static const int color = 0x03;
  static const int reset = 0x0F;
  static const int monospace = 0x11;
  static const int reverse = 0x16;
  static const int italic = 0x1D;
  static const int strikethrough = 0x1E;
  static const int underline = 0x1F;
}

const Map<int, String> ircStandardColorMap = <int, String>{
  0: '#FFFFFF',
  1: '#000000',
  2: '#00007F',
  3: '#009300',
  4: '#FF0000',
  5: '#7F0000',
  6: '#9C009C',
  7: '#FC7F00',
  8: '#FFFF00',
  9: '#00FC00',
  10: '#009393',
  11: '#00FFFF',
  12: '#0000FC',
  13: '#FF00FF',
  14: '#7F7F7F',
  15: '#D2D2D2',
};

const Map<int, String> ircExtendedColorMap = <int, String>{
  16: '#470000',
  17: '#472100',
  18: '#474700',
  19: '#324700',
  20: '#004700',
  21: '#00472c',
  22: '#004747',
  23: '#002747',
  24: '#000047',
  25: '#2e0047',
  26: '#470047',
  27: '#47002a',
  28: '#740000',
  29: '#743a00',
  30: '#747400',
  31: '#517400',
  32: '#007400',
  33: '#007449',
  34: '#007474',
  35: '#004074',
  36: '#000074',
  37: '#4b0074',
  38: '#740074',
  39: '#740045',
  40: '#b50000',
  41: '#b56300',
  42: '#b5b500',
  43: '#7db500',
  44: '#00b500',
  45: '#00b571',
  46: '#00b5b5',
  47: '#0063b5',
  48: '#0000b5',
  49: '#7500b5',
  50: '#b500b5',
  51: '#b5006b',
  52: '#ff0000',
  53: '#ff8c00',
  54: '#ffff00',
  55: '#b2ff00',
  56: '#00ff00',
  57: '#00ffa0',
  58: '#00ffff',
  59: '#008cff',
  60: '#0000ff',
  61: '#a500ff',
  62: '#ff00ff',
  63: '#ff0098',
  64: '#ff5959',
  65: '#ffb459',
  66: '#ffff71',
  67: '#cfff60',
  68: '#6fff6f',
  69: '#65ffc9',
  70: '#6dffff',
  71: '#59b4ff',
  72: '#5959ff',
  73: '#c459ff',
  74: '#ff66ff',
  75: '#ff59bc',
  76: '#ff9c9c',
  77: '#ffd39c',
  78: '#ffff9c',
  79: '#e2ff9c',
  80: '#9cff9c',
  81: '#9cffdb',
  82: '#9cffff',
  83: '#9cd3ff',
  84: '#9c9cff',
  85: '#dc9cff',
  86: '#ff9cff',
  87: '#ff94d3',
  88: '#000000',
  89: '#131313',
  90: '#282828',
  91: '#363636',
  92: '#4d4d4d',
  93: '#656565',
  94: '#818181',
  95: '#9f9f9f',
  96: '#bcbcbc',
  97: '#e2e2e2',
  98: '#ffffff',
};

class IrcFormatStyle {
  const IrcFormatStyle({
    this.bold = false,
    this.underline = false,
    this.italic = false,
    this.strikethrough = false,
    this.monospace = false,
    this.reverse = false,
    this.color,
    this.background,
    this.colorHex,
    this.backgroundHex,
  });

  final bool bold;
  final bool underline;
  final bool italic;
  final bool strikethrough;
  final bool monospace;
  final bool reverse;
  final int? color;
  final int? background;
  final String? colorHex;
  final String? backgroundHex;

  IrcFormatStyle copyWith({
    bool? bold,
    bool? underline,
    bool? italic,
    bool? strikethrough,
    bool? monospace,
    bool? reverse,
    int? color,
    int? background,
    String? colorHex,
    String? backgroundHex,
    bool clearColor = false,
    bool clearBackground = false,
  }) {
    return IrcFormatStyle(
      bold: bold ?? this.bold,
      underline: underline ?? this.underline,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      monospace: monospace ?? this.monospace,
      reverse: reverse ?? this.reverse,
      color: clearColor || colorHex != null ? null : (color ?? this.color),
      background: clearBackground || backgroundHex != null
          ? null
          : (background ?? this.background),
      colorHex: clearColor || color != null
          ? null
          : (colorHex ?? this.colorHex),
      backgroundHex: clearBackground || background != null
          ? null
          : (backgroundHex ?? this.backgroundHex),
    );
  }
}

class IrcTextSegment {
  const IrcTextSegment({required this.text, required this.style});

  final String text;
  final IrcFormatStyle style;
}

class IrcLinkSegment {
  const IrcLinkSegment({required this.text, required this.style, this.url});

  final String text;
  final IrcFormatStyle style;
  final String? url;

  bool get isLink => url != null;
}

final RegExp _ircUrlPattern = RegExp(
  r'(https?:\/\/[^\s<>"{}|\\^`\[\]]+|ftp:\/\/[^\s<>"{}|\\^`\[\]]+|www\.[^\s<>"{}|\\^`\[\]]+)',
  caseSensitive: false,
);

String? getIrcColorHex(int code) {
  if (code >= 16 && code <= 98) {
    return ircExtendedColorMap[code];
  }
  return ircStandardColorMap[code];
}

List<IrcTextSegment> parseIrcText(String text) {
  if (text.isEmpty) {
    return const <IrcTextSegment>[];
  }

  final segments = <IrcTextSegment>[];
  var currentText = '';
  var i = 0;
  var currentStyle = const IrcFormatStyle();

  void flushText() {
    if (currentText.isEmpty) {
      return;
    }
    segments.add(IrcTextSegment(text: currentText, style: currentStyle));
    currentText = '';
  }

  while (i < text.length) {
    final charCode = text.codeUnitAt(i);

    switch (charCode) {
      case IrcFormatCodes.bold:
        flushText();
        currentStyle = currentStyle.copyWith(bold: !currentStyle.bold);
        i += 1;
        continue;
      case IrcFormatCodes.hexColor:
        flushText();
        final parsed = _parseHexColorSequence(text, i);
        i = parsed.nextIndex;
        if (parsed.foreground == null && parsed.background == null) {
          currentStyle = currentStyle.copyWith(
            clearColor: true,
            clearBackground: true,
          );
        } else {
          currentStyle = currentStyle.copyWith(
            colorHex: parsed.foreground ?? currentStyle.colorHex,
            backgroundHex: parsed.background ?? currentStyle.backgroundHex,
          );
        }
        continue;
      case IrcFormatCodes.color:
        flushText();
        final parsed = _parseColorSequence(text, i);
        i = parsed.nextIndex;
        if (parsed.foreground == null && parsed.background == null) {
          currentStyle = currentStyle.copyWith(
            clearColor: true,
            clearBackground: true,
          );
        } else {
          currentStyle = currentStyle.copyWith(
            color: parsed.foreground ?? currentStyle.color,
            background: parsed.background ?? currentStyle.background,
          );
        }
        continue;
      case IrcFormatCodes.reset:
        flushText();
        currentStyle = const IrcFormatStyle();
        i += 1;
        continue;
      case IrcFormatCodes.underline:
        flushText();
        currentStyle = currentStyle.copyWith(
          underline: !currentStyle.underline,
        );
        i += 1;
        continue;
      case IrcFormatCodes.monospace:
        flushText();
        currentStyle = currentStyle.copyWith(
          monospace: !currentStyle.monospace,
        );
        i += 1;
        continue;
      case IrcFormatCodes.italic:
        flushText();
        currentStyle = currentStyle.copyWith(italic: !currentStyle.italic);
        i += 1;
        continue;
      case IrcFormatCodes.strikethrough:
        flushText();
        currentStyle = currentStyle.copyWith(
          strikethrough: !currentStyle.strikethrough,
        );
        i += 1;
        continue;
      case IrcFormatCodes.reverse:
        flushText();
        currentStyle = currentStyle.copyWith(reverse: !currentStyle.reverse);
        i += 1;
        continue;
      default:
        currentText += text[i];
        i += 1;
    }
  }

  flushText();
  return segments;
}

String stripIrcFormatting(String text) {
  if (text.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final charCode = text.codeUnitAt(i);
    switch (charCode) {
      case IrcFormatCodes.bold:
      case IrcFormatCodes.reset:
      case IrcFormatCodes.underline:
      case IrcFormatCodes.monospace:
      case IrcFormatCodes.italic:
      case IrcFormatCodes.strikethrough:
      case IrcFormatCodes.reverse:
        i += 1;
        continue;
      case IrcFormatCodes.hexColor:
        i = _parseHexColorSequence(text, i).nextIndex;
        continue;
      case IrcFormatCodes.color:
        i = _parseColorSequence(text, i).nextIndex;
        continue;
      default:
        buffer.write(text[i]);
        i += 1;
    }
  }

  return buffer.toString();
}

String formatIrcPlainText(String text, {bool collapseWhitespace = false}) {
  final stripped = stripIrcFormatting(text);
  if (!collapseWhitespace) {
    return stripped;
  }
  return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String formatIrcDebug(String text) {
  if (text.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final charCode = text.codeUnitAt(i);
    switch (charCode) {
      case IrcFormatCodes.bold:
        buffer.write('[B]');
        i += 1;
      case IrcFormatCodes.hexColor:
        final parsed = _parseHexColorSequence(text, i);
        final colorBuffer = StringBuffer('[HC');
        if (parsed.foreground != null) {
          colorBuffer.write(parsed.foreground);
        }
        if (parsed.background != null) {
          colorBuffer.write(',${parsed.background}');
        }
        colorBuffer.write(']');
        buffer.write(colorBuffer.toString());
        i = parsed.nextIndex;
      case IrcFormatCodes.color:
        final parsed = _parseColorSequence(text, i);
        final colorBuffer = StringBuffer('[C');
        if (parsed.foreground != null) {
          colorBuffer.write(parsed.foreground);
        }
        if (parsed.background != null) {
          colorBuffer.write(',${parsed.background}');
        }
        colorBuffer.write(']');
        buffer.write(colorBuffer.toString());
        i = parsed.nextIndex;
      case IrcFormatCodes.reset:
        buffer.write('[R]');
        i += 1;
      case IrcFormatCodes.underline:
        buffer.write('[U]');
        i += 1;
      case IrcFormatCodes.monospace:
        buffer.write('[M]');
        i += 1;
      case IrcFormatCodes.italic:
        buffer.write('[I]');
        i += 1;
      case IrcFormatCodes.strikethrough:
        buffer.write('[S]');
        i += 1;
      case IrcFormatCodes.reverse:
        buffer.write('[REV]');
        i += 1;
      default:
        buffer.write(text[i]);
        i += 1;
    }
  }
  return buffer.toString();
}

List<IrcLinkSegment> parseIrcTextWithLinks(String text) {
  final output = <IrcLinkSegment>[];
  for (final segment in parseIrcText(text)) {
    var lastIndex = 0;
    for (final match in _ircUrlPattern.allMatches(segment.text)) {
      if (match.start > lastIndex) {
        output.add(
          IrcLinkSegment(
            text: segment.text.substring(lastIndex, match.start),
            style: segment.style,
          ),
        );
      }
      final rawUrl = match.group(0)!;
      final fullUrl = rawUrl.toLowerCase().startsWith('www.')
          ? 'https://$rawUrl'
          : rawUrl;
      output.add(
        IrcLinkSegment(text: rawUrl, style: segment.style, url: fullUrl),
      );
      lastIndex = match.end;
    }
    if (lastIndex < segment.text.length) {
      output.add(
        IrcLinkSegment(
          text: segment.text.substring(lastIndex),
          style: segment.style,
        ),
      );
    }
    if (segment.text.isEmpty) {
      output.add(IrcLinkSegment(text: '', style: segment.style));
    }
  }
  return output;
}

class _ParsedColorSequence {
  const _ParsedColorSequence({
    required this.nextIndex,
    this.foreground,
    this.background,
  });

  final int nextIndex;
  final int? foreground;
  final int? background;
}

class _ParsedHexColorSequence {
  const _ParsedHexColorSequence({
    required this.nextIndex,
    this.foreground,
    this.background,
  });

  final int nextIndex;
  final String? foreground;
  final String? background;
}

_ParsedColorSequence _parseColorSequence(String text, int start) {
  var i = start + 1;
  int? foreground;
  int? background;

  int? readNumber() {
    if (i >= text.length || !_isAsciiDigit(text.codeUnitAt(i))) {
      return null;
    }

    final first = text.codeUnitAt(i) - 48;
    if (i + 1 < text.length && _isAsciiDigit(text.codeUnitAt(i + 1))) {
      final second = text.codeUnitAt(i + 1) - 48;
      i += 2;
      return (first * 10) + second;
    }

    i += 1;
    return first;
  }

  foreground = readNumber();
  if (i < text.length && text[i] == ',') {
    final commaIndex = i;
    i += 1;
    background = readNumber();
    if (background == null) {
      i = commaIndex;
    }
  }

  return _ParsedColorSequence(
    nextIndex: i,
    foreground: foreground,
    background: background,
  );
}

_ParsedHexColorSequence _parseHexColorSequence(String text, int start) {
  var i = start + 1;

  String? readHex() {
    if (i + 6 > text.length) {
      return null;
    }
    final candidate = text.substring(i, i + 6);
    if (!_isHexColor(candidate)) {
      return null;
    }
    i += 6;
    return '#${candidate.toUpperCase()}';
  }

  final foreground = readHex();
  String? background;
  if (foreground != null && i < text.length && text[i] == ',') {
    final commaIndex = i;
    i += 1;
    background = readHex();
    if (background == null) {
      i = commaIndex;
    }
  }

  return _ParsedHexColorSequence(
    nextIndex: i,
    foreground: foreground,
    background: background,
  );
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

bool _isHexColor(String value) {
  if (value.length != 6) {
    return false;
  }
  for (var i = 0; i < value.length; i += 1) {
    final unit = value.codeUnitAt(i);
    final isDigit = unit >= 48 && unit <= 57;
    final isUpper = unit >= 65 && unit <= 70;
    final isLower = unit >= 97 && unit <= 102;
    if (!isDigit && !isUpper && !isLower) {
      return false;
    }
  }
  return true;
}
