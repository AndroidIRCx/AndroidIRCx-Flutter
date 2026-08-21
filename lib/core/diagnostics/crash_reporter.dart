import 'dart:async';

import 'package:androidircx/core/diagnostics/crash_report.dart';
import 'package:androidircx/core/diagnostics/crash_report_sanitizer.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures uncaught errors, sanitizes them, and keeps the most recent few on
/// device so the user can review and — only if they choose — email a plaintext
/// report. No automatic/network reporting and no analytics SDK: the report is
/// sent solely through the user's own mail client via a `mailto:` link.
class CrashReporter {
  CrashReporter({
    CrashReportSanitizer sanitizer = const CrashReportSanitizer(),
    Future<SharedPreferences> Function()? prefsLoader,
    String? platformName,
    DateTime Function()? clock,
    this.contactEmail = defaultContactEmail,
    this.maxStored = 5,
  }) : _sanitizer = sanitizer,
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _platformName = platformName ?? _defaultPlatformName(),
       _clock = clock ?? DateTime.now;

  static const String defaultContactEmail = 'contact@androidircx.com';
  static const String emailSubject = 'AndroidIRCX Crash Report';
  static const String _storageKey = 'androidircx.crashReports';

  final CrashReportSanitizer _sanitizer;
  final Future<SharedPreferences> Function() _prefsLoader;
  final String? _platformName;
  final DateTime Function() _clock;

  /// Address the crash email is pre-addressed to.
  final String contactEmail;

  /// Maximum number of reports retained on device.
  final int maxStored;

  static String? _defaultPlatformName() {
    // Avoid dart:io so this stays testable; use the platform embedder name.
    final name = defaultTargetPlatform.name;
    return name.isEmpty ? null : name;
  }

  /// Records an error, persisting a sanitized [CrashReport]. Never throws.
  Future<CrashReport?> record(
    Object error,
    StackTrace? stack, {
    bool fatal = true,
    String source = 'unknown',
  }) async {
    try {
      final report = CrashReport(
        timestamp: _clock().toUtc(),
        fatal: fatal,
        source: source,
        message: _sanitizer.sanitize(error.toString()),
        stack: _sanitizer.sanitize(stack?.toString() ?? ''),
        platform: _platformName,
      );
      final prefs = await _prefsLoader();
      final existing = prefs.getStringList(_storageKey) ?? <String>[];
      final updated = <String>[report.encode(), ...existing];
      if (updated.length > maxStored) {
        updated.removeRange(maxStored, updated.length);
      }
      await prefs.setStringList(_storageKey, updated);
      return report;
    } catch (_) {
      // Diagnostics must never worsen a crash.
      return null;
    }
  }

  /// Loads the retained reports, newest first.
  Future<List<CrashReport>> loadReports() async {
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getStringList(_storageKey) ?? <String>[];
      return raw
          .map(CrashReport.decode)
          .whereType<CrashReport>()
          .toList(growable: false);
    } catch (_) {
      return const <CrashReport>[];
    }
  }

  /// Clears all retained reports.
  Future<void> clear() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_storageKey);
    } catch (_) {
      // Best effort.
    }
  }

  /// Builds a `mailto:` URI pre-addressed to [contactEmail] with the report as
  /// the plaintext body. Spaces are percent-encoded (not `+`) for broad mail
  /// client compatibility.
  Uri buildMailtoUri(CrashReport report) {
    final subject = Uri.encodeComponent(emailSubject);
    final body = Uri.encodeComponent(report.toPlainText());
    return Uri.parse('mailto:$contactEmail?subject=$subject&body=$body');
  }

  /// Installs global handlers so uncaught framework and platform errors are
  /// recorded. Existing handlers are preserved and still invoked.
  void install() {
    final priorFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(
        record(
          details.exception,
          details.stack,
          source: 'FlutterError.onError',
        ),
      );
      if (priorFlutterHandler != null) {
        priorFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final priorPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record(error, stack, source: 'PlatformDispatcher'));
      return priorPlatformHandler?.call(error, stack) ?? false;
    };
  }
}
