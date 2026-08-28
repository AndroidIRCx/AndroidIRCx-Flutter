import 'package:androidircx/features/chat/data/kick_ban_reasons_repository.dart';
import 'package:androidircx/features/settings/presentation/kick_ban_reasons_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('repository defaults and round-trips custom reasons', () async {
    final repository = KickBanReasonsRepository();
    expect(
      await repository.loadReasons(),
      KickBanReasonsRepository.defaultReasons,
    );

    await repository.saveReasons(['Trolling', ' ', 'Spam ']);
    expect(await repository.loadReasons(), ['Trolling', 'Spam']);
  });

  testWidgets('screen adds, removes, and resets reasons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: KickBanReasonsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Spam'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kick-ban-reason-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('kick-ban-reason-field')),
      'Trolling',
    );
    await tester.tap(find.byKey(const Key('kick-ban-reason-save')));
    await tester.pumpAndSettle();
    expect(find.text('Trolling'), findsOneWidget);
    expect(
      await KickBanReasonsRepository().loadReasons(),
      contains('Trolling'),
    );

    await tester.tap(find.byKey(const Key('kick-ban-reason-remove-Spam')));
    await tester.pumpAndSettle();
    expect(find.text('Spam'), findsNothing);

    await tester.tap(find.byKey(const Key('kick-ban-reasons-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Spam'), findsOneWidget);
    expect(find.text('Trolling'), findsNothing);
  });
}
