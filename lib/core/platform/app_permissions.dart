import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum AppPermissionResult { granted, denied, permanentlyDenied, restricted }

/// Thin wrapper over `permission_handler` so runtime-permission flows are
/// testable (the concrete implementation talks to the OS; tests inject a fake).
abstract class AppPermissions {
  Future<AppPermissionResult> requestNotifications();
  Future<bool> hasNotifications();

  /// Whether the app is already exempt from battery optimization (Doze). Reads
  /// `PowerManager.isIgnoringBatteryOptimizations`; needs no special permission.
  Future<bool> hasIgnoreBatteryOptimizations();

  /// Opens the system battery-optimization list so the user can exempt the app
  /// from Doze. Play-safe: it does not use the restricted
  /// `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission. Returns false if the
  /// screen could not be opened.
  Future<bool> openBatteryOptimizationSettings();

  /// Opens the OS app-settings page (used after a permanent denial).
  Future<void> openSettingsPage();
}

class PermissionHandlerAppPermissions implements AppPermissions {
  const PermissionHandlerAppPermissions();

  /// Reuses the foreground-service channel, whose native handler opens the
  /// battery-optimization list (see AndroidIrcxEngineManager).
  static const MethodChannel _foregroundChannel = MethodChannel(
    'androidircx/foreground_connection_service',
  );

  static AppPermissionResult _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return AppPermissionResult.granted;
    }
    if (status.isPermanentlyDenied) {
      return AppPermissionResult.permanentlyDenied;
    }
    if (status.isRestricted) {
      return AppPermissionResult.restricted;
    }
    return AppPermissionResult.denied;
  }

  @override
  Future<AppPermissionResult> requestNotifications() async =>
      _map(await Permission.notification.request());

  @override
  Future<bool> hasNotifications() async =>
      (await Permission.notification.status).isGranted;

  @override
  Future<bool> hasIgnoreBatteryOptimizations() async =>
      (await Permission.ignoreBatteryOptimizations.status).isGranted;

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    try {
      final opened = await _foregroundChannel.invokeMethod<bool>(
        'openBatteryOptimizationSettings',
      );
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openSettingsPage() async {
    await openAppSettings();
  }
}
