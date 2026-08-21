import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/diagnostics/crash_reporter.dart';
import 'package:androidircx/core/firebase/firebase_service.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On-device email crash reporter (always available, no analytics).
  CrashReporter().install();
  // Firebase App Check runs immediately (anti-abuse); Analytics/Crashlytics
  // collection stays off until the user consents. Optional — never blocks boot.
  try {
    await FirebaseService.instance.initialize();
  } catch (_) {
    // Continue without Firebase if initialization fails.
  }
  runApp(const AndroidIrcxApp());
}
