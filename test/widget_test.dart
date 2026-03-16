import 'package:androidircx/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows seeded network on bootstrap', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AndroidIrcxApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('AndroidIRCX'), findsOneWidget);
    expect(find.text('DBase'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
