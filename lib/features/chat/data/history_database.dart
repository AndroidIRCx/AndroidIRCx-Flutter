import 'dart:convert';

import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/features/chat/application/message_history_formatter.dart';
import 'package:androidircx/features/chat/data/message_history_repository.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:drift/drift.dart';

part 'history_database.g.dart';

/// One IRC message row.
///
/// The message body ([payload]) is an application-encrypted JSON blob, so it is
/// unreadable at rest without the biometric/PIN-gated key. Only non-content
/// metadata (network/tab/kind/timestamp/msgid) is stored in the clear so the
/// database can index, paginate, dedupe, and enforce retention efficiently.
class Messages extends Table {
  IntColumn get rowId => integer().autoIncrement()();
  TextColumn get networkId => text()();
  TextColumn get tabId => text()();
  TextColumn get msgid => text().nullable()();
  TextColumn get kind => text()();
  IntColumn get timestampMs => integer()();
  TextColumn get payload => text()();
}

@DriftDatabase(tables: [Messages])
class HistoryDatabase extends _$HistoryDatabase {
  HistoryDatabase(super.e);

  @override
  int get schemaVersion => 1;
}

/// Encrypts/decrypts the message payload blob. The production codec is AES-GCM
/// keyed by `HistoryEncryptionKeyManager`; tests can use a plaintext codec.
abstract class HistoryPayloadCodec {
  Future<String> encrypt(String plaintext);
  Future<String> decrypt(String ciphertext);
}

/// No-op codec for tests / non-sensitive contexts.
class PlaintextHistoryPayloadCodec implements HistoryPayloadCodec {
  const PlaintextHistoryPayloadCodec();

  @override
  Future<String> encrypt(String plaintext) async => plaintext;

  @override
  Future<String> decrypt(String ciphertext) async => ciphertext;
}

/// A migration-safe, encrypted [MessageHistoryRepository] over Drift/SQLite.
///
/// Message bodies are encrypted with [_codec] before being written, so copying
/// the database file off the device does not reveal chat history without the
/// user's key.
class DriftMessageHistoryRepository implements MessageHistoryRepository {
  DriftMessageHistoryRepository(
    this._db, {
    HistoryPayloadCodec codec = const PlaintextHistoryPayloadCodec(),
  }) : _codec = codec;

  final HistoryDatabase _db;
  final HistoryPayloadCodec _codec;

  Future<void> close() => _db.close();

  @override
  Future<void> append({
    required String networkId,
    required IrcMessage message,
  }) async {
    final stored = message.networkId == networkId
        ? message
        : message.copyWith(networkId: networkId);
    final dedupeId = _dedupeId(stored);
    if (dedupeId != null) {
      final existing = await (_db.select(_db.messages)
            ..where((row) =>
                row.networkId.equals(networkId) &
                row.tabId.equals(stored.tabId) &
                row.msgid.equals(dedupeId))
            ..limit(1))
          .get();
      if (existing.isNotEmpty) {
        return;
      }
    }

    final payload = await _codec.encrypt(jsonEncode(stored.toJson()));
    await _db.into(_db.messages).insert(
          MessagesCompanion.insert(
            networkId: networkId,
            tabId: stored.tabId,
            msgid: dedupeId == null ? const Value.absent() : Value(dedupeId),
            kind: stored.kind.name,
            timestampMs: stored.timestamp.millisecondsSinceEpoch,
            payload: payload,
          ),
        );
  }

  @override
  Future<void> appendAll({
    required String networkId,
    required Iterable<IrcMessage> messages,
  }) async {
    for (final message in messages) {
      await append(networkId: networkId, message: message);
    }
  }

  @override
  Future<List<IrcMessage>> loadTabHistory({
    required String networkId,
    required String tabId,
    int limit = 50,
    String? beforeMessageId,
  }) async {
    final normalizedLimit = limit.clamp(1, 1000);
    final anchor = (beforeMessageId ?? '').trim();
    int? beforeRowId;
    if (anchor.isNotEmpty) {
      final rows = await (_db.select(_db.messages)
            ..where((row) =>
                row.networkId.equals(networkId) & row.tabId.equals(tabId)))
          .get();
      for (final row in rows) {
        final message = await _fromRow(row);
        if (message.id == anchor || message.tags['msgid'] == anchor) {
          beforeRowId = row.rowId;
          break;
        }
      }
    }

    final query = _db.select(_db.messages)
      ..where((row) {
        final base =
            row.networkId.equals(networkId) & row.tabId.equals(tabId);
        return beforeRowId == null
            ? base
            : base & row.rowId.isSmallerThanValue(beforeRowId);
      })
      ..orderBy([(row) => OrderingTerm.desc(row.rowId)])
      ..limit(normalizedLimit);

    final rows = (await query.get()).reversed.toList(growable: false);
    final messages = <IrcMessage>[];
    for (final row in rows) {
      messages.add(await _fromRow(row));
    }
    return List<IrcMessage>.unmodifiable(messages);
  }

