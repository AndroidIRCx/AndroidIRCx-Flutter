enum NoticeRoutingMode { server, active, notice, private }

/// How sender nicks are decorated in the message list.
enum NickDisplayFormat { plain, angle, colon, bracket }

/// Where the timestamp sits relative to the sender nick.
enum TimestampPosition { afterNick, beforeNick }

enum AppThemePreset { light, dark, ircap, custom }

enum MessageDensity { compact, comfortable, relaxed }

enum NickColorMode { none, soft, vivid }

enum MediaAutoDownloadMode { never, wifiOnly, always }

class AppSettings {
  const AppSettings({
    this.showRawEvents = true,
    this.noticeRouting = NoticeRoutingMode.server,
    this.showHeaderSearchButton = true,
    this.showAttachmentPreviews = true,
    this.dccDownloadDirectoryPath = '',
    this.mediaDownloadDirectoryPath = '',
    this.mediaAutoDownloadMode = MediaAutoDownloadMode.never,
    this.themePreset = AppThemePreset.light,
    this.customThemeJson = '',
    this.messageFontScale = 1.0,
    this.messageDensity = MessageDensity.comfortable,
    this.monospaceMessages = false,
    this.messageFontFamily = 'system',
    this.nickColorMode = NickColorMode.soft,
    this.onboardingCompleted = false,
    this.appLockEnabled = false,
    this.analyticsConsent = false,
    this.notificationsEnabled = false,
    this.notifyHighlights = true,
    this.notifyPrivateMessages = true,
    this.notifyDccOffers = true,
    this.notifyErrors = true,
    this.notificationSound = true,
    this.hideJoinPartQuit = false,
    this.showTimestamps = true,
    this.timestampFormat = 'HH:mm',
    this.timestampPosition = TimestampPosition.afterNick,
    this.nickDisplayFormat = NickDisplayFormat.plain,
    this.enterToSend = true,
    this.showSendButton = true,
    this.composerAutocorrect = true,
    this.composerSuggestions = true,
    this.composerCapitalizeSentences = false,
    this.highlightWords = const <String>[],
    this.autoAwayEnabled = false,
    this.autoAwayMinutes = 10,
    this.awayMessage = 'Away',
    this.historyRetentionPerTab = 5000,
    this.autoRejoinOnKick = true,
    this.screenshotProtection = false,
  });

  final bool showRawEvents;
  final NoticeRoutingMode noticeRouting;
  final bool showHeaderSearchButton;
  final bool showAttachmentPreviews;
  final String dccDownloadDirectoryPath;
  final String mediaDownloadDirectoryPath;
  final MediaAutoDownloadMode mediaAutoDownloadMode;
  final AppThemePreset themePreset;
  final String customThemeJson;
  final double messageFontScale;
  final MessageDensity messageDensity;

  /// Legacy monospace toggle, kept for stored-settings migration; superseded
  /// by [messageFontFamily] whenever that is not 'system'.
  final bool monospaceMessages;

  /// Message font family: 'system' for the platform default, otherwise an
  /// Android family name ('monospace', 'serif', 'sans-serif', ...).
  final String messageFontFamily;
  final NickColorMode nickColorMode;

  /// Whether the first-run onboarding + consent flow has been completed.
  final bool onboardingCompleted;

  /// Whether the whole app is locked behind biometric/PIN on launch/resume.
  final bool appLockEnabled;

  // Notifications.
  /// Whether the user consented to Firebase Analytics + Crashlytics data
  /// collection. Off by default; collection stays disabled until this is true.
  final bool analyticsConsent;

  /// Master switch for notifications. Stays false until the OS notification
  /// permission (POST_NOTIFICATIONS) is granted; the per-type toggles below
  /// only take effect while this is true.
  final bool notificationsEnabled;
  final bool notifyHighlights;
  final bool notifyPrivateMessages;
  final bool notifyDccOffers;
  final bool notifyErrors;
  final bool notificationSound;

  // Display / writing.
  final bool hideJoinPartQuit;
  final bool showTimestamps;

  /// Timestamp pattern for message lines ('HH:mm', 'HH:mm:ss', 'h:mm a',
  /// 'h:mm:ss a').
  final String timestampFormat;
  final TimestampPosition timestampPosition;
  final NickDisplayFormat nickDisplayFormat;
  final bool enterToSend;
  final bool showSendButton;

  /// Composer keyboard behavior.
  final bool composerAutocorrect;
  final bool composerSuggestions;
  final bool composerCapitalizeSentences;

  /// Extra words (besides your nick) that trigger a highlight notification.
  final List<String> highlightWords;
  final bool autoAwayEnabled;
  final int autoAwayMinutes;
  final String awayMessage;

