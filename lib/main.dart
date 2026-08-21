import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/diagnostics/crash_reporter.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Capture uncaught framework/platform errors into on-device crash reports.
  // Nothing is sent anywhere automatically; the user emails a report manually
  // from Settings if they choose.
  CrashReporter().install();
  runApp(const AndroidIrcxApp());
}
