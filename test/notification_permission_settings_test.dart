import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/platform/app_permissions.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePermissions implements AppPermissions {
  _FakePermissions({
    this.notifResult = AppPermissionResult.granted,
    this.hasNotif = false,
  });

  AppPermissionResult notifResult;
  bool hasNotif;
  int notifRequests = 0;

  @override
  Future<bool> hasNotifications() async => hasNotif;

  @override
  Future<AppPermissionResult> requestNotifications() async {
    notifRequests++;
    if (notifResult == AppPermissionResult.granted) hasNotif = true;
    return notifResult;
  }

  bool hasBattery = false;
  int batteryRequests = 0;

  @override
  Future<bool> hasIgnoreBatteryOptimizations() async => hasBattery;

  @override
  Future<AppPermissionResult> requestIgnoreBatteryOptimizations() async {
    batteryRequests++;
    hasBattery = true;
    return AppPermissionResult.granted;
  }

  @override
  Future<void> openSettingsPage() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, _FakePermissions perms) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(permissions: perms)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-notifications-enabled')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('settings-notifications-enabled')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'enabling notifications requests permission and enables on grant',
    (tester) async {
      final perms = _FakePermissions(notifResult: AppPermissionResult.granted);
      await pump(tester, perms);

      await tester.tap(find.byKey(const Key('settings-notifications-enabled')));
      await tester.pumpAndSettle();

      expect(perms.notifRequests, 1);
      final saved = await SharedPrefsSettingsRepository().loadSettings();
      expect(saved.notificationsEnabled, isTrue);
    },
  );

  testWidgets('denied permission keeps notifications off', (tester) async {
    final perms = _FakePermissions(notifResult: AppPermissionResult.denied);
    await pump(tester, perms);

    await tester.tap(find.byKey(const Key('settings-notifications-enabled')));
    await tester.pumpAndSettle();

    expect(perms.notifRequests, 1);
    final saved = await SharedPrefsSettingsRepository().loadSettings();
    expect(saved.notificationsEnabled, isFalse);
    expect(
      find.textContaining('Notification permission denied'),
      findsOneWidget,
    );
  });

  testWidgets('reconciles notifications off when OS permission is missing', (
    tester,
  ) async {
    // Stored as enabled, but the OS permission is not granted.
    await SharedPrefsSettingsRepository().saveSettings(
      const AppSettings(notificationsEnabled: true),
    );
    final perms = _FakePermissions(hasNotif: false);

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(permissions: perms)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final saved = await SharedPrefsSettingsRepository().loadSettings();
    expect(saved.notificationsEnabled, isFalse);
  });

  testWidgets('analytics consent toggle saves the setting', (tester) async {
    final perms = _FakePermissions();
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(permissions: perms)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-analytics-consent')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('settings-analytics-consent')),
    );
    await tester.pumpAndSettle();

    var saved = await SharedPrefsSettingsRepository().loadSettings();
    expect(saved.analyticsConsent, isFalse);

    await tester.tap(find.byKey(const Key('settings-analytics-consent')));
    await tester.pumpAndSettle();

    saved = await SharedPrefsSettingsRepository().loadSettings();
    expect(saved.analyticsConsent, isTrue);
  });
}
