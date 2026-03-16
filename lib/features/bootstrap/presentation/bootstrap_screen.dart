import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = NetworkListController(
      repository: SharedPrefsNetworkRepository(),
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NetworkListScreen(controller: _controller);
  }
}
