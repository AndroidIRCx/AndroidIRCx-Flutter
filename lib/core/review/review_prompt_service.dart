import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Requests a Play Store in-app review after the app has been opened enough
/// times, once. The availability/request calls are injectable for tests.
class ReviewPromptService {
  ReviewPromptService({
    Future<bool> Function()? isAvailable,
    Future<void> Function()? requestReview,
  }) : _isAvailable = isAvailable ?? (() => InAppReview.instance.isAvailable()),
       _requestReview =
           requestReview ?? (() => InAppReview.instance.requestReview());

  static const String _launchKey = 'androidircx.launchCount';
  static const String _promptedKey = 'androidircx.reviewPrompted';
  static const int threshold = 8;

  final Future<bool> Function() _isAvailable;
  final Future<void> Function() _requestReview;

  /// Increments the launch counter and, once it reaches [threshold] and no
  /// review has been requested yet, asks for a review. Never throws.
  Future<void> registerLaunchAndMaybePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_launchKey) ?? 0) + 1;
      await prefs.setInt(_launchKey, count);
      if ((prefs.getBool(_promptedKey) ?? false) || count < threshold) {
        return;
      }
      if (await _isAvailable()) {
        await _requestReview();
        await prefs.setBool(_promptedKey, true);
      }
    } catch (_) {
      // Best-effort; never block startup on a review prompt.
    }
  }
}
