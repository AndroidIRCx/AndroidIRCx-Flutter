import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/connections/presentation/network_list_screen.dart';
import 'package:flutter/material.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  late final NetworkListController _controller;
  late final SessionRegistry _sessionRegistry;
  bool _bootstrapComplete = false;

  @override
  void initState() {
    super.initState();
    _sessionRegistry = SessionRegistry();
    _controller = NetworkListController(
      repository: SharedPrefsNetworkRepository(),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _controller.load();
    for (final network in _controller.networks.where((item) => item.autoConnect)) {
      final session = _sessionRegistry.obtainSession(network);
      await session.start();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _bootstrapComplete = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _sessionRegistry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapComplete && _controller.isLoading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return NetworkListScreen(
      controller: _controller,
      sessionRegistry: _sessionRegistry,
    );
  }
}
