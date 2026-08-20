import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/features/chat/data/message_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IrcMessage message(
    int index, {
    String tabId = 'channel::dbase::#room',
    String content = 'hello',
    String? msgid,
    IrcMessageKind kind = IrcMessageKind.chat,
    List<IrcMessageAttachment> attachments = const <IrcMessageAttachment>[],
  }) {
    return IrcMessage(
      id: 'local-$index',
      networkId: 'dbase',
      tabId: tabId,
      sender: index.isEven ? 'alice' : 'bob',
      content: content,
      timestamp: DateTime.utc(2026, 8, 20, 12, 0).add(Duration(seconds: index)),
      tags: msgid == null ? const <String, String?>{} : {'msgid': msgid},
      kind: kind,
      attachments: attachments,
    );
  }

  test('loads lazy tab pages without returning the whole history', () async {
    final repository = InMemoryMessageHistoryRepository();
    await repository.appendAll(
      networkId: 'dbase',
      messages: List<IrcMessage>.generate(
        5000,
        (index) => message(index, content: 'line $index', msgid: 'msg-$index'),
      ),
    );

    final latest = await repository.loadTabHistory(
      networkId: 'dbase',
      tabId: 'channel::dbase::#room',
      limit: 40,
    );
    final older = await repository.loadTabHistory(
      networkId: 'dbase',
      tabId: 'channel::dbase::#room',
      beforeMessageId: latest.first.tags['msgid'],
      limit: 40,
    );

    expect(latest, hasLength(40));
    expect(latest.first.content, 'line 4960');
    expect(latest.last.content, 'line 4999');
    expect(older, hasLength(40));
    expect(older.first.content, 'line 4920');
    expect(older.last.content, 'line 4959');
  });

  test(
    'searches and exports clean plain text including attachment metadata',
    () async {
      final repository = InMemoryMessageHistoryRepository();
      await repository.append(
        networkId: 'dbase',
        message: message(
          1,
          content: 'Look \u0002manual\u0002',
          kind: IrcMessageKind.media,
          attachments: const [
            IrcMessageAttachment(
              type: IrcMessageAttachmentType.file,
              label: 'File',
              uri: 'https://example.test/manual.pdf',
              fileName: 'manual.pdf',
              size: 1234,
            ),
          ],
        ),
      );

      final matches = await repository.search(
        networkId: 'dbase',
        query: 'manual',
        kinds: const <IrcMessageKind>{IrcMessageKind.media},
      );
      final export = await repository.exportTabHistory(
        networkId: 'dbase',
        tabId: 'channel::dbase::#room',
        query: 'manual',
      );

      expect(matches, hasLength(1));
      expect(export, contains('<bob> Look manual'));
      expect(export, contains('file manual.pdf'));
      expect(export, isNot(contains('\u0002')));
    },
  );

  test(
    'deduplicates msgid replays and enforces count and age retention',
    () async {
      final repository = InMemoryMessageHistoryRepository();
      await repository.append(
        networkId: 'dbase',
        message: message(1, content: 'from live', msgid: 'same-msg'),
      );
      await repository.append(
        networkId: 'dbase',
        message: message(2, content: 'from playback', msgid: 'same-msg'),
      );
      await repository.append(
        networkId: 'dbase',
        message: message(3, content: 'keep me', msgid: 'keep-1'),
      );
      await repository.append(
        networkId: 'dbase',
        message: message(4, content: 'also keep me', msgid: 'keep-2'),
      );

      var loaded = await repository.loadTabHistory(
        networkId: 'dbase',
        tabId: 'channel::dbase::#room',
        limit: 10,
      );
      expect(loaded.map((item) => item.content), [
        'from live',
        'keep me',
        'also keep me',
      ]);

      await repository.enforceRetention(
        networkId: 'dbase',
        tabId: 'channel::dbase::#room',
        maxMessages: 2,
        deleteBefore: DateTime.utc(2026, 8, 20, 12, 0, 2),
      );

      loaded = await repository.loadTabHistory(
        networkId: 'dbase',
        tabId: 'channel::dbase::#room',
        limit: 10,
      );
      expect(loaded.map((item) => item.content), ['keep me', 'also keep me']);
    },
  );
}
