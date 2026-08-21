import 'package:androidircx/features/chat/data/user_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  UserNotesRepository repo() =>
      UserNotesRepository(prefsLoader: SharedPreferences.getInstance);

  test('returns empty when no note exists', () async {
    expect(await repo().getNote('dbase', 'alice'), '');
  });

  test('saves, trims, and reloads a note (case-insensitive nick)', () async {
    final r = repo();
    await r.setNote('dbase', 'Alice', '  knows the ops  ');
    expect(await r.getNote('dbase', 'alice'), 'knows the ops');
    expect(await r.getNote('dbase', 'ALICE'), 'knows the ops');
    expect(await r.getNote('other', 'alice'), '');
  });

  test('empty note removes the entry', () async {
    final r = repo();
    await r.setNote('dbase', 'bob', 'temp');
    await r.setNote('dbase', 'bob', '');
    expect(await r.getNote('dbase', 'bob'), '');
    expect(await r.allNotes(), isEmpty);
  });

  test('survives a corrupt blob', () async {
    SharedPreferences.setMockInitialValues({
      UserNotesRepository.storageKey: '{{bad',
    });
    final r = repo();
    expect(await r.getNote('dbase', 'x'), '');
    await r.setNote('dbase', 'x', 'ok');
    expect(await r.getNote('dbase', 'x'), 'ok');
  });
}
