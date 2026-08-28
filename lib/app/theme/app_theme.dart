import 'dart:convert';

import 'package:androidircx/core/models/app_settings.dart';
import 'package:flutter/material.dart';

ThemeData buildAppTheme([AppSettings settings = const AppSettings()]) {
  final palette = _paletteFor(settings);
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: palette.brightness,
      ).copyWith(
        primary: palette.primary,
        secondary: palette.secondary,
        tertiary: palette.tertiary,
        surface: palette.surface,
        onSurface: palette.onSurface,
        surfaceContainer: palette.panel,
        surfaceContainerHighest: palette.panelAlt,
        primaryContainer: palette.ownMessage,
        onPrimaryContainer: palette.onSurface,
      );
  final chatTheme = IrcUiTheme._fromSettings(settings, palette);

  return ThemeData(
    colorScheme: colorScheme,
    brightness: palette.brightness,
    scaffoldBackgroundColor: palette.scaffold,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: palette.onSurface,
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.outline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.panel,
      selectedColor: palette.primary.withValues(alpha: 0.16),
      side: BorderSide(color: palette.outline),
      labelStyle: TextStyle(color: palette.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.primary, width: 1.4),
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[chatTheme],
  );
}

String customThemeJsonTemplate([AppSettings settings = const AppSettings()]) {
  final palette = _paletteFor(
    settings.themePreset == AppThemePreset.custom
        ? const AppSettings()
        : settings,
  );
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(<String, Object?>{
    'name': 'Custom IRC theme',
    'brightness': palette.brightness == Brightness.dark ? 'dark' : 'light',
    'primary': _hexColor(palette.primary),
    'secondary': _hexColor(palette.secondary),
    'tertiary': _hexColor(palette.tertiary),
    'scaffold': _hexColor(palette.scaffold),
    'surface': _hexColor(palette.surface),
    'card': _hexColor(palette.card),
    'panel': _hexColor(palette.panel),
    'messageOther': _hexColor(palette.messageOther),
    'messageOwn': _hexColor(palette.ownMessage),
    'messageSystem': _hexColor(palette.systemMessage),
    'messageError': _hexColor(palette.errorMessage),
    'messageDcc': _hexColor(palette.dccMessage),
    'messageMedia': _hexColor(palette.mediaMessage),
    'messageRaw': _hexColor(palette.rawMessage),
    'attachment': _hexColor(palette.attachment),
    'topic': _hexColor(palette.topic),
  });
}

class IrcUiTheme extends ThemeExtension<IrcUiTheme> {
  const IrcUiTheme({
    required this.messageOther,
    required this.messageOwn,
    required this.messageSystem,
    required this.messageError,
    required this.messageDcc,
    required this.messageMedia,
    required this.messageRaw,
    required this.attachment,
    required this.topic,
    required this.messageBorder,
    required this.messageFontSize,
    required this.messageFontFamily,
    required this.messagePadding,
    required this.messageSpacing,
    required this.nickColorMode,
    required this.nickPalette,
  });

  final Color messageOther;
  final Color messageOwn;
  final Color messageSystem;
  final Color messageError;
  final Color messageDcc;
  final Color messageMedia;
  final Color messageRaw;
  final Color attachment;
  final Color topic;
  final Color messageBorder;
  final double messageFontSize;
  final String? messageFontFamily;
  final EdgeInsets messagePadding;
  final double messageSpacing;
  final NickColorMode nickColorMode;
  final List<Color> nickPalette;

  factory IrcUiTheme._fromSettings(
    AppSettings settings,
    _ThemePalette palette,
  ) {
    final density = switch (settings.messageDensity) {
      MessageDensity.compact => (
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        spacing: 6.0,
      ),
      MessageDensity.comfortable => (
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        spacing: 10.0,
      ),
      MessageDensity.relaxed => (
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        spacing: 14.0,
      ),
    };
    return IrcUiTheme(
      messageOther: palette.messageOther,
      messageOwn: palette.ownMessage,
      messageSystem: palette.systemMessage,
      messageError: palette.errorMessage,
      messageDcc: palette.dccMessage,
      messageMedia: palette.mediaMessage,
      messageRaw: palette.rawMessage,
      attachment: palette.attachment,
      topic: palette.topic,
      messageBorder: palette.outline,
      messageFontSize: 14 * settings.messageFontScale,
      messageFontFamily: switch (settings.messageFontFamily) {
        'system' => settings.monospaceMessages ? 'monospace' : null,
        final family => family,
      },
      messagePadding: density.padding,
      messageSpacing: density.spacing,
      nickColorMode: settings.nickColorMode,
      nickPalette: palette.nickPalette,
    );
  }

