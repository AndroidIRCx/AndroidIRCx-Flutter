import 'dart:async';

import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/core/presets/server_preset_service.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/dcc/services/dcc_file_picker.dart';
import 'package:androidircx/dcc/services/dcc_service.dart';
import 'package:androidircx/dcc/services/dcc_socket_backend.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/chat/presentation/channel_list_screen.dart';
import 'package:androidircx/features/chat/presentation/chat_screen.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/chat/presentation/connection_details_screen.dart';
import 'package:androidircx/features/connections/presentation/network_form_screen.dart';
import 'package:androidircx/features/connections/presentation/network_list_screen.dart';
import 'package:androidircx/features/onboarding/presentation/onboarding_screen.dart';
import 'package:androidircx/features/security/presentation/app_lock_gate.dart';
import 'package:androidircx/features/settings/presentation/theme_editor_screen.dart';
import 'package:androidircx/media/services/link_preview_service.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:androidircx/media/services/media_auto_download_policy.dart';
import 'package:androidircx/media/services/media_download_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final List<String> sentLines = <String>[];

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
  }

  void emit(String line) {
    _controller.add(line);
  }
}

bool _spanTreeContainsStyle(
  InlineSpan span,
  bool Function(TextStyle? style) predicate,
) {
  if (span is TextSpan) {
    if (predicate(span.style)) {
      return true;
    }
    return span.children?.any(
          (child) => _spanTreeContainsStyle(child, predicate),
        ) ??
        false;
  }
  return false;
}

class _FakeDccConnection implements DccSocketConnection {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentPackets = <List<int>>[];

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    sentPackets.add(Uint8List.fromList(data));
  }
}

class _FakeDccServer implements DccSocketServer {
  final StreamController<DccSocketConnection> _controller =
      StreamController<DccSocketConnection>.broadcast();

  @override
  String get address => '127.0.0.1';

  @override
  Stream<DccSocketConnection> get connections => _controller.stream;

  @override
  int get port => 5001;

