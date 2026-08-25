import 'package:permission_handler/permission_handler.dart';

enum AppPermissionResult { granted, denied, permanentlyDenied, restricted }

/// Thin wrapper over `permission_handler` so runtime-permission flows are
/// testable (the concrete implementation talks to the OS; tests inject a fake).
abstract class AppPermissions {
  Future<AppPermissionResult> requestNotifications();
  Future<bool> hasNotifications();

  /// Opens the OS app-settings page (used after a permanent denial).
  Future<void> openSettingsPage();
}

class PermissionHandlerAppPermissions implements AppPermissions {
  const PermissionHandlerAppPermissions();

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
  Future<void> openSettingsPage() async {
    await openAppSettings();
  }
}
