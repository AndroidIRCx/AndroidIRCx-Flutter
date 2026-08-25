import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/platform/app_permissions.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePermissions implements AppPermissions {
  _FakePermissions(this.notifResult);
  final AppPermissionResult notifResult;
  int notifRequests = 0;

  @override
  Future<AppPermissionResult> requestNotifications() async {
    notifRequests++;
    return notifResult;
  }

  @override
  Future<bool> hasNotifications() async => false;

  @override
  Future<void> openSettingsPage() async {}
}

class _MemSettingsRepository implements SettingsRepository {
  AppSettings settings = const AppSettings();
  @override
  Future<AppSettings> loadSettings() async => settings;
  @override
  Future<void> saveSettings(AppSettings s) async => settings = s;
}

Future<void> _toNotificationsStep(WidgetTester tester) async {
  await tester.tap(find.text('Next')); // welcome
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox).first); // privacy consent (terms)
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next')); // privacy
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next')); // identity
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next')); // network
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next')); // channels -> notifications
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('granting notifications in onboarding enables the setting', (
    tester,
  ) async {
    final perms = _FakePermissions(AppPermissionResult.granted);
    final settings = _MemSettingsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          networkRepository: InMemoryNetworkRepository(const []),
          onCompleted: () async {},
          permissions: perms,
          settingsRepository: settings,
        ),
      ),
    );
    await tester.pump();
    await _toNotificationsStep(tester);

    await tester.tap(find.byKey(const Key('onboarding-allow-notifications')));
    await tester.pumpAndSettle();

    expect(perms.notifRequests, 1);
    expect(settings.settings.notificationsEnabled, isTrue);
    expect(find.text('Notifications enabled.'), findsOneWidget);
  });

  testWidgets('opting into analytics in onboarding saves consent', (
    tester,
  ) async {
    final settings = _MemSettingsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          networkRepository: InMemoryNetworkRepository(const []),
          onCompleted: () async {},
          permissions: _FakePermissions(AppPermissionResult.granted),
          settingsRepository: settings,
        ),
      ),
    );
    await tester.pump();

    // Welcome -> Privacy.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Accept terms + opt into analytics.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-analytics-consent')));
    await tester.pumpAndSettle();
    // Advance to the end and finish.
    await tester.tap(find.text('Next')); // privacy
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // identity
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // network
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // channels -> notifications
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(settings.settings.analyticsConsent, isTrue);
  });

  testWidgets('denying notifications in onboarding leaves the setting off', (
    tester,
  ) async {
    final perms = _FakePermissions(AppPermissionResult.denied);
    final settings = _MemSettingsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          networkRepository: InMemoryNetworkRepository(const []),
          onCompleted: () async {},
          permissions: perms,
          settingsRepository: settings,
        ),
      ),
    );
    await tester.pump();
    await _toNotificationsStep(tester);

    await tester.tap(find.byKey(const Key('onboarding-allow-notifications')));
    await tester.pumpAndSettle();

    expect(perms.notifRequests, 1);
    expect(settings.settings.notificationsEnabled, isFalse);
  });
}
