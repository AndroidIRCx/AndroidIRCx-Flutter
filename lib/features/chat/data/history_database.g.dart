// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_database.dart';

// ignore_for_file: type=lint
class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<int> rowId = GeneratedColumn<int>(
    'row_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _networkIdMeta = const VerificationMeta(
    'networkId',
  );
  @override
  late final GeneratedColumn<String> networkId = GeneratedColumn<String>(
    'network_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tabIdMeta = const VerificationMeta('tabId');
  @override
  late final GeneratedColumn<String> tabId = GeneratedColumn<String>(
    'tab_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _msgidMeta = const VerificationMeta('msgid');
  @override
  late final GeneratedColumn<String> msgid = GeneratedColumn<String>(
    'msgid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    rowId,
    networkId,
    tabId,
    msgid,
    kind,
    timestampMs,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    }
    if (data.containsKey('network_id')) {
      context.handle(
        _networkIdMeta,
        networkId.isAcceptableOrUnknown(data['network_id']!, _networkIdMeta),
      );
    } else if (isInserting) {
      context.missing(_networkIdMeta);
    }
    if (data.containsKey('tab_id')) {
      context.handle(
        _tabIdMeta,
        tabId.isAcceptableOrUnknown(data['tab_id']!, _tabIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tabIdMeta);
    }
    if (data.containsKey('msgid')) {
      context.handle(
        _msgidMeta,
        msgid.isAcceptableOrUnknown(data['msgid']!, _msgidMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampMsMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowId};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_id'],
      )!,
      networkId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network_id'],
      )!,
      tabId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tab_id'],
      )!,
      msgid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}msgid'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final int rowId;
  final String networkId;
  final String tabId;
  final String? msgid;
  final String kind;
  final int timestampMs;
  final String payload;
  const Message({
    required this.rowId,
    required this.networkId,
    required this.tabId,
    this.msgid,
    required this.kind,
    required this.timestampMs,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_id'] = Variable<int>(rowId);
    map['network_id'] = Variable<String>(networkId);
    map['tab_id'] = Variable<String>(tabId);
    if (!nullToAbsent || msgid != null) {
      map['msgid'] = Variable<String>(msgid);
    }
    map['kind'] = Variable<String>(kind);
    map['timestamp_ms'] = Variable<int>(timestampMs);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      rowId: Value(rowId),
      networkId: Value(networkId),
      tabId: Value(tabId),
      msgid: msgid == null && nullToAbsent
          ? const Value.absent()
          : Value(msgid),
      kind: Value(kind),
      timestampMs: Value(timestampMs),
      payload: Value(payload),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      rowId: serializer.fromJson<int>(json['rowId']),
      networkId: serializer.fromJson<String>(json['networkId']),
      tabId: serializer.fromJson<String>(json['tabId']),
      msgid: serializer.fromJson<String?>(json['msgid']),
      kind: serializer.fromJson<String>(json['kind']),
      timestampMs: serializer.fromJson<int>(json['timestampMs']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowId': serializer.toJson<int>(rowId),
      'networkId': serializer.toJson<String>(networkId),
      'tabId': serializer.toJson<String>(tabId),
      'msgid': serializer.toJson<String?>(msgid),
      'kind': serializer.toJson<String>(kind),
      'timestampMs': serializer.toJson<int>(timestampMs),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Message copyWith({
    int? rowId,
    String? networkId,
    String? tabId,
    Value<String?> msgid = const Value.absent(),
    String? kind,
    int? timestampMs,
    String? payload,
  }) => Message(
    rowId: rowId ?? this.rowId,
    networkId: networkId ?? this.networkId,
    tabId: tabId ?? this.tabId,
    msgid: msgid.present ? msgid.value : this.msgid,
    kind: kind ?? this.kind,
    timestampMs: timestampMs ?? this.timestampMs,
    payload: payload ?? this.payload,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      networkId: data.networkId.present ? data.networkId.value : this.networkId,
      tabId: data.tabId.present ? data.tabId.value : this.tabId,
      msgid: data.msgid.present ? data.msgid.value : this.msgid,
      kind: data.kind.present ? data.kind.value : this.kind,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('rowId: $rowId, ')
          ..write('networkId: $networkId, ')
          ..write('tabId: $tabId, ')
          ..write('msgid: $msgid, ')
          ..write('kind: $kind, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(rowId, networkId, tabId, msgid, kind, timestampMs, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.rowId == this.rowId &&
          other.networkId == this.networkId &&
          other.tabId == this.tabId &&
          other.msgid == this.msgid &&
          other.kind == this.kind &&
          other.timestampMs == this.timestampMs &&
          other.payload == this.payload);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> rowId;
  final Value<String> networkId;
  final Value<String> tabId;
  final Value<String?> msgid;
  final Value<String> kind;
  final Value<int> timestampMs;
  final Value<String> payload;
  const MessagesCompanion({
    this.rowId = const Value.absent(),
    this.networkId = const Value.absent(),
    this.tabId = const Value.absent(),
    this.msgid = const Value.absent(),
    this.kind = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.payload = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.rowId = const Value.absent(),
    required String networkId,
    required String tabId,
    this.msgid = const Value.absent(),
    required String kind,
    required int timestampMs,
    required String payload,
  }) : networkId = Value(networkId),
       tabId = Value(tabId),
       kind = Value(kind),
       timestampMs = Value(timestampMs),
       payload = Value(payload);
  static Insertable<Message> custom({
    Expression<int>? rowId,
    Expression<String>? networkId,
    Expression<String>? tabId,
    Expression<String>? msgid,
    Expression<String>? kind,
    Expression<int>? timestampMs,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (rowId != null) 'row_id': rowId,
      if (networkId != null) 'network_id': networkId,
      if (tabId != null) 'tab_id': tabId,
      if (msgid != null) 'msgid': msgid,
      if (kind != null) 'kind': kind,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (payload != null) 'payload': payload,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? rowId,
    Value<String>? networkId,
    Value<String>? tabId,
    Value<String?>? msgid,
    Value<String>? kind,
    Value<int>? timestampMs,
    Value<String>? payload,
  }) {
    return MessagesCompanion(
      rowId: rowId ?? this.rowId,
      networkId: networkId ?? this.networkId,
      tabId: tabId ?? this.tabId,
      msgid: msgid ?? this.msgid,
      kind: kind ?? this.kind,
      timestampMs: timestampMs ?? this.timestampMs,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowId.present) {
      map['row_id'] = Variable<int>(rowId.value);
    }
    if (networkId.present) {
      map['network_id'] = Variable<String>(networkId.value);
    }
    if (tabId.present) {
      map['tab_id'] = Variable<String>(tabId.value);
    }
    if (msgid.present) {
      map['msgid'] = Variable<String>(msgid.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('rowId: $rowId, ')
          ..write('networkId: $networkId, ')
          ..write('tabId: $tabId, ')
          ..write('msgid: $msgid, ')
          ..write('kind: $kind, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

abstract class _$HistoryDatabase extends GeneratedDatabase {
  _$HistoryDatabase(QueryExecutor e) : super(e);
  $HistoryDatabaseManager get managers => $HistoryDatabaseManager(this);
  late final $MessagesTable messages = $MessagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [messages];
}

typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> rowId,
      required String networkId,
      required String tabId,
      Value<String?> msgid,
      required String kind,
      required int timestampMs,
      required String payload,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> rowId,
      Value<String> networkId,
      Value<String> tabId,
      Value<String?> msgid,
      Value<String> kind,
      Value<int> timestampMs,
      Value<String> payload,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$HistoryDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get networkId => $composableBuilder(
    column: $table.networkId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tabId => $composableBuilder(
    column: $table.tabId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get msgid => $composableBuilder(
    column: $table.msgid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$HistoryDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get networkId => $composableBuilder(
    column: $table.networkId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tabId => $composableBuilder(
    column: $table.tabId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get msgid => $composableBuilder(
    column: $table.msgid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$HistoryDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get networkId =>
      $composableBuilder(column: $table.networkId, builder: (column) => column);

  GeneratedColumn<String> get tabId =>
      $composableBuilder(column: $table.tabId, builder: (column) => column);

  GeneratedColumn<String> get msgid =>
      $composableBuilder(column: $table.msgid, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$HistoryDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$HistoryDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$HistoryDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                Value<String> networkId = const Value.absent(),
                Value<String> tabId = const Value.absent(),
                Value<String?> msgid = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> timestampMs = const Value.absent(),
                Value<String> payload = const Value.absent(),
              }) => MessagesCompanion(
                rowId: rowId,
                networkId: networkId,
                tabId: tabId,
                msgid: msgid,
                kind: kind,
                timestampMs: timestampMs,
                payload: payload,
              ),
          createCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                required String networkId,
                required String tabId,
                Value<String?> msgid = const Value.absent(),
                required String kind,
                required int timestampMs,
                required String payload,
              }) => MessagesCompanion.insert(
                rowId: rowId,
                networkId: networkId,
                tabId: tabId,
                msgid: msgid,
                kind: kind,
                timestampMs: timestampMs,
                payload: payload,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$HistoryDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$HistoryDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;

class $HistoryDatabaseManager {
  final _$HistoryDatabase _db;
  $HistoryDatabaseManager(this._db);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
}
