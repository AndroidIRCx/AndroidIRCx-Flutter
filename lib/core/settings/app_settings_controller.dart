import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:flutter/widgets.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({SettingsRepository? repository})
    : _repository = repository ?? SharedPrefsSettingsRepository();

  final SettingsRepository _repository;
  AppSettings _settings = const AppSettings();
  bool _isLoading = true;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _settings = await _repository.loadSettings();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> reload() => load();

  Future<void> save(AppSettings settings) async {
    _settings = settings;
    _isLoading = false;
    notifyListeners();
    await _repository.saveSettings(settings);
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'No AppSettingsScope found in context.');
    return scope!.notifier!;
  }

  static AppSettingsController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>()
        ?.notifier;
  }
}