  Color? nickColorFor(String nick) {
    if (nickColorMode == NickColorMode.none || nickPalette.isEmpty) {
      return null;
    }
    var hash = 0;
    for (final codeUnit in nick.toLowerCase().codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    final base = nickPalette[hash.abs() % nickPalette.length];
    return switch (nickColorMode) {
      NickColorMode.none => null,
      NickColorMode.soft => Color.lerp(base, messageOther, 0.24),
      NickColorMode.vivid => base,
    };
  }

  @override
  IrcUiTheme copyWith({
    Color? messageOther,
    Color? messageOwn,
    Color? messageSystem,
    Color? messageError,
    Color? messageDcc,
    Color? messageMedia,
    Color? messageRaw,
    Color? attachment,
    Color? topic,
    Color? messageBorder,
    double? messageFontSize,
    String? messageFontFamily,
    EdgeInsets? messagePadding,
    double? messageSpacing,
    NickColorMode? nickColorMode,
    List<Color>? nickPalette,
  }) {
    return IrcUiTheme(
      messageOther: messageOther ?? this.messageOther,
      messageOwn: messageOwn ?? this.messageOwn,
      messageSystem: messageSystem ?? this.messageSystem,
      messageError: messageError ?? this.messageError,
      messageDcc: messageDcc ?? this.messageDcc,
      messageMedia: messageMedia ?? this.messageMedia,
      messageRaw: messageRaw ?? this.messageRaw,
      attachment: attachment ?? this.attachment,
      topic: topic ?? this.topic,
      messageBorder: messageBorder ?? this.messageBorder,
      messageFontSize: messageFontSize ?? this.messageFontSize,
      messageFontFamily: messageFontFamily ?? this.messageFontFamily,
      messagePadding: messagePadding ?? this.messagePadding,
      messageSpacing: messageSpacing ?? this.messageSpacing,
      nickColorMode: nickColorMode ?? this.nickColorMode,
      nickPalette: nickPalette ?? this.nickPalette,
    );
  }

  @override
  IrcUiTheme lerp(ThemeExtension<IrcUiTheme>? other, double t) {
    if (other is! IrcUiTheme) {
      return this;
    }
    return IrcUiTheme(
      messageOther: Color.lerp(messageOther, other.messageOther, t)!,
      messageOwn: Color.lerp(messageOwn, other.messageOwn, t)!,
      messageSystem: Color.lerp(messageSystem, other.messageSystem, t)!,
      messageError: Color.lerp(messageError, other.messageError, t)!,
      messageDcc: Color.lerp(messageDcc, other.messageDcc, t)!,
      messageMedia: Color.lerp(messageMedia, other.messageMedia, t)!,
      messageRaw: Color.lerp(messageRaw, other.messageRaw, t)!,
      attachment: Color.lerp(attachment, other.attachment, t)!,
      topic: Color.lerp(topic, other.topic, t)!,
      messageBorder: Color.lerp(messageBorder, other.messageBorder, t)!,
      messageFontSize:
          messageFontSize + ((other.messageFontSize - messageFontSize) * t),
      messageFontFamily: t < 0.5 ? messageFontFamily : other.messageFontFamily,
      messagePadding: EdgeInsets.lerp(messagePadding, other.messagePadding, t)!,
      messageSpacing:
          messageSpacing + ((other.messageSpacing - messageSpacing) * t),
      nickColorMode: t < 0.5 ? nickColorMode : other.nickColorMode,
      nickPalette: t < 0.5 ? nickPalette : other.nickPalette,
    );
  }
}

extension IrcUiThemeLookup on BuildContext {
  IrcUiTheme get ircUiTheme {
    return Theme.of(this).extension<IrcUiTheme>() ??
        IrcUiTheme._fromSettings(const AppSettings(), _lightPalette);
  }
}

class _ThemePalette {
  const _ThemePalette({
    required this.brightness,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.scaffold,
    required this.surface,
    required this.card,
    required this.panel,
    required this.panelAlt,
    required this.onSurface,
    required this.outline,
    required this.messageOther,
    required this.ownMessage,
    required this.systemMessage,
    required this.errorMessage,
    required this.dccMessage,
    required this.mediaMessage,
    required this.rawMessage,
    required this.attachment,
    required this.topic,
    required this.nickPalette,
  });