  @override
  Future<List<IrcMessage>> search({
    required String networkId,
    String? tabId,
    String query = '',
    Set<IrcMessageKind> kinds = const <IrcMessageKind>{},
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final normalizedLimit = limit.clamp(1, 10000);
    final normalizedQuery =
        formatIrcPlainText(query, collapseWhitespace: true).toLowerCase();

    final select = _db.select(_db.messages)
      ..where((row) {
        var condition = row.networkId.equals(networkId);
        if (tabId != null) {
          condition = condition & row.tabId.equals(tabId);
        }
        if (kinds.isNotEmpty) {
          condition =
              condition & row.kind.isIn(kinds.map((kind) => kind.name));
        }
        if (from != null) {
          condition = condition &
              row.timestampMs
                  .isBiggerOrEqualValue(from.millisecondsSinceEpoch);
        }
        if (to != null) {
          condition = condition &
              row.timestampMs.isSmallerOrEqualValue(to.millisecondsSinceEpoch);
        }
        return condition;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.timestampMs)]);

    final rows = await select.get();
    final matches = <IrcMessage>[];
    for (final row in rows) {
      final message = await _fromRow(row);
      if (normalizedQuery.isNotEmpty &&
          !_searchText(message).contains(normalizedQuery)) {
        continue;
      }
      matches.add(message);
      if (matches.length >= normalizedLimit) {
        break;
      }
    }
    return List<IrcMessage>.unmodifiable(matches);
  }

  @override
  Future<String> exportTabHistory({
    required String networkId,
    required String tabId,
    String query = '',
    Set<IrcMessageKind> kinds = const <IrcMessageKind>{},
    DateTime? from,
    DateTime? to,
    int limit = 10000,
  }) async {
    final messages = await search(
      networkId: networkId,
      tabId: tabId,
      query: query,
      kinds: kinds,
      from: from,
      to: to,
      limit: limit,
    );
    return messages.map(formatIrcMessagePlainText).join('\n');
  }

  @override
  Future<void> enforceRetention({
    required String networkId,
    String? tabId,
    int? maxMessages,
    DateTime? deleteBefore,
  }) async {
    if (deleteBefore != null) {
      await (_db.delete(_db.messages)
            ..where((row) {
              var condition = row.networkId.equals(networkId) &
                  row.timestampMs.isSmallerThanValue(
                    deleteBefore.millisecondsSinceEpoch,
                  );
              if (tabId != null) {
                condition = condition & row.tabId.equals(tabId);
              }
              return condition;
            }))
          .go();
    }

    if (maxMessages != null && maxMessages > 0) {
      final tabIds = <String>[];
      if (tabId != null) {
        tabIds.add(tabId);
      } else {
        final rows = await (_db.selectOnly(_db.messages, distinct: true)
              ..addColumns([_db.messages.tabId])
              ..where(_db.messages.networkId.equals(networkId)))
            .get();
        for (final row in rows) {
          tabIds.add(row.read(_db.messages.tabId)!);
        }
      }

      for (final id in tabIds) {
        final rowIds = await (_db.select(_db.messages)
              ..where((row) =>
                  row.networkId.equals(networkId) & row.tabId.equals(id))
              ..orderBy([(row) => OrderingTerm.asc(row.rowId)]))
            .map((row) => row.rowId)
            .get();
        if (rowIds.length <= maxMessages) {
          continue;
        }
        final removable = rowIds.sublist(0, rowIds.length - maxMessages);
        await (_db.delete(_db.messages)
              ..where((row) => row.rowId.isIn(removable)))
            .go();
      }
    }
  }

  @override
  Future<void> deleteTabHistory({
    required String networkId,
    required String tabId,
  }) async {
    await (_db.delete(_db.messages)
          ..where((row) =>
              row.networkId.equals(networkId) & row.tabId.equals(tabId)))
        .go();
  }

  @override
  Future<void> deleteNetworkHistory(String networkId) async {
    await (_db.delete(_db.messages)
          ..where((row) => row.networkId.equals(networkId)))
        .go();
  }

  Future<IrcMessage> _fromRow(Message row) async {
    final decrypted = await _codec.decrypt(row.payload);
    return IrcMessage.fromJson(
      Map<String, Object?>.from(jsonDecode(decrypted) as Map),
    );
  }

  static String? _dedupeId(IrcMessage message) {
    final msgid = (message.tags['msgid'] ?? '').trim();
    return msgid.isEmpty ? null : msgid;
  }

  static String _searchText(IrcMessage message) {
    return [
      message.sender,
      formatIrcPlainText(message.content),
      for (final attachment in message.attachments) ...[
        attachment.label,
        attachment.uri,
        attachment.mediaId,
        attachment.transferId,
        attachment.peerNick,
        attachment.fileName,
        attachment.direction,
        attachment.status,
      ],
    ].whereType<String>().join(' ').toLowerCase();
  }
}
