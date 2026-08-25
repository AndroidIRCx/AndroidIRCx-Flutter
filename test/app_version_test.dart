import 'dart:io';

import 'package:androidircx/core/app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app version constants match pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(appVersionName, match!.group(1));
    expect(appVersionCode, int.parse(match.group(2)!));
    expect(appVersion, '${match.group(1)}+${match.group(2)}');
    expect(ctcpVersionReply, 'AndroidIRCX Flutter v$appVersion');
  });
}
