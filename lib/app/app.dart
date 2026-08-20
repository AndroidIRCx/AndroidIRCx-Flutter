import 'package:androidircx/app/theme/app_theme.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/settings/app_settings_controller.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
import 'package:androidircx/features/bootstrap/presentation/bootstrap_screen.dart';
import 'package:androidircx/features/onboarding/presentation/onboarding_screen.dart';
import 'package:androidircx/features/security/presentation/app_lock_gate.dart';
import 'package:flutter/material.dart';

class AndroidIrcxApp extends StatefulWidget {
  const AndroidIrcxApp({
    super.key,
    this.networkRepository,
    this.settingsRepository,
    this.foregroundConnectionService =
        const MethodChannelForegroundConnectionService(),
    this.historyRepositoryLoader,
  });

  final NetworkRepository? networkRepository;
  final SettingsRepository? settingsRepository;
  final ForegroundConnectionService foregroundConnectionService;
  final HistoryRepositoryLoader? historyRepositoryLoader;

  @override
  State<AndroidIrcxApp> createState() => _AndroidIrcxAppState();
}

class _AndroidIrcxAppState extends State<AndroidIrcxApp> {
  late final AppSettingsController _settingsController;

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController(
      repository: widget.settingsRepository,
    );
    _settingsController.load();
  }

  @override
  void dispose() {
    _settingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      controller: _settingsController,
      child: AnimatedBuilder(
        animation: _settingsController,
        builder: (context, _) {
          return MaterialApp(
            title: 'AndroidIRCx Flutter',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(_settingsController.settings),
            home: AppLockGate(
              enabled: !_settingsController.isLoading &&
                  _settingsController.settings.appLockEnabled,
              child: _buildHome(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    if (_settingsController.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_settingsController.settings.onboardingCompleted) {
      final repository =
          widget.networkRepository ??
          SharedPrefsNetworkRepository(
            secretStorage: FlutterSecureSecretStorage(),
          );
      return OnboardingScreen(
        networkRepository: repository,
        onCompleted: () => _settingsController.save(
          _settingsController.settings.copyWith(onboardingCompleted: true),
        ),
      );
    }
    return BootstrapScreen(
      networkRepository: widget.networkRepository,
      foregroundConnectionService: widget.foregroundConnectionService,
      historyRepositoryLoader: widget.historyRepositoryLoader,
    );
  }
}
