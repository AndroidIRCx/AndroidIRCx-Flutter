import 'package:androidircx/features/chat/data/channel_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ChannelNotesRepository repo() =>
      ChannelNotesRepository(prefsLoader: SharedPreferences.getInstance);

  test('returns empty string when no note exists', () async {
    expect(await repo().getNote('dbase', '#flutter'), '');
  });

  test('saves and reloads a note per network+channel', () async {
    final r = repo();
    await r.setNote('dbase', '#flutter', '  ops: alice, bob  ');
    expect(await r.getNote('dbase', '#flutter'), 'ops: alice, bob');
    // Different channel / network is independent.
    expect(await r.getNote('dbase', '#dart'), '');
    expect(await r.getNote('other', '#flutter'), '');
  });

  test('empty note removes the entry', () async {
    final r = repo();
    await r.setNote('dbase', '#flutter', 'keep me');
    await r.setNote('dbase', '#flutter', '   ');
    expect(await r.getNote('dbase', '#flutter'), '');
    expect(await r.allNotes(), isEmpty);
  });

  test('allNotes returns every stored note', () async {
    final r = repo();
    await r.setNote('dbase', '#a', 'note a');
    await r.setNote('dbase', '#b', 'note b');
    final all = await r.allNotes();
    expect(all['dbase::#a'], 'note a');
    expect(all['dbase::#b'], 'note b');
  });

  test('survives a corrupt blob', () async {
    SharedPreferences.setMockInitialValues({
      ChannelNotesRepository.storageKey: 'not json',
    });
    final r = repo();
    expect(await r.getNote('dbase', '#x'), '');
    await r.setNote('dbase', '#x', 'fresh');
    expect(await r.getNote('dbase', '#x'), 'fresh');
  });
}
