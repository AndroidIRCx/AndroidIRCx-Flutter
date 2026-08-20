enum NoticeRoutingMode { server, active, notice, private }

enum AppThemePreset { light, dark, ircap, custom }

enum MessageDensity { compact, comfortable, relaxed }

enum NickColorMode { none, soft, vivid }

class AppSettings {
  const AppSettings({
    this.showRawEvents = true,
    this.noticeRouting = NoticeRoutingMode.server,
    this.showHeaderSearchButton = true,
    this.showAttachmentPreviews = true,
    this.dccDownloadDirectoryPath = '',
    this.mediaDownloadDirectoryPath = '',
    this.themePreset = AppThemePreset.light,
    this.customThemeJson = '',
    this.messageFontScale = 1.0,
    this.messageDensity = MessageDensity.comfortable,
    this.monospaceMessages = false,
    this.nickColorMode = NickColorMode.soft,
  });

  final bool showRawEvents;
  final NoticeRoutingMode noticeRouting;
  final bool showHeaderSearchButton;
  final bool showAttachmentPreviews;
  final String dccDownloadDirectoryPath;
  final String mediaDownloadDirectoryPath;
  final AppThemePreset themePreset;
  final String customThemeJson;
  final double messageFontScale;
  final MessageDensity messageDensity;
  final bool monospaceMessages;
  final NickColorMode nickColorMode;

  AppSettings copyWith({
    bool? showRawEvents,
    NoticeRoutingMode? noticeRouting,
    bool? showHeaderSearchButton,
    bool? showAttachmentPreviews,
    String? dccDownloadDirectoryPath,
    String? mediaDownloadDirectoryPath,
    AppThemePreset? themePreset,
    String? customThemeJson,
    double? messageFontScale,
    MessageDensity? messageDensity,
    bool? monospaceMessages,
    NickColorMode? nickColorMode,
  }) {
    return AppSettings(
      showRawEvents: showRawEvents ?? this.showRawEvents,
      noticeRouting: noticeRouting ?? this.noticeRouting,
      showHeaderSearchButton:
          showHeaderSearchButton ?? this.showHeaderSearchButton,
      showAttachmentPreviews:
          showAttachmentPreviews ?? this.showAttachmentPreviews,
      dccDownloadDirectoryPath:
          dccDownloadDirectoryPath ?? this.dccDownloadDirectoryPath,
      mediaDownloadDirectoryPath:
          mediaDownloadDirectoryPath ?? this.mediaDownloadDirectoryPath,
      themePreset: themePreset ?? this.themePreset,
      customThemeJson: customThemeJson ?? this.customThemeJson,
      messageFontScale: _clampFontScale(
        messageFontScale ?? this.messageFontScale,
      ),
      messageDensity: messageDensity ?? this.messageDensity,
      monospaceMessages: monospaceMessages ?? this.monospaceMessages,
      nickColorMode: nickColorMode ?? this.nickColorMode,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'showRawEvents': showRawEvents,
      'noticeRouting': noticeRouting.name,
      'showHeaderSearchButton': showHeaderSearchButton,
      'showAttachmentPreviews': showAttachmentPreviews,
      'dccDownloadDirectoryPath': dccDownloadDirectoryPath,
      'mediaDownloadDirectoryPath': mediaDownloadDirectoryPath,
      'themePreset': themePreset.name,
      'customThemeJson': customThemeJson,
      'messageFontScale': messageFontScale,
      'messageDensity': messageDensity.name,
      'monospaceMessages': monospaceMessages,
      'nickColorMode': nickColorMode.name,
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      showRawEvents: (json['showRawEvents'] as bool?) ?? true,
      noticeRouting: _enumByName(
        NoticeRoutingMode.values,
        json['noticeRouting'],
        NoticeRoutingMode.server,
      ),
      showHeaderSearchButton: (json['showHeaderSearchButton'] as bool?) ?? true,
      showAttachmentPreviews: (json['showAttachmentPreviews'] as bool?) ?? true,
      dccDownloadDirectoryPath:
          (json['dccDownloadDirectoryPath'] as String?)?.trim() ?? '',
      mediaDownloadDirectoryPath:
          (json['mediaDownloadDirectoryPath'] as String?)?.trim() ?? '',
      themePreset: _enumByName(
        AppThemePreset.values,
        json['themePreset'],
        AppThemePreset.light,
      ),
      customThemeJson: (json['customThemeJson'] as String?)?.trim() ?? '',
      messageFontScale: _clampFontScale(
        (json['messageFontScale'] as num?)?.toDouble() ?? 1.0,
      ),
      messageDensity: _enumByName(
        MessageDensity.values,
        json['messageDensity'],
        MessageDensity.comfortable,
      ),
      monospaceMessages: (json['monospaceMessages'] as bool?) ?? false,
      nickColorMode: _enumByName(
        NickColorMode.values,
        json['nickColorMode'],
        NickColorMode.soft,
      ),
    );
  }
}

double _clampFontScale(double value) {
  return value.clamp(0.8, 1.4).toDouble();
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return fallback;
}
