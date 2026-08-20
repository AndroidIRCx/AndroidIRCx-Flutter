enum NoticeRoutingMode { server, active, notice, private }

class AppSettings {
  const AppSettings({
    this.showRawEvents = true,
    this.noticeRouting = NoticeRoutingMode.server,
    this.showHeaderSearchButton = true,
    this.showAttachmentPreviews = true,
    this.dccDownloadDirectoryPath = '',
    this.mediaDownloadDirectoryPath = '',
  });

  final bool showRawEvents;
  final NoticeRoutingMode noticeRouting;
  final bool showHeaderSearchButton;
  final bool showAttachmentPreviews;
  final String dccDownloadDirectoryPath;
  final String mediaDownloadDirectoryPath;

  AppSettings copyWith({
    bool? showRawEvents,
    NoticeRoutingMode? noticeRouting,
    bool? showHeaderSearchButton,
    bool? showAttachmentPreviews,
    String? dccDownloadDirectoryPath,
    String? mediaDownloadDirectoryPath,
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
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      showRawEvents: (json['showRawEvents'] as bool?) ?? true,
      noticeRouting: json['noticeRouting'] is String
          ? NoticeRoutingMode.values.byName(json['noticeRouting']! as String)
          : NoticeRoutingMode.server,
      showHeaderSearchButton: (json['showHeaderSearchButton'] as bool?) ?? true,
      showAttachmentPreviews: (json['showAttachmentPreviews'] as bool?) ?? true,
      dccDownloadDirectoryPath:
          (json['dccDownloadDirectoryPath'] as String?)?.trim() ?? '',
      mediaDownloadDirectoryPath:
          (json['mediaDownloadDirectoryPath'] as String?)?.trim() ?? '',
    );
  }
}
