import 'package:androidircx/core/review/review_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('requests a review once after the launch threshold', () async {
    SharedPreferences.setMockInitialValues({});
    var requested = 0;
    final service = ReviewPromptService(
      isAvailable: () async => true,
      requestReview: () async {
        requested++;
      },
    );

    for (var i = 0; i < ReviewPromptService.threshold - 1; i++) {
      await service.registerLaunchAndMaybePrompt();
    }
    expect(requested, 0);

    await service.registerLaunchAndMaybePrompt();
    expect(requested, 1);

    // Already prompted: no further requests.
    await service.registerLaunchAndMaybePrompt();
    expect(requested, 1);
  });

  test('does not request a review when unavailable', () async {
    SharedPreferences.setMockInitialValues({});
    var requested = 0;
    final service = ReviewPromptService(
      isAvailable: () async => false,
      requestReview: () async {
        requested++;
      },
    );
    for (var i = 0; i < ReviewPromptService.threshold + 2; i++) {
      await service.registerLaunchAndMaybePrompt();
    }
    expect(requested, 0);
  });
}
