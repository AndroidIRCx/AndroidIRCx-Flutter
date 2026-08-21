import 'package:androidircx/core/diagnostics/crash_reporter.dart';
import 'package:androidircx/features/settings/presentation/crash_reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  CrashReporter reporter() => CrashReporter(
    prefsLoader: SharedPreferences.getInstance,
    platformName: 'android',
    clock: () => DateTime.utc(2026, 8, 21, 10),
  );

  testWidgets('shows empty state when there are no reports', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CrashReportsScreen(reporter: reporter())),
    );
    await tester.pumpAndSettle();
    expect(find.text('No crash reports'), findsOneWidget);
  });

  testWidgets('lists a report and emails it via the launcher', (tester) async {
    final r = reporter();
    await r.record(
      Exception('boom PASS secret'),
      StackTrace.fromString('#0 main'),
      source: 'test',
    );

    Uri? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: CrashReportsScreen(
          reporter: r,
          launcher: (uri) async {
            launched = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The sanitized message is shown, secret redacted.
    expect(find.textContaining('PASS [redacted]'), findsWidgets);
    expect(find.textContaining('secret'), findsNothing);

    // Expand and tap "Email report".
    await tester.tap(find.textContaining('boom').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Email report'));
    await tester.pumpAndSettle();

    expect(launched, isNotNull);
    expect(launched!.scheme, 'mailto');
    expect(launched!.path, 'contact@androidircx.com');
  });

  testWidgets('clear removes reports', (tester) async {
    final r = reporter();
    await r.record(Exception('x'), null, source: 'test');

    await tester.pumpWidget(
      MaterialApp(home: CrashReportsScreen(reporter: r)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('crash-reports-clear')));
    await tester.pumpAndSettle();

    expect(find.text('No crash reports'), findsOneWidget);
  });
}
