import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('normalizes default aliases', () {
    final service = CommandService();

    expect(service.normalizeCommand('/j #flutter'), '/join #flutter');
    expect(service.normalizeCommand('/w nick'), '/whois nick');
    expect(service.normalizeCommand('hello'), 'hello');
  });

  test('persists command history', () async {
    final service = CommandService();

    await service.load();
    await service.addToHistory('/join #flutter');
    await service.addToHistory('/whois nick');

    final secondInstance = CommandService();
    await secondInstance.load();

    expect(secondInstance.history, hasLength(2));
    expect(secondInstance.history.first.command, '/whois nick');
  });
}
