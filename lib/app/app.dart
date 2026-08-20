import 'package:androidircx/app/theme/app_theme.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:androidircx/features/bootstrap/presentation/bootstrap_screen.dart';
import 'package:flutter/material.dart';

class AndroidIrcxApp extends StatelessWidget {
  const AndroidIrcxApp({
    super.key,
    this.networkRepository,
    this.foregroundConnectionService =
        const MethodChannelForegroundConnectionService(),
  });

  final NetworkRepository? networkRepository;
  final ForegroundConnectionService foregroundConnectionService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AndroidIRCx Flutter',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: BootstrapScreen(
        networkRepository: networkRepository,
        foregroundConnectionService: foregroundConnectionService,
      ),
    );
  }
}