  void accept(DccSocketConnection connection) {
    _controller.add(connection);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class _FakeDccBackend implements DccSocketBackend {
  final _FakeDccConnection connection = _FakeDccConnection();
  _FakeDccServer? server;

  @override
  Future<DccSocketServer> bindEphemeral() async {
    final next = _FakeDccServer();
    server = next;
    return next;
  }

  @override
  Future<DccSocketConnection> connect({
    required String host,
    required int port,
  }) async => connection;
}

class _FakeDccFilePicker implements DccFilePicker {
  _FakeDccFilePicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> pickFile() async {
    calls += 1;
    return path;
  }
}

class _FakeMediaDownloadService implements MediaDownloadService {
  final calls = <({String url, String? directoryPath})>[];

  @override
  Future<MediaDownloadResult> download(
    String url, {
    String? directoryPath,
  }) async {
    calls.add((url: url, directoryPath: directoryPath));
    return MediaDownloadResult(
      url: url,
      fileName: 'manual.pdf',
      localPath: r'C:\Downloads\Media\manual.pdf',
      bytesDownloaded: 6,
    );
  }
}

class _FakeMediaAutoDownloadPolicy implements MediaAutoDownloadPolicy {
  _FakeMediaAutoDownloadPolicy({required this.allowed});

  bool allowed;
  final modes = <MediaAutoDownloadMode>[];

  @override
  Future<bool> canAutoDownload(MediaAutoDownloadMode mode) async {
    modes.add(mode);
    return allowed;
  }
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }
}

void main() {
  setUp(() {
    // Avoid real network for link previews in widget tests.
    linkPreviewService = LinkPreviewService(fetcher: (_) async => '');
  });

  testWidgets('shows seeded network on bootstrap', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AndroidIrcxApp(
        networkRepository: SharedPrefsNetworkRepository(
          secretStorage: InMemorySecretStorage(),
        ),
        settingsRepository: _FakeSettingsRepository(
          const AppSettings(onboardingCompleted: true),
        ),
        foregroundConnectionService: const NoopForegroundConnectionService(),
        historyRepositoryLoader: () async => null,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('AndroidIRCX'), findsOneWidget);
    expect(find.text('DBase'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('connection details screen shows network and status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => _FakeTransport()),
    );
    await tester.pumpWidget(
      MaterialApp(home: ConnectionDetailsScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('DBase'), findsOneWidget);
    expect(find.text('irc.dbase.in.rs:6697'), findsOneWidget);
    expect(find.text('TLS'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('theme editor generates JSON from picked brightness', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: ThemeEditorScreen(
          initialJson: '',
          onSaved: (json) async {
            saved = json;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Dark base'));
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.contains('"brightness":"dark"'), isTrue);
    expect(saved!.contains('"primary":'), isTrue);
  });

  testWidgets('app lock gate is transparent when disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLockGate(enabled: false, child: Text('SECRET')),
      ),
    );
    await tester.pump();
    expect(find.text('SECRET'), findsOneWidget);
  });

  testWidgets('app lock gate hides content until unlocked', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          enabled: true,
          unlock: () async {
            calls++;
            return calls > 1;
          },
          child: const Text('SECRET'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AndroidIRCX is locked'), findsOneWidget);
    expect(find.text('SECRET'), findsNothing);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('SECRET'), findsOneWidget);
  });

  testWidgets('onboarding wizard creates a network and completes', (
    tester,
  ) async {
    final repo = InMemoryNetworkRepository(const []);
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          networkRepository: repo,
          onCompleted: () async {
            completed = true;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to AndroidIRCX'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Privacy step: consent required before Next is enabled.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Identity step (defaults filled).
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Network step (DBase selected by default).
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Channels step -> Next.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Notifications step -> Finish (permission prompt skipped).
    expect(find.text('Notifications'), findsWidgets);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    final networks = await repo.loadNetworks();
    expect(networks.any((network) => network.name == 'DBase'), isTrue);
    expect(completed, isTrue);
  });

  testWidgets('applies saved app theme from settings repository', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AndroidIrcxApp(
        networkRepository: SharedPrefsNetworkRepository(
          secretStorage: InMemorySecretStorage(),
        ),
        settingsRepository: _FakeSettingsRepository(
          const AppSettings(themePreset: AppThemePreset.dark),
        ),
        foregroundConnectionService: const NoopForegroundConnectionService(),
        historyRepositoryLoader: () async => null,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
  });

  testWidgets('shows active sessions and auto-connect labels in network list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
      autoConnect: true,
      profileLabel: 'Main identity',
      profileGroup: 'general',
    );
    final controller = NetworkListController(
      repository: InMemoryNetworkRepository(const [network]),
    );
    final registry = SessionRegistry();

    await controller.load();
    registry.obtainSession(network);

    await tester.pumpWidget(
      MaterialApp(
        home: NetworkListScreen(
          controller: controller,
          sessionRegistry: registry,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Active sessions'), findsOneWidget);
    expect(find.text('1 live'), findsOneWidget);
    expect(find.text('Disconnect all'), findsOneWidget);
    expect(find.text('Auto connect enabled'), findsOneWidget);
    expect(find.text('Profile: Main identity • general'), findsOneWidget);
    expect(find.text('Open session'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Active nick: AndroidIRCX'), findsOneWidget);
    expect(find.text('Status: Idle'), findsOneWidget);
    expect(find.textContaining('Activity:'), findsNothing);

    registry.dispose();
    controller.dispose();
  });

  testWidgets('adds a network from the server directory', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = NetworkListController(
      repository: InMemoryNetworkRepository(const []),
    );
    final registry = SessionRegistry();
    await controller.load();

    const payload =
        '{"data":[{"network_name":"Libera","average_users":30000,'
        '"server_list":[{"hostname":"irc.libera.chat","port":6697,'
        '"use_ssl":true}]}]}';

    await tester.pumpWidget(
      MaterialApp(
        home: NetworkListScreen(
          controller: controller,
          sessionRegistry: registry,
          presetService: ServerPresetService(httpGet: (_) async => payload),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Browse server directory'));
    await tester.pumpAndSettle();

    expect(find.text('Server directory'), findsOneWidget);
    expect(find.text('Libera'), findsOneWidget);

    await tester.tap(find.text('Libera'));
    await tester.pumpAndSettle();

    expect(
      controller.networks.any((network) => network.name == 'Libera'),
      isTrue,
    );

    registry.dispose();
    controller.dispose();
  });

  testWidgets('network form edits profile label and group fields', (
    tester,
  ) async {
    NetworkFormResult? result;
    const network = NetworkConfig(
      id: 'profile-net',
      name: 'ProfileNet',
      host: 'irc.profile.test',
      port: 6697,
      nickname: 'tester',
      altNickname: 'tester_',
      profileLabel: 'Old profile',
      profileGroup: 'old-group',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<NetworkFormResult>(
                MaterialPageRoute<NetworkFormResult>(
                  builder: (_) =>
                      const NetworkFormScreen(initialValue: network),
                ),
              );
            },
            child: const Text('Open form'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    final formScrollable = find
        .descendant(
          of: find.byType(NetworkFormScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('network-form-profile-label')),
      500,
      scrollable: formScrollable,
    );
    final profileLabelField = find.byKey(
      const Key('network-form-profile-label'),
    );
    final profileGroupField = find.byKey(
      const Key('network-form-profile-group'),
    );
    await tester.enterText(profileLabelField, ' Main profile ');
    await tester.scrollUntilVisible(
      find.byKey(const Key('network-form-profile-group')),
      500,
      scrollable: formScrollable,
    );
    await tester.enterText(profileGroupField, ' General ');
    await tester.scrollUntilVisible(
      find.text('Save network'),
      500,
      scrollable: formScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save network'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.profileLabel, 'Main profile');
    expect(result!.profileGroup, 'General');
  });

  testWidgets('network form edits service fallback channel keys and proxy', (
    tester,
  ) async {
    NetworkFormResult? result;
    const network = NetworkConfig(
      id: 'advanced-net',
      name: 'AdvancedNet',
      host: 'irc.advanced.test',
      port: 6697,
      nickname: 'tester',
      altNickname: 'tester_',
      saslAccount: 'alice',
      saslPassword: 'secret',
      serviceAuthFallback: ServiceAuthFallback.nickServ,
      serviceAuthTarget: 'NickServ',
      autoJoinChannels: ['#secret'],
      autoJoinChannelKeys: {'#secret': 'old-key'},
      proxyType: IrcProxyType.socks5,
      proxyHost: '127.0.0.1',
      proxyPort: 9050,
      proxyUsername: 'old-user',
      proxyPassword: 'old-pass',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<NetworkFormResult>(
                MaterialPageRoute<NetworkFormResult>(
                  builder: (_) =>
                      const NetworkFormScreen(initialValue: network),
                ),
              );
            },
            child: const Text('Open form'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    final formScrollable = find
        .descendant(
          of: find.byType(NetworkFormScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.scrollUntilVisible(
      find.byKey(const Key('network-form-service-auth-target')),
      500,
      scrollable: formScrollable,
    );
    await tester.enterText(
      find.byKey(const Key('network-form-service-auth-target')),
      'AuthServ',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('network-form-auto-join-channel-keys')),
      500,
      scrollable: formScrollable,
    );
    await tester.enterText(
      find.byKey(const Key('network-form-auto-join-channel-keys')),
      '#secret=new-key\nstaff staff-key',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('network-form-proxy-host')),
      500,
      scrollable: formScrollable,
    );
    await tester.enterText(
      find.byKey(const Key('network-form-proxy-host')),
      '10.0.2.2',
    );
    await tester.enterText(
      find.byKey(const Key('network-form-proxy-port')),
      '9150',
    );
    await tester.enterText(
      find.byKey(const Key('network-form-proxy-username')),
      'proxy-user',
    );
    await tester.enterText(
      find.byKey(const Key('network-form-proxy-password')),
      'proxy-pass',
    );
    await tester.scrollUntilVisible(
      find.text('Save network'),
      500,
      scrollable: formScrollable,
    );
    await tester.tap(find.text('Save network'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.serviceAuthFallback, ServiceAuthFallback.nickServ);
    expect(result!.serviceAuthTarget, 'AuthServ');
    expect(result!.autoJoinChannelKeys, {
      '#secret': 'new-key',
      '#staff': 'staff-key',
    });
    expect(result!.proxyType, IrcProxyType.socks5);
    expect(result!.proxyHost, '10.0.2.2');
    expect(result!.proxyPort, 9150);
    expect(result!.proxyUsername, 'proxy-user');
    expect(result!.proxyPassword, 'proxy-pass');
  });

  testWidgets('settings saves DCC download folder path', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-dcc-download-directory')),
      500,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-dcc-download-directory')),
      r'C:\Downloads\IRC',
    );
    await tester.tap(find.byTooltip('Save DCC folder'));
    await tester.pump();

    final settings = await SharedPrefsSettingsRepository().loadSettings();

    expect(settings.dccDownloadDirectoryPath, r'C:\Downloads\IRC');
  });

  testWidgets('settings saves media download folder path', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-media-download-directory')),
      500,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-media-download-directory')),
      r'C:\Downloads\Media',
    );
    await tester.tap(find.byTooltip('Save media folder'));
    await tester.pump();

    final settings = await SharedPrefsSettingsRepository().loadSettings();

    expect(settings.mediaDownloadDirectoryPath, r'C:\Downloads\Media');
  });

  testWidgets('settings saves media auto-download mode', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-media-auto-download')),
      500,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-media-auto-download')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any network').last);
    await tester.pumpAndSettle();

    final settings = await SharedPrefsSettingsRepository().loadSettings();

    expect(settings.mediaAutoDownloadMode, MediaAutoDownloadMode.always);
  });

  testWidgets('settings saves appearance and theme options', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump();

    Future<void> scrollTo(String key) async {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    await scrollTo('settings-theme-preset');
    await tester.tap(find.byKey(const Key('settings-theme-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();

    const customJson =
        '{"brightness":"dark","primary":"#336699","messageDcc":"#224433"}';
    await scrollTo('settings-custom-theme-json');
    await tester.enterText(
      find.byKey(const Key('settings-custom-theme-json')),
      customJson,
    );
    await tester.tap(find.byTooltip('Save custom theme'));
    await tester.pumpAndSettle();

    await scrollTo('settings-message-density');
    await tester.tap(find.byKey(const Key('settings-message-density')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact').last);
    await tester.pumpAndSettle();

    await scrollTo('settings-message-font-family');
    await tester.tap(
      find.byKey(const Key('settings-message-font-family')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monospace').last);
    await tester.pumpAndSettle();

    await scrollTo('settings-nick-color-mode');
    await tester.tap(find.byKey(const Key('settings-nick-color-mode')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vivid').last);
    await tester.pumpAndSettle();

    final settings = await SharedPrefsSettingsRepository().loadSettings();
    expect(settings.themePreset, AppThemePreset.custom);
    expect(settings.customThemeJson, customJson);
    expect(settings.messageDensity, MessageDensity.compact);
    expect(settings.messageFontFamily, 'monospace');
    expect(settings.monospaceMessages, isTrue);
    expect(settings.nickColorMode, NickColorMode.vivid);
  });

  testWidgets('settings shows the privacy doc', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-privacy-topic')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('settings-privacy-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-privacy-topic')));
    await tester.pumpAndSettle();
    expect(find.text('Privacy'), findsWidgets);
    expect(find.textContaining('SecretStorage'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // IRC help, Support and Release audit were removed from the menu.
    expect(find.byKey(const Key('settings-help-topic')), findsNothing);
    expect(find.byKey(const Key('settings-support-topic')), findsNothing);
    expect(find.byKey(const Key('settings-release-audit-topic')), findsNothing);
  });

  testWidgets('shows IRC services quick actions on the server tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('NickServ HELP'), findsOneWidget);
    expect(find.text('ChanServ HELP'), findsOneWidget);
    expect(find.text('MemoServ HELP'), findsOneWidget);
    await tester.tap(find.text('NickServ HELP'));
    await tester.pump();
    expect(find.text('NickServ'), findsWidgets);

    controller.dispose();
  });

  testWidgets('dismisses connected status banner in chat screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();
    transport.emit(':server 001 AndroidIRCX :Welcome to DBase');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('connection-banner-dismiss')), findsOneWidget);

    await tester.tap(find.byKey(const Key('connection-banner-dismiss')));
    await tester.pump();

    expect(find.byKey(const Key('connection-banner-dismiss')), findsNothing);

    controller.dispose();
  });

  testWidgets('lists other networks and switches from the chat drawer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const netA = NetworkConfig(
      id: 'a',
      name: 'NetA',
      host: 'a.example',
      port: 6697,
      nickname: 'X',
      altNickname: 'X_',
    );
    const netB = NetworkConfig(
      id: 'b',
      name: 'NetB',
      host: 'b.example',
      port: 6697,
      nickname: 'X',
      altNickname: 'X_',
    );
    final networkController = NetworkListController(
      repository: InMemoryNetworkRepository(const [netA, netB]),
    );
    await networkController.load();
    final registry = SessionRegistry();
    final controller = ChatSessionController(
      network: netA,
      ircService: IrcService(transportConnector: (_) async => _FakeTransport()),
    );

    NetworkConfig? switched;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          controller: controller,
          sessionRegistry: registry,
          networkController: networkController,
          onSwitchNetwork: (network) async {
            switched = network;
          },
          onManageNetworks: () {},
        ),
      ),
    );
    await tester.pump();

    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('NETWORKS'), findsOneWidget);
    expect(find.text('NetB'), findsOneWidget);
    expect(find.text('Manage networks'), findsOneWidget);

    await tester.tap(find.text('NetB'));
    await tester.pumpAndSettle();
    expect(switched?.id, 'b');

    controller.dispose();
    registry.dispose();
  });

  testWidgets('shows and applies slash command suggestions in chat composer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '/n hello');
    await tester.pump();

    expect(find.text('/nick'), findsWidgets);
    expect(find.text('/nickserv'), findsWidgets);
    expect(find.text('/ns'), findsOneWidget);
    expect(find.text('alias'), findsWidgets);
    expect(find.text('/encmsg'), findsNothing);

    await tester.tap(find.text('/ns'));
    await tester.pump();

    expect(find.text('/ns hello'), findsOneWidget);
    expect(find.text('/nickserv'), findsNothing);

    controller.dispose();
  });

  testWidgets('shows and applies nick/channel autocomplete in chat composer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    await controller.joinChannel(
      const JoinChannelRequest(channel: '#androidircx'),
    );
    transport.emit(':server 353 AndroidIRCX = #room :@alice bob carol');
    await tester.pump();
    await tester.pump();
    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.name == '#room').id,
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, 'hello al');
    await tester.pump();
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('nick'), findsOneWidget);

    await tester.tap(find.text('alice'));
    await tester.pump();
    expect(find.text('hello alice '), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '/msg #and');
    await tester.pump();
    expect(find.text('#androidircx'), findsOneWidget);
    expect(find.text('channel'), findsOneWidget);

    await tester.tap(find.text('#androidircx'));
    await tester.pump();
    expect(find.text('/msg #androidircx '), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows server playback actions in history tools for chat tabs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('History tools'));
    await tester.pumpAndSettle();

    expect(find.text('Server playback'), findsOneWidget);
    expect(find.text('Recent 25'), findsOneWidget);
    expect(find.text('Recent 100'), findsOneWidget);
    expect(find.text('Older 50'), findsOneWidget);
    expect(find.text('Newer 50'), findsOneWidget);
    expect(find.text('Around latest'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows unread badge for inactive tabs in chat drawer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    transport.emit(':alice!user@example PRIVMSG #room :one');
    await tester.pump();
    transport.emit(':bob!user@example PRIVMSG #room :two');
    await tester.pump();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('#room'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    controller.dispose();
  });

  testWidgets(
    'shows grouped searchable nick details in the channel user drawer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const network = NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.dbase.in.rs',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      );
      final transport = _FakeTransport();
      final controller = ChatSessionController(
        network: network,
        ircService: IrcService(transportConnector: (_) async => transport),
      );

      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(controller: controller)),
      );
      await tester.pump();

      transport.emit(
        ':server 005 AndroidIRCX CHANTYPES=#& PREFIX=(qaohv)~&@%+ :supported',
      );
      transport.emit(
        ':alice!ident@example JOIN #room aliceAccount :Alice Example',
      );
      transport.emit(
        ':server 353 AndroidIRCX = #room :~owner &admin @alice!ident@example %half +voice regular',
      );
      transport.emit(':alice!ident@example AWAY :coffee');
      await tester.pump();
      await tester.pump();
      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.name == '#room').id,
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.people_outline));
      await tester.pumpAndSettle();

      expect(find.text('Search users'), findsOneWidget);
      expect(find.text('~ Owners (1)'), findsOneWidget);
      expect(find.text('& Admins (1)'), findsOneWidget);
      expect(find.text('@ Operators (1)'), findsOneWidget);
      expect(find.text('% Half operators (1)'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('+ Voiced (1)'), findsOneWidget);
      expect(find.text('Regular (1)'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('account: aliceAccount'), findsWidgets);
      expect(find.textContaining('away: coffee'), findsOneWidget);
      expect(find.textContaining('mode: @'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('channel-user-search')),
        'ali',
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 6 users'), findsOneWidget);
      expect(find.text('@ Operators (1)'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('owner'), findsNothing);

      controller.dispose();
    },
  );

  testWidgets('renders channel list topics with IRC formatting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(home: ChannelListScreen(controller: controller)),
    );
    await tester.pump();

    transport.emit(':server 321 AndroidIRCX Channel :Users Name');
    transport.emit(
      ':server 322 AndroidIRCX #color 5 :\u000304Red \u0002bold\u0002',
    );
    transport.emit(':server 323 AndroidIRCX :End of /LIST');
    await tester.pump();

    expect(find.textContaining('\u0003'), findsNothing);
    expect(find.textContaining('Red bold'), findsWidgets);

    final topicRichText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((widget) => widget.text.toPlainText().contains('Red bold'));
    expect(
      _spanTreeContainsStyle(
        topicRichText.text,
        (style) => style?.color == const Color(0xFFFF0000),
      ),
      isTrue,
    );
    expect(
      _spanTreeContainsStyle(
        topicRichText.text,
        (style) => style?.fontWeight == FontWeight.bold,
      ),
      isTrue,
    );

    controller.dispose();
  });

  testWidgets('toggles inline message search from the chat header', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Search messages'));
    await tester.pump();
    expect(find.text('Search current tab'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'nickserv');
    await tester.pump();
    expect(find.text('0 matches'), findsOneWidget);

    await tester.tap(find.byTooltip('Close message search'));
    await tester.pump();
    expect(find.text('Search current tab'), findsNothing);

    controller.dispose();
  });

  testWidgets('shows message attachment cards and long-press actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final dccBackend = _FakeDccBackend();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
      dccService: DccService(backend: dccBackend),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :see https://example.com/file.pdf',
    );
    await tester.pump();

    expect(find.text('File'), findsOneWidget);
    expect(find.textContaining('https://example.com/file.pdf'), findsWidgets);

    await tester.longPress(
      find.textContaining('https://example.com/file.pdf').first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Copy clean text'), findsOneWidget);
    expect(find.text('Copy first link'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('downloads media attachment cards to configured folder', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final mediaDownloadService = _FakeMediaDownloadService();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(mediaDownloadDirectoryPath: r'C:\Downloads\Media'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          controller: controller,
          mediaDownloadService: mediaDownloadService,
        ),
      ),
    );
    await tester.pump();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    await tester.pump();
    transport.emit(
      ':alice!user@example PRIVMSG #room :manual https://example.com/manual.pdf',
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Download file'));
    await tester.pump();

    expect(mediaDownloadService.calls, hasLength(1));
    expect(
      mediaDownloadService.calls.single.url,
      'https://example.com/manual.pdf',
    );
    expect(
      mediaDownloadService.calls.single.directoryPath,
      r'C:\Downloads\Media',
    );
    expect(find.textContaining('Downloaded manual.pdf'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('auto-downloads new media attachments when enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final mediaDownloadService = _FakeMediaDownloadService();
    final autoDownloadPolicy = _FakeMediaAutoDownloadPolicy(allowed: true);
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(
          mediaDownloadDirectoryPath: r'C:\Downloads\Media',
          mediaAutoDownloadMode: MediaAutoDownloadMode.always,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          controller: controller,
          mediaDownloadService: mediaDownloadService,
          mediaAutoDownloadPolicy: autoDownloadPolicy,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    await tester.pump();
    transport.emit(
      ':alice!user@example PRIVMSG #room :auto https://example.com/auto.pdf',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(autoDownloadPolicy.modes, [MediaAutoDownloadMode.always]);
    expect(mediaDownloadService.calls, hasLength(1));
    expect(
      mediaDownloadService.calls.single.url,
      'https://example.com/auto.pdf',
    );
    expect(
      mediaDownloadService.calls.single.directoryPath,
      r'C:\Downloads\Media',
    );

    controller.selectTab(controller.activeTabId);
    await tester.pump();
    expect(mediaDownloadService.calls, hasLength(1));

    controller.dispose();
  });

  testWidgets('fills composer from message quote and reply actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':alice!user@example PRIVMSG #room :Hello there');
    await tester.pump();

    await tester.longPress(find.textContaining('Hello there').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quote in composer'));
    await tester.pumpAndSettle();
    expect(find.text('> Hello there'), findsOneWidget);

    await tester.longPress(find.textContaining('Hello there').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply with nick'));
    await tester.pumpAndSettle();
    expect(find.text('> Hello there alice: '), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows pending reply bar and sends tagged reply flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(
      '@msgid=seed-1 :alice!user@example PRIVMSG #room :Original text',
    );
    await tester.pump();

    await tester.longPress(find.textContaining('Original text').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply to message'));
    await tester.pumpAndSettle();

    expect(find.text('Replying to alice'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Reply body');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(
      transport.sentLines,
      contains('@+draft/reply=seed-1 PRIVMSG #room :Reply body'),
    );

    controller.dispose();
  });

  testWidgets('shows delete message action and sends redact command', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :draft/message-redaction');
    transport.emit(
      '@msgid=seed-redact :alice!user@example PRIVMSG #room :Delete this',
    );
    await tester.pump();
    await tester.pump();

    // Reacting from the actions sheet sends a TAGMSG with the combined tag.
    await tester.longPress(find.textContaining('Delete this').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-react-👍')));
    await tester.pumpAndSettle();
    expect(
      transport.sentLines,
      contains('@+draft/react=seed-redact\\:👍 TAGMSG #room'),
    );

    await tester.longPress(find.textContaining('Delete this').first);
    await tester.pumpAndSettle();

    // The quick-reaction row sits above the actions and can push this item
    // below the fold in the sheet's list.
    await tester.scrollUntilVisible(
      find.text('Delete message'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Delete message'), findsOneWidget);

    await tester.tap(find.text('Delete message'));
    await tester.pump();

    expect(transport.sentLines, contains('REDACT #room seed-redact'));

    controller.dispose();
  });

  testWidgets('shows typing indicator and reaction chips from TAGMSG state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(
      '@msgid=react-ui-1 :alice!user@example PRIVMSG #room :Hello',
    );
    transport.emit(
      '@+draft/react=react-ui-1\\::thumbsup: :bob!user@example TAGMSG #room',
    );
    transport.emit('@+typing=active :alice!user@example TAGMSG #room');
    await tester.pump();
    await tester.pump();

    expect(find.textContaining(':thumbsup: 1'), findsOneWidget);
    expect(find.text('alice is typing…'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows dcc session banner and actions for incoming dcc tabs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC CHAT chat 127001 5001\u0001',
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('DCC CHAT session'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsNothing);
    expect(find.text('Close'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('switches tabs with hardware keyboard shortcuts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    await tester.pump();

    // Joining focuses the channel tab; the server tab is the other one.
    final startTab = controller.activeTab.name;
    expect(startTab, '#room');

    // Focus the composer so key events land inside the shortcut scope.
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.activeTab.name, isNot('#room'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(controller.activeTab.name, '#room');

    controller.dispose();
  });

  testWidgets('lists dcc sessions in the transfers modal', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    // No sessions yet -> no transfers button in the app bar.
    expect(find.byKey(const Key('chat-dcc-transfers')), findsNothing);

    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :DCC SEND notes.txt 2130706433 5002 2048',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('chat-dcc-transfers')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-dcc-transfers')));
    await tester.pumpAndSettle();

    expect(find.text('DCC transfers'), findsOneWidget);
    expect(find.textContaining('notes.txt'), findsWidgets);

    final session = controller.dccSessions.single;
    await tester.tap(find.byKey(Key('dcc-transfer-close-${session.tabId}')));
    await tester.pumpAndSettle();

    expect(
      controller.dccSessions.single.status,
      anyOf(DccSessionStatus.closed, DccSessionStatus.failed),
    );

    controller.dispose();
  });

  testWidgets('shows reverse dcc limitations for passive send offers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();

    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC SEND "reverse.bin" 127001 0 42 abc123\u0001',
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('DCC transfer session'), findsOneWidget);
    expect(
      find.textContaining('Reverse DCC opens a local listener'),
      findsOneWidget,
    );
    expect(
      find.textContaining('NAT, firewall, and peer support'),
      findsOneWidget,
    );

    controller.dispose();
  });

  testWidgets('opens the DCC file picker from query tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final picker = _FakeDccFilePicker(null);
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(transportConnector: (_) async => transport),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller, filePicker: picker),
      ),
    );
    await tester.pump();

    await controller.handleComposerSubmit('/query alice');
    await tester.pump();
    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send file (DCC)'));
    await tester.pump();

    expect(picker.calls, 1);

    controller.dispose();
  });
}