  final Brightness brightness;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color scaffold;
  final Color surface;
  final Color card;
  final Color panel;
  final Color panelAlt;
  final Color onSurface;
  final Color outline;
  final Color messageOther;
  final Color ownMessage;
  final Color systemMessage;
  final Color errorMessage;
  final Color dccMessage;
  final Color mediaMessage;
  final Color rawMessage;
  final Color attachment;
  final Color topic;
  final List<Color> nickPalette;

  _ThemePalette copyWith({
    Brightness? brightness,
    Color? primary,
    Color? secondary,
    Color? tertiary,
    Color? scaffold,
    Color? surface,
    Color? card,
    Color? panel,
    Color? panelAlt,
    Color? onSurface,
    Color? outline,
    Color? messageOther,
    Color? ownMessage,
    Color? systemMessage,
    Color? errorMessage,
    Color? dccMessage,
    Color? mediaMessage,
    Color? rawMessage,
    Color? attachment,
    Color? topic,
    List<Color>? nickPalette,
  }) {
    return _ThemePalette(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      scaffold: scaffold ?? this.scaffold,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      panel: panel ?? this.panel,
      panelAlt: panelAlt ?? this.panelAlt,
      onSurface: onSurface ?? this.onSurface,
      outline: outline ?? this.outline,
      messageOther: messageOther ?? this.messageOther,
      ownMessage: ownMessage ?? this.ownMessage,
      systemMessage: systemMessage ?? this.systemMessage,
      errorMessage: errorMessage ?? this.errorMessage,
      dccMessage: dccMessage ?? this.dccMessage,
      mediaMessage: mediaMessage ?? this.mediaMessage,
      rawMessage: rawMessage ?? this.rawMessage,
      attachment: attachment ?? this.attachment,
      topic: topic ?? this.topic,
      nickPalette: nickPalette ?? this.nickPalette,
    );
  }
}

_ThemePalette _paletteFor(AppSettings settings) {
  return switch (settings.themePreset) {
    AppThemePreset.light => _lightPalette,
    AppThemePreset.dark => _darkPalette,
    AppThemePreset.ircap => _ircapPalette,
    AppThemePreset.custom => _customPalette(settings.customThemeJson),
  };
}

_ThemePalette _customPalette(String rawJson) {
  if (rawJson.trim().isEmpty) {
    return _lightPalette;
  }
  try {
    final decoded = jsonDecode(rawJson) as Map<String, Object?>;
    final brightness = (decoded['brightness'] as String?) == 'dark'
        ? Brightness.dark
        : Brightness.light;
    final fallback = brightness == Brightness.dark
        ? _darkPalette
        : _lightPalette;
    return fallback.copyWith(
      brightness: brightness,
      primary: _jsonColor(decoded['primary'], fallback.primary),
      secondary: _jsonColor(decoded['secondary'], fallback.secondary),
      tertiary: _jsonColor(decoded['tertiary'], fallback.tertiary),
      scaffold: _jsonColor(decoded['scaffold'], fallback.scaffold),
      surface: _jsonColor(decoded['surface'], fallback.surface),
      card: _jsonColor(decoded['card'], fallback.card),
      panel: _jsonColor(decoded['panel'], fallback.panel),
      panelAlt: _jsonColor(decoded['panelAlt'], fallback.panelAlt),
      messageOther: _jsonColor(decoded['messageOther'], fallback.messageOther),
      ownMessage: _jsonColor(decoded['messageOwn'], fallback.ownMessage),
      systemMessage: _jsonColor(
        decoded['messageSystem'],
        fallback.systemMessage,
      ),
      errorMessage: _jsonColor(decoded['messageError'], fallback.errorMessage),
      dccMessage: _jsonColor(decoded['messageDcc'], fallback.dccMessage),
      mediaMessage: _jsonColor(decoded['messageMedia'], fallback.mediaMessage),
      rawMessage: _jsonColor(decoded['messageRaw'], fallback.rawMessage),
      attachment: _jsonColor(decoded['attachment'], fallback.attachment),
      topic: _jsonColor(decoded['topic'], fallback.topic),
    );
  } catch (_) {
    return _lightPalette;
  }
}

Color _jsonColor(Object? value, Color fallback) {
  if (value is! String) {
    return fallback;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }
  final hex = trimmed.startsWith('#')
      ? trimmed.substring(1)
      : trimmed.startsWith('0x')
      ? trimmed.substring(2)
      : trimmed;
  final normalized = hex.length == 6 ? 'ff$hex' : hex;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    return fallback;
  }
  return Color(parsed);
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0x00ffffff;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

const _lightPalette = _ThemePalette(
  brightness: Brightness.light,
  primary: Color(0xFF2E8F62),
  secondary: Color(0xFF4C6F92),
  tertiary: Color(0xFF8A5A24),
  scaffold: Color(0xFFF2F5F6),
  surface: Color(0xFFF6F8FA),
  card: Color(0xFFFFFFFF),
  panel: Color(0xFFE9EEF1),
  panelAlt: Color(0xFFDDE6EA),
  onSurface: Color(0xFF15202B),
  outline: Color(0x1A000000),
  messageOther: Color(0xFFFFFFFF),
  ownMessage: Color(0xFFDCEFE5),
  systemMessage: Color(0xFFF1F4E8),
  errorMessage: Color(0xFFFFE5E8),
  dccMessage: Color(0xFFE1F4EF),
  mediaMessage: Color(0xFFFFF0D8),
  rawMessage: Color(0xFFECEFF3),
  attachment: Color(0xFFE6EEF4),
  topic: Color(0xFFFFFFFF),
  nickPalette: <Color>[
    Color(0xFF1E6B52),
    Color(0xFF3366A6),
    Color(0xFF8A5A24),
    Color(0xFF8B3D57),
    Color(0xFF5D6B1E),
    Color(0xFF6A4B9A),
    Color(0xFF15737A),
  ],
);

const _darkPalette = _ThemePalette(
  brightness: Brightness.dark,
  primary: Color(0xFF70C99A),
  secondary: Color(0xFF8CB4D8),
  tertiary: Color(0xFFE0B46D),
  scaffold: Color(0xFF111418),
  surface: Color(0xFF151A20),
  card: Color(0xFF1B2229),
  panel: Color(0xFF242C34),
  panelAlt: Color(0xFF2D3741),
  onSurface: Color(0xFFE9EDF1),
  outline: Color(0x26FFFFFF),
  messageOther: Color(0xFF1D252D),
  ownMessage: Color(0xFF214131),
  systemMessage: Color(0xFF303624),
  errorMessage: Color(0xFF4B252B),
  dccMessage: Color(0xFF1F403C),
  mediaMessage: Color(0xFF44351E),
  rawMessage: Color(0xFF272D35),
  attachment: Color(0xFF26333E),
  topic: Color(0xFF1F2830),
  nickPalette: <Color>[
    Color(0xFF70C99A),
    Color(0xFF8CB4D8),
    Color(0xFFE0B46D),
    Color(0xFFE18AA5),
    Color(0xFFB9C86B),
    Color(0xFFC3A6E8),
    Color(0xFF79CED5),
  ],
);

const _ircapPalette = _ThemePalette(
  brightness: Brightness.light,
  primary: Color(0xFF245B87),
  secondary: Color(0xFF6F7F2A),
  tertiary: Color(0xFFB25E2B),
  scaffold: Color(0xFFE6EBF2),
  surface: Color(0xFFEFF3F8),
  card: Color(0xFFF9FBFD),
  panel: Color(0xFFDCE4EE),
  panelAlt: Color(0xFFC8D5E4),
  onSurface: Color(0xFF102232),
  outline: Color(0x240D2535),
  messageOther: Color(0xFFFAFCFF),
  ownMessage: Color(0xFFD8E8F7),
  systemMessage: Color(0xFFE6EBCF),
  errorMessage: Color(0xFFFBE1DB),
  dccMessage: Color(0xFFDDF0E8),
  mediaMessage: Color(0xFFFFEDD0),
  rawMessage: Color(0xFFE1E6ED),
  attachment: Color(0xFFD8E2EC),
  topic: Color(0xFFF9FBFD),
  nickPalette: <Color>[
    Color(0xFF245B87),
    Color(0xFF6F7F2A),
    Color(0xFFB25E2B),
    Color(0xFF7F476B),
    Color(0xFF2E746F),
    Color(0xFF8A621B),
    Color(0xFF3E658E),
  ],
);
