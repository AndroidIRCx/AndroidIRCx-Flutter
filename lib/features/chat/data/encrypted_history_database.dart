import 'dart:io';

import 'package:androidircx/core/security/history_encryption_key_manager.dart';
import 'package:androidircx/features/chat/data/history_database.dart';
import 'package:androidircx/features/chat/data/history_payload_cipher.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opens the on-device history database (native sqlite via `sqlite3_flutter_libs`).
///
/// Message bodies are encrypted at the application layer via
/// [AesGcmHistoryPayloadCodec]; the sqlite file itself only holds ciphertext for
/// content plus non-sensitive metadata columns.
Future<HistoryDatabase> openHistoryDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final file = File(p.join(directory.path, 'history.db'));
  return HistoryDatabase(NativeDatabase.createInBackground(file));
}

/// Convenience: unlock the encryption key (prompting biometric/PIN), open the
/// database, and return a repository whose payloads are AES-256-GCM encrypted.
///
/// Returns null if the user does not authenticate, leaving history locked.
Future<DriftMessageHistoryRepository?> openEncryptedHistory(
  HistoryEncryptionKeyManager keyManager, {
  String reason = 'Unlock your chat history',
}) async {
  final key = await keyManager.unlockKey(reason: reason);
  if (key == null) {
    return null;
  }
  final database = await openHistoryDatabase();
  return DriftMessageHistoryRepository(
    database,
    codec: AesGcmHistoryPayloadCodec.fromBase64Key(key),
  );
}
