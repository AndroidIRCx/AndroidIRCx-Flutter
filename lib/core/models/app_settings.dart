class AppSettings {
  const AppSettings({
    this.showRawEvents = true,
  });

  final bool showRawEvents;

  AppSettings copyWith({
    bool? showRawEvents,
  }) {
    return AppSettings(
      showRawEvents: showRawEvents ?? this.showRawEvents,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'showRawEvents': showRawEvents,
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      showRawEvents: (json['showRawEvents'] as bool?) ?? true,
    );
  }
}
