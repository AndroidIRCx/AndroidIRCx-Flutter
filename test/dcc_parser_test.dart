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

  test('parses dcc resume and accept control payloads', () {
    final resume = parseDccOffer('DCC RESUME "movie.mkv" 5000 2048 999');
    final accept = parseDccOffer('DCC ACCEPT "movie.mkv" 5000 2048 999');

    expect(resume, isNotNull);
    expect(resume!.command, 'RESUME');
    expect(resume.filename, 'movie.mkv');
    expect(resume.port, 5000);
    expect(resume.offset, 2048);
    expect(resume.token, '999');

    expect(accept, isNotNull);
    expect(accept!.command, 'ACCEPT');
    expect(accept.filename, 'movie.mkv');
    expect(accept.port, 5000);
    expect(accept.offset, 2048);
    expect(accept.token, '999');
  });
}
