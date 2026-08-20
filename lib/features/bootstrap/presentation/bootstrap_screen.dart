import 'dart:async';

import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/core/security/history_encryption_key_manager.dart';
import 'package:androidircx/core/security/local_auth_history_unlock.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/chat/data/encrypted_history_database.dart';
import 'package:androidircx/features/chat/data/message_history_repository.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/connections/presentation/network_list_screen.dart';
import 'package:flutter/material.dart';

/// Loads the encrypted message-history repository (prompting biometric/PIN).
typedef HistoryRepositoryLoader = Future<MessageHistoryRepository?> Function();

Future<MessageHistoryRepository?> _defaultHistoryRepositoryLoader() {
  final keyManager = HistoryEncryptionKeyManager(
    storage: FlutterSecureSecretStorage(),
    authenticator: LocalAuthHistoryUnlockAuthenticator(),
  );
  return openEncryptedHistory(keyManager);
}

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({
    super.key,
    this.networkRepository,
    this.foregroundConnectionService =
        const MethodChannelForegroundConnectionService(),
    this.historyRepositoryLoader,
  });

  final NetworkRepository? networkRepository;
  final ForegroundConnectionService foregroundConnectionService;

  /// Overridable for tests; defaults to the biometric/PIN-gated encrypted
  /// history repository. When it returns null (e.g. auth declined), sessions
  /// keep messages in memory only.
  final HistoryRepositoryLoader? historyRepositoryLoader;

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen>
    with WidgetsBindingObserver {
  late final ForegroundConnectionService _foregroundConnectionService;
  late final NetworkListController _controller;
  late final SessionRegistry _sessionRegistry;
  MessageHistoryRepository? _historyRepository;
  bool _bootstrapComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foregroundConnectionService = widget.foregroundConnectionService;
    _sessionRegistry = SessionRegistry(
      foregroundService: _foregroundConnectionService,
      sessionFactory: (network) => ChatSessionController(
        network: network,
        historyRepository: _historyRepository,
      ),
    );
    _controller = NetworkListController(
      repository:
          widget.networkRepository ??
          SharedPrefsNetworkRepository(
            secretStorage: FlutterSecureSecretStorage(),
          ),
    );
    _bootstrap();
  }

  Future<void> _loadHistoryRepository() async {
    final loader =
        widget.historyRepositoryLoader ?? _defaultHistoryRepositoryLoader;
    try {
      _historyRepository = await loader();
    } catch (_) {
      _historyRepository = null;
    }
  }

  Future<void> _bootstrap() async {
    await _loadHistoryRepository();
    await _controller.load();
    for (final network in _controller.networks.where(
      (item) => item.autoConnect,
    )) {
      final session = _sessionRegistry.obtainSession(network);
      await session.start();
    }
    await _consumePendingForegroundAction();

    if (!mounted) {
      return;
    }

    setState(() {
      _bootstrapComplete = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_handleAppLifecycleState(state));
  }

  Future<void> _handleAppLifecycleState(AppLifecycleState state) async {
    await _sessionRegistry.handleAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      await _consumePendingForegroundAction();
    }
  }

  Future<void> _consumePendingForegroundAction() async {
    final action = await _foregroundConnectionService.consumePendingAction();
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case ForegroundConnectionAction.disconnectAll:
        await _sessionRegistry.closeAllSessions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sessionRegistry.flushAllSessions());
    _controller.dispose();
    _sessionRegistry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapComplete && _controller.isLoading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return NetworkListScreen(
      controller: _controller,
      sessionRegistry: _sessionRegistry,
    );
  }
}
