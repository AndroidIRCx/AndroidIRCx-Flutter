import 'dart:async';

import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/diagnostics/crash_reporter.dart';
import 'package:androidircx/core/firebase/firebase_service.dart';
import 'package:androidircx/monetization/monetization_config.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  if (MonetizationConfig.mobileAdsRuntimeSupported) {
    unawaited(MobileAds.instance.initialize());
  }
  runApp(const AndroidIrcxApp());
}
