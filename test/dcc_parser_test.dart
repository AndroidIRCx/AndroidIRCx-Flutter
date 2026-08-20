import 'package:androidircx/irc/parser/dcc_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses reverse dcc send token', () {
    final offer = parseDccOffer('DCC SEND "movie.mkv" 127001 0 42 999');

    expect(offer, isNotNull);
    expect(offer!.command, 'SEND');
    expect(offer.isReverseSend, isTrue);
    expect(offer.token, '999');
    expect(offer.port, 0);
  });

  test('parses quoted filenames and optional send size', () {
    final spaced = parseDccOffer(
      'DCC SEND "movie final cut.mkv" 2130706433 5000 42',
    );
    final withoutSize = parseDccOffer('DCC SEND readme.txt irc.example 5000');

    expect(spaced, isNotNull);
    expect(spaced!.filename, 'movie final cut.mkv');
    expect(spaced.host, '127.0.0.1');
    expect(spaced.port, 5000);
    expect(spaced.size, 42);

    expect(withoutSize, isNotNull);
    expect(withoutSize!.filename, 'readme.txt');
    expect(withoutSize.host, 'irc.example');
    expect(withoutSize.port, 5000);
    expect(withoutSize.size, isNull);
  });

  test('parses dcc resume and accept control payloads', () {
    final resume = parseDccOffer('DCC RESUME "movie final.mkv" 5000 2048 999');
    final accept = parseDccOffer('DCC ACCEPT "movie final.mkv" 5000 2048 999');

    expect(resume, isNotNull);
    expect(resume!.command, 'RESUME');
    expect(resume.filename, 'movie final.mkv');
    expect(resume.port, 5000);
    expect(resume.offset, 2048);
    expect(resume.token, '999');

    expect(accept, isNotNull);
    expect(accept!.command, 'ACCEPT');
    expect(accept.filename, 'movie final.mkv');
    expect(accept.port, 5000);
    expect(accept.offset, 2048);
    expect(accept.token, '999');
  });

  test('keeps invalid numeric host values and rejects negative numbers', () {
    final hugeHost = parseDccOffer(
      'DCC SEND file.bin 999999999999999999999 5000 1',
    );
    final negativePort = parseDccOffer('DCC SEND file.bin 127001 -1 1');

    expect(hugeHost, isNotNull);
    expect(hugeHost!.host, '999999999999999999999');
    expect(negativePort, isNotNull);
    expect(negativePort!.port, isNull);
  });
}
