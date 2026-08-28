import 'package:androidircx/core/diagnostics/crash_report.dart';
import 'package:androidircx/core/diagnostics/crash_report_sanitizer.dart';
import 'package:androidircx/core/diagnostics/crash_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sanitizer = CrashReportSanitizer();

  group('CrashReportSanitizer', () {
    test('redacts IRC auth command arguments but keeps the verb', () {
      final out = sanitizer.sanitize(
        'sent: PASS hunter2 then AUTHENTICATE bXlzZWNyZXQ=',
      );
      expect(out, contains('PASS [redacted]'));
      expect(out, contains('AUTHENTICATE [redacted]'));
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('bXlzZWNyZXQ=')));
    });

    test('does not redact a channel name after JOIN-like tokens', () {
      final out = sanitizer.sanitize('IDENTIFY #general');
      // #channel is not a secret; the negative lookahead keeps it.
      expect(out, contains('#general'));
    });

    test('redacts password/token key-value pairs', () {
      final out = sanitizer.sanitize(
        'config password: s3cr3tvalue, token=abc123def, host=irc.example.net',
      );
      expect(out, contains('password=[redacted]'));
      expect(out, contains('token=[redacted]'));
      expect(out, isNot(contains('s3cr3tvalue')));
      expect(out, isNot(contains('abc123def')));
      // Non-secret values survive.
      expect(out, contains('irc.example.net'));
    });

    test('redacts PEM blocks and long opaque tokens', () {
      final pem =
          '-----BEGIN PRIVATE KEY-----\nAAAABBBBCCCC\n-----END PRIVATE KEY-----';
      final out = sanitizer.sanitize('key $pem end');
      expect(out, isNot(contains('BEGIN PRIVATE KEY')));
      expect(out, contains('[redacted]'));

      final longToken = 'Zm9vYmFyMTIzNDU2Nzg5MGFiY2RlZmdoaWprbG1ub3BxcnN0dXY=';
      final out2 = sanitizer.sanitize('bearer $longToken');
      expect(out2, isNot(contains(longToken)));
    });

    test('leaves ordinary text untouched', () {
      const msg = 'RangeError: index 5 out of range for list of length 3';
      expect(sanitizer.sanitize(msg), msg);
    });
  });

  group('CrashReport', () {
    test('round-trips through json', () {
      final report = CrashReport(
        timestamp: DateTime.utc(2026, 8, 21, 9, 30),
        fatal: true,
        source: 'zone',
        message: 'boom',
        stack: '#0 main',
        platform: 'android',
      );
      final decoded = CrashReport.decode(report.encode());
      expect(decoded, isNotNull);
      expect(decoded!.message, 'boom');
      expect(decoded.source, 'zone');
      expect(decoded.fatal, isTrue);
      expect(decoded.platform, 'android');
      expect(decoded.timestamp, report.timestamp);
    });

    test('plaintext body includes the key fields', () {
      final report = CrashReport(
        timestamp: DateTime.utc(2026, 8, 21),
        fatal: false,
        source: 'manual',
        message: 'something failed',
        stack: '#0 somewhere',
      );
      final text = report.toPlainText();
      expect(text, contains('Fatal: false'));
      expect(text, contains('Source: manual'));
      expect(text, contains('something failed'));
      expect(text, contains('#0 somewhere'));
    });

    test('decode returns null on malformed input', () {
      expect(CrashReport.decode('not json'), isNull);
      expect(CrashReport.decode('[]'), isNull);
    });
  });

  group('CrashReporter', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    CrashReporter build() => CrashReporter(
      prefsLoader: SharedPreferences.getInstance,
      platformName: 'android',
      clock: () => DateTime.utc(2026, 8, 21, 10),
    );

    test('records a sanitized report and reloads it', () async {
      final reporter = build();
      await reporter.record(
        Exception('login failed PASS topsecret'),
        StackTrace.fromString('#0 auth'),
        source: 'test',
      );
      final reports = await reporter.loadReports();
      expect(reports, hasLength(1));
      expect(reports.first.source, 'test');
      expect(reports.first.message, contains('PASS [redacted]'));
      expect(reports.first.message, isNot(contains('topsecret')));
      expect(reports.first.platform, 'android');
    });

    test('keeps newest first and caps at maxStored', () async {
      final reporter = CrashReporter(
        prefsLoader: SharedPreferences.getInstance,
        platformName: 'android',
        clock: () => DateTime.utc(2026, 8, 21, 10),
        maxStored: 3,
      );
      for (var i = 0; i < 5; i++) {
        await reporter.record(Exception('error $i'), null, source: 's$i');
      }
      final reports = await reporter.loadReports();
      expect(reports, hasLength(3));
      // Newest (error 4) first.
      expect(reports.first.message, contains('error 4'));
      expect(reports.last.message, contains('error 2'));
    });

    test('clear removes all reports', () async {
      final reporter = build();
      await reporter.record(Exception('x'), null);
      expect(await reporter.loadReports(), isNotEmpty);
      await reporter.clear();
      expect(await reporter.loadReports(), isEmpty);
    });

    test(
      'builds a mailto uri addressed to the contact with subject/body',
      () async {
        final reporter = build();
        final report = await reporter.record(
          Exception('kaboom'),
          null,
          source: 'test',
        );
        final uri = reporter.buildMailtoUri(report!);
        expect(uri.scheme, 'mailto');
        expect(uri.path, 'contact@androidircx.com');
        expect(uri.query, contains('subject=AndroidIRCX%20Crash%20Report'));
        expect(
          Uri.decodeComponent(uri.queryParameters['body']!),
          contains('kaboom'),
        );
      },
    );
  });
}
