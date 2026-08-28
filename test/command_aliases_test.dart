import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/features/settings/presentation/command_aliases_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CommandService aliases', () {
    test('custom alias expands in normalizeCommand and persists', () async {
      final service = CommandService();
      await service.load();

      expect(await service.setAlias('gm', '/msg GameMaster'), isNull);
      expect(
        service.normalizeCommand('/gm hello there'),
        '/msg GameMaster hello there',
      );

      // A fresh service instance sees the persisted alias.
      final reloaded = CommandService();
      await reloaded.load();
      expect(reloaded.normalizeCommand('/gm hi'), '/msg GameMaster hi');
      expect(reloaded.isCustomAlias('gm'), isTrue);
    });

    test(
      'custom alias can shadow a built-in and removal restores it',
      () async {
        final service = CommandService();
        await service.load();

        expect(service.normalizeCommand('/j #a'), '/join #a');
        expect(await service.setAlias('j', '/join #androidircx'), isNull);
        expect(service.normalizeCommand('/j'), '/join #androidircx');

        await service.removeAlias('j');
        expect(service.normalizeCommand('/j #a'), '/join #a');
        expect(service.isCustomAlias('j'), isFalse);
        expect(service.isBuiltInAlias('j'), isTrue);
      },
    );

    test('rejects invalid aliases and command-name collisions', () async {
      final service = CommandService();
      await service.load();

      expect(await service.setAlias('two words', '/join'), isNotNull);
      expect(await service.setAlias('', '/join'), isNotNull);
      // 'join' is an actual command, not allowed as an alias.
      expect(await service.setAlias('join', '/part'), isNotNull);
      // Command without leading slash gets normalized instead of rejected.
      expect(await service.setAlias('gg', 'msg GG'), isNull);
      expect(service.normalizeCommand('/gg'), '/msg GG');
    });
  });

  group('CommandAliasesScreen', () {
    testWidgets('adds and removes a custom alias', (tester) async {
      final service = CommandService();
      await tester.pumpWidget(
        MaterialApp(home: CommandAliasesScreen(commandService: service)),
      );
      await tester.pumpAndSettle();

      // Built-in aliases are listed without a remove button.
      expect(find.text('/j'), findsOneWidget);
      expect(find.byKey(const Key('alias-remove-j')), findsNothing);

      await tester.tap(find.byKey(const Key('alias-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('alias-name-field')), 'gm');
      await tester.enterText(
        find.byKey(const Key('alias-command-field')),
        '/msg GameMaster',
      );
      await tester.tap(find.byKey(const Key('alias-save')));
      await tester.pumpAndSettle();

      expect(find.text('/gm'), findsOneWidget);
      expect(service.normalizeCommand('/gm hi'), '/msg GameMaster hi');

      await tester.scrollUntilVisible(
        find.byKey(const Key('alias-remove-gm')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('alias-remove-gm')));
      await tester.pumpAndSettle();
      expect(find.text('/gm'), findsNothing);
    });
  });
}
