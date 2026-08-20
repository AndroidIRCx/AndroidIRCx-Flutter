import 'media_download_service_stub.dart'
    if (dart.library.io) 'media_download_service_io.dart'
    as platform;

class MediaDownloadResult {
  const MediaDownloadResult({
    required this.url,
    required this.fileName,
    required this.localPath,
    required this.bytesDownloaded,
    this.contentType,
  });

  final String url;
  final String fileName;
  final String localPath;
  final int bytesDownloaded;
  final String? contentType;
}

abstract class MediaDownloadService {
  Future<MediaDownloadResult> download(String url, {String? directoryPath});
}

MediaDownloadService createMediaDownloadService() {
  return platform.createPlatformMediaDownloadService();
}
