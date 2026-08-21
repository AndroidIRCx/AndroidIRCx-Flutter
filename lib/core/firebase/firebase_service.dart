import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Owns the Firebase integration: App Check (Play Integrity, anti-abuse and
/// always on), plus Analytics and Crashlytics whose data collection stays OFF
/// until the user consents. Uncaught Flutter/platform errors are chained into
/// Crashlytics on top of any existing handlers (e.g. the email crash reporter).
class FirebaseService {
  FirebaseService();

  /// App-wide instance used by `main`, the settings consent toggle and the
  /// onboarding step.
  static final FirebaseService instance = FirebaseService();

  bool _initialized = false;
  bool _consent = false;

  bool get isInitialized => _initialized;
  FirebaseAnalytics? get analytics =>
      _initialized ? FirebaseAnalytics.instance : null;

  /// Initializes Firebase and App Check, and routes uncaught errors into
  /// Crashlytics. Safe to call once; never throws to the caller.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      providerAndroid:
          kReleaseMode ? AndroidPlayIntegrityProvider() : AndroidDebugProvider(),
    );
    _initialized = true;

    // Collection stays off until the user consents; apply the default now.
    await _applyConsent(_consent);

    final priorFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      priorFlutterHandler?.call(details);
      // No-op unless Crashlytics collection is enabled (consent given).
      unawaited(
        FirebaseCrashlytics.instance.recordFlutterError(details, fatal: true),
      );
    };

    final priorPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
      return priorPlatformHandler?.call(error, stack) ?? false;
    };
  }

  /// Enables/disables Analytics and Crashlytics collection to match consent.
  Future<void> setConsent(bool consent) async {
    _consent = consent;
    await _applyConsent(consent);
  }

  Future<void> _applyConsent(bool consent) async {
    if (!_initialized) {
      return;
    }
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(consent);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        consent,
      );
    } catch (_) {
      // Best effort; never let telemetry toggling crash the app.
    }
  }

  /// Logs a named analytics event (no-op unless initialized + consented).
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    if (!_initialized || !_consent) {
      return;
    }
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (_) {
      // Ignore analytics failures.
    }
  }
}