  /// Max messages kept per tab in the encrypted history (0 = unlimited).
  final int historyRetentionPerTab;

  /// Whether to rejoin a channel automatically after being kicked.
  final bool autoRejoinOnKick;

  /// Whether to block screenshots/screen recording (Android FLAG_SECURE).
  final bool screenshotProtection;

  AppSettings copyWith({
    bool? showRawEvents,
    NoticeRoutingMode? noticeRouting,
    bool? showHeaderSearchButton,
    bool? showAttachmentPreviews,
    String? dccDownloadDirectoryPath,
    String? mediaDownloadDirectoryPath,
    MediaAutoDownloadMode? mediaAutoDownloadMode,
    AppThemePreset? themePreset,
    String? customThemeJson,
    double? messageFontScale,
    MessageDensity? messageDensity,
    bool? monospaceMessages,
    String? messageFontFamily,
    NickColorMode? nickColorMode,
    bool? onboardingCompleted,
    bool? appLockEnabled,
    bool? analyticsConsent,
    bool? notificationsEnabled,
    bool? notifyHighlights,
    bool? notifyPrivateMessages,
    bool? notifyDccOffers,
    bool? notifyErrors,
    bool? notificationSound,
    bool? hideJoinPartQuit,
    bool? showTimestamps,
    String? timestampFormat,
    TimestampPosition? timestampPosition,
    NickDisplayFormat? nickDisplayFormat,
    bool? enterToSend,
    bool? showSendButton,
    bool? composerAutocorrect,
    bool? composerSuggestions,
    bool? composerCapitalizeSentences,
    List<String>? highlightWords,
    bool? autoAwayEnabled,
    int? autoAwayMinutes,
    String? awayMessage,
    int? historyRetentionPerTab,
    bool? autoRejoinOnKick,
    bool? screenshotProtection,
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
      mediaAutoDownloadMode:
          mediaAutoDownloadMode ?? this.mediaAutoDownloadMode,
      themePreset: themePreset ?? this.themePreset,
      customThemeJson: customThemeJson ?? this.customThemeJson,
      messageFontScale: _clampFontScale(
        messageFontScale ?? this.messageFontScale,
      ),
      messageDensity: messageDensity ?? this.messageDensity,
      monospaceMessages: monospaceMessages ?? this.monospaceMessages,
      messageFontFamily: messageFontFamily ?? this.messageFontFamily,
      nickColorMode: nickColorMode ?? this.nickColorMode,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      analyticsConsent: analyticsConsent ?? this.analyticsConsent,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyHighlights: notifyHighlights ?? this.notifyHighlights,
      notifyPrivateMessages:
          notifyPrivateMessages ?? this.notifyPrivateMessages,
      notifyDccOffers: notifyDccOffers ?? this.notifyDccOffers,
      notifyErrors: notifyErrors ?? this.notifyErrors,
      notificationSound: notificationSound ?? this.notificationSound,
      hideJoinPartQuit: hideJoinPartQuit ?? this.hideJoinPartQuit,
      showTimestamps: showTimestamps ?? this.showTimestamps,
      timestampFormat: timestampFormat ?? this.timestampFormat,
      timestampPosition: timestampPosition ?? this.timestampPosition,
      nickDisplayFormat: nickDisplayFormat ?? this.nickDisplayFormat,
      enterToSend: enterToSend ?? this.enterToSend,
      showSendButton: showSendButton ?? this.showSendButton,
      composerAutocorrect: composerAutocorrect ?? this.composerAutocorrect,
      composerSuggestions: composerSuggestions ?? this.composerSuggestions,
      composerCapitalizeSentences:
          composerCapitalizeSentences ?? this.composerCapitalizeSentences,
      highlightWords: highlightWords ?? this.highlightWords,
      autoAwayEnabled: autoAwayEnabled ?? this.autoAwayEnabled,
      autoAwayMinutes: autoAwayMinutes ?? this.autoAwayMinutes,
      awayMessage: awayMessage ?? this.awayMessage,
      historyRetentionPerTab:
          historyRetentionPerTab ?? this.historyRetentionPerTab,
      autoRejoinOnKick: autoRejoinOnKick ?? this.autoRejoinOnKick,
      screenshotProtection: screenshotProtection ?? this.screenshotProtection,
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
      'mediaAutoDownloadMode': mediaAutoDownloadMode.name,
      'themePreset': themePreset.name,
      'customThemeJson': customThemeJson,
      'messageFontScale': messageFontScale,
      'messageDensity': messageDensity.name,
      'monospaceMessages': monospaceMessages,
      'messageFontFamily': messageFontFamily,
      'nickColorMode': nickColorMode.name,
      'onboardingCompleted': onboardingCompleted,
      'appLockEnabled': appLockEnabled,
      'analyticsConsent': analyticsConsent,
      'notificationsEnabled': notificationsEnabled,
      'notifyHighlights': notifyHighlights,
      'notifyPrivateMessages': notifyPrivateMessages,
      'notifyDccOffers': notifyDccOffers,
      'notifyErrors': notifyErrors,
      'notificationSound': notificationSound,
      'hideJoinPartQuit': hideJoinPartQuit,
      'showTimestamps': showTimestamps,
      'timestampFormat': timestampFormat,
      'timestampPosition': timestampPosition.name,
      'nickDisplayFormat': nickDisplayFormat.name,
      'enterToSend': enterToSend,
      'showSendButton': showSendButton,
      'composerAutocorrect': composerAutocorrect,
      'composerSuggestions': composerSuggestions,
      'composerCapitalizeSentences': composerCapitalizeSentences,
      'highlightWords': highlightWords,
      'autoAwayEnabled': autoAwayEnabled,
      'autoAwayMinutes': autoAwayMinutes,
      'awayMessage': awayMessage,
      'historyRetentionPerTab': historyRetentionPerTab,
      'autoRejoinOnKick': autoRejoinOnKick,
      'screenshotProtection': screenshotProtection,
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
      mediaAutoDownloadMode: _enumByName(
        MediaAutoDownloadMode.values,
        json['mediaAutoDownloadMode'],
        MediaAutoDownloadMode.never,
      ),
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
      messageFontFamily:
          (json['messageFontFamily'] as String?)?.trim().isNotEmpty ?? false
          ? (json['messageFontFamily']! as String).trim()
          // Migrate the legacy monospace toggle into the font family.
          : ((json['monospaceMessages'] as bool?) ?? false)
          ? 'monospace'
          : 'system',
      nickColorMode: _enumByName(
        NickColorMode.values,
        json['nickColorMode'],
        NickColorMode.soft,
      ),
      onboardingCompleted: (json['onboardingCompleted'] as bool?) ?? false,
      appLockEnabled: (json['appLockEnabled'] as bool?) ?? false,
      analyticsConsent: (json['analyticsConsent'] as bool?) ?? false,
      notificationsEnabled: (json['notificationsEnabled'] as bool?) ?? false,
      notifyHighlights: (json['notifyHighlights'] as bool?) ?? true,
      notifyPrivateMessages: (json['notifyPrivateMessages'] as bool?) ?? true,
      notifyDccOffers: (json['notifyDccOffers'] as bool?) ?? true,
      notifyErrors: (json['notifyErrors'] as bool?) ?? true,
      notificationSound: (json['notificationSound'] as bool?) ?? true,
      hideJoinPartQuit: (json['hideJoinPartQuit'] as bool?) ?? false,
      showTimestamps: (json['showTimestamps'] as bool?) ?? true,
      timestampFormat:
          (json['timestampFormat'] as String?)?.trim().isNotEmpty ?? false
          ? (json['timestampFormat']! as String).trim()
          : 'HH:mm',
      timestampPosition: _enumByName(
        TimestampPosition.values,
        json['timestampPosition'],
        TimestampPosition.afterNick,
      ),
      nickDisplayFormat: _enumByName(
        NickDisplayFormat.values,
        json['nickDisplayFormat'],
        NickDisplayFormat.plain,
      ),
      enterToSend: (json['enterToSend'] as bool?) ?? true,
      showSendButton: (json['showSendButton'] as bool?) ?? true,
      composerAutocorrect: (json['composerAutocorrect'] as bool?) ?? true,
      composerSuggestions: (json['composerSuggestions'] as bool?) ?? true,
      composerCapitalizeSentences:
          (json['composerCapitalizeSentences'] as bool?) ?? false,
      highlightWords: _stringList(json['highlightWords']),
      autoAwayEnabled: (json['autoAwayEnabled'] as bool?) ?? false,
      autoAwayMinutes: (json['autoAwayMinutes'] as num?)?.toInt() ?? 10,
      awayMessage: (json['awayMessage'] as String?)?.trim().isEmpty ?? true
          ? 'Away'
          : (json['awayMessage'] as String).trim(),
      historyRetentionPerTab:
          (json['historyRetentionPerTab'] as num?)?.toInt() ?? 5000,
      autoRejoinOnKick: (json['autoRejoinOnKick'] as bool?) ?? true,
      screenshotProtection: (json['screenshotProtection'] as bool?) ?? false,
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
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
