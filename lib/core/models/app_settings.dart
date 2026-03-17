enum NoticeRoutingMode { server, active, notice, private }

class AppSettings {
  const AppSettings({
    this.showRawEvents = true,
    this.noticeRouting = NoticeRoutingMode.server,
    this.showHeaderSearchButton = true,
    this.showAttachmentPreviews = true,
  });

  final bool showRawEvents;
  final NoticeRoutingMode noticeRouting;
  final bool showHeaderSearchButton;
  final bool showAttachmentPreviews;

  AppSettings copyWith({
    bool? showRawEvents,
    NoticeRoutingMode? noticeRouting,
    bool? showHeaderSearchButton,
    bool? showAttachmentPreviews,
  }) {
    return AppSettings(
      showRawEvents: showRawEvents ?? this.showRawEvents,
      noticeRouting: noticeRouting ?? this.noticeRouting,
      showHeaderSearchButton: showHeaderSearchButton ?? this.showHeaderSearchButton,
      showAttachmentPreviews: showAttachmentPreviews ?? this.showAttachmentPreviews,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'showRawEvents': showRawEvents,
      'noticeRouting': noticeRouting.name,
      'showHeaderSearchButton': showHeaderSearchButton,
      'showAttachmentPreviews': showAttachmentPreviews,
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
    );
  }
}
