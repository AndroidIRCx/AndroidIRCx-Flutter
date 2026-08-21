import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSettings(
    WidgetTester tester, {
    required Future<bool> Function() auth,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(appLockAuthenticator: auth)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-app-lock')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('enabling app lock requires successful authentication', (
    tester,
  ) async {
    await pumpSettings(tester, auth: () async => false);

    await tester.tap(find.byKey(const Key('settings-app-lock')));
    await tester.pumpAndSettle();

    final settings = await SharedPrefsSettingsRepository().loadSettings();
    expect(settings.appLockEnabled, isFalse);
    expect(
      find.textContaining('could not verify fingerprint or PIN'),
      findsOneWidget,
    );
  });

  testWidgets('app lock is enabled once authentication succeeds', (
    tester,
  ) async {
    await pumpSettings(tester, auth: () async => true);

    await tester.tap(find.byKey(const Key('settings-app-lock')));
    await tester.pumpAndSettle();

    final settings = await SharedPrefsSettingsRepository().loadSettings();
    expect(settings.appLockEnabled, isTrue);
  });
}
