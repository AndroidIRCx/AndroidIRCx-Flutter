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
          certificateFileReader: (_) async => '$_cert\n$_key\n',
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

  testWidgets('shows a convert hint for non-pem (.p12) files', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkFormScreen(
          certificateFilePicker: const _FakePicker('/tmp/cert.p12'),
          certificateFileReader: (_) async => 'binary-pkcs12-bytes',
        ),
      ),
    );
    await enableCertSection(tester);

    await tester.tap(find.byKey(const Key('network-form-import-cert')));
    await tester.pumpAndSettle();

    expect(find.textContaining('openssl pkcs12'), findsOneWidget);
  });
}
