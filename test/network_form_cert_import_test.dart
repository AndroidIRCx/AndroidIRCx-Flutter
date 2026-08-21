import 'dart:convert';

import 'package:androidircx/dcc/services/dcc_file_picker.dart';
import 'package:androidircx/features/connections/presentation/network_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePicker implements DccFilePicker {
  const _FakePicker(this.path);
  final String? path;
  @override
  Future<String?> pickFile() async => path;
}

const _cert =
    '-----BEGIN CERTIFICATE-----\nMIIByyCERT\n-----END CERTIFICATE-----';
const _key =
    '-----BEGIN PRIVATE KEY-----\nMIIEvKEY\n-----END PRIVATE KEY-----';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> enableCertSection(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Client certificate (SASL EXTERNAL)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Client certificate (SASL EXTERNAL)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('network-form-import-cert')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('imports certificate and key from a combined pem file', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkFormScreen(
          certificateFilePicker: const _FakePicker('/tmp/cert.pem'),
          certificateFileReader: (_) async => utf8.encode('$_cert\n$_key\n'),
        ),
      ),
    );
    await enableCertSection(tester);

    await tester.tap(find.byKey(const Key('network-form-import-cert')));
    await tester.pumpAndSettle();

    expect(
      find.text('Imported certificate and private key from file.'),
      findsOneWidget,
    );
    expect(find.textContaining('MIIByyCERT'), findsWidgets);
    expect(find.textContaining('MIIEvKEY'), findsWidgets);
  });

  testWidgets('loads a binary .p12 bundle', (tester) async {
    // Bytes that are not valid UTF-8 and contain no PEM blocks -> treated as a
    // PKCS#12 bundle.
    final p12Bytes = <int>[0x30, 0x82, 0x04, 0xff, 0xfe, 0x00, 0x01];
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkFormScreen(
          certificateFilePicker: const _FakePicker('/tmp/cert.p12'),
          certificateFileReader: (_) async => p12Bytes,
        ),
      ),
    );
    await enableCertSection(tester);

    await tester.tap(find.byKey(const Key('network-form-import-cert')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('network-form-pkcs12-loaded')),
      findsOneWidget,
    );
    expect(find.text('PKCS#12 bundle loaded'), findsOneWidget);
  });
}
