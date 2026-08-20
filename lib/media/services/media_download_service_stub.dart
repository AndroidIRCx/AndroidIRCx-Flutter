import 'media_download_service.dart';

MediaDownloadService createPlatformMediaDownloadService() {
  return const _UnsupportedMediaDownloadService();
}

class _UnsupportedMediaDownloadService implements MediaDownloadService {
  const _UnsupportedMediaDownloadService();

  @override
  Future<MediaDownloadResult> download(String url, {String? directoryPath}) {
    throw UnsupportedError(
      'Media downloads are only supported on IO platforms.',
    );
  }
}
