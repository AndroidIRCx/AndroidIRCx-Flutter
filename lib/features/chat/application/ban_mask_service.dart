class BanMaskType {
  const BanMaskType({
    required this.id,
    required this.pattern,
    required this.description,
    required this.example,
  });

  final int id;
  final String pattern;
  final String description;
  final String example;
}

const List<BanMaskType> banMaskTypes = <BanMaskType>[
  BanMaskType(
    id: 0,
    pattern: '*!user@host',
    description: 'Ban by user@host',
    example: '*!john@192.168.1.1',
  ),
  BanMaskType(
    id: 1,
    pattern: '*!*user@host',
    description: 'Ban by *user@host',
    example: '*!*john@192.168.1.1',
  ),
  BanMaskType(
    id: 2,
    pattern: '*!*@host',
    description: 'Ban by host only',
    example: '*!*@192.168.1.1',
  ),
  BanMaskType(
    id: 3,
    pattern: '*!*user@*.host',
    description: 'Ban by *user@*.domain',
    example: '*!*john@*.example.com',
  ),
  BanMaskType(
    id: 4,
    pattern: '*!*@*.host',
    description: 'Ban by *.domain only',
    example: '*!*@*.example.com',
  ),
  BanMaskType(
    id: 5,
    pattern: 'nick!user@host',
    description: 'Ban exact nick!user@host',
    example: 'John!john@192.168.1.1',
  ),
  BanMaskType(
    id: 6,
    pattern: 'nick!*user@host',
    description: 'Ban nick with *user@host',
    example: 'John!*john@192.168.1.1',
  ),
  BanMaskType(
    id: 7,
    pattern: 'nick!*@host',
    description: 'Ban nick with any user@host',
    example: 'John!*@192.168.1.1',
  ),
  BanMaskType(
    id: 8,
    pattern: 'nick!*user@*.host',
    description: 'Ban nick with *user@*.domain',
    example: 'John!*john@*.example.com',
  ),
  BanMaskType(
    id: 9,
    pattern: 'nick!*@*.host',
    description: 'Ban nick with *.domain',
    example: 'John!*@*.example.com',
  ),
  BanMaskType(
    id: 10,
    pattern: 'nick!*@*',
    description: 'Ban by nick only',
    example: 'John!*@*',
  ),
  BanMaskType(
    id: 11,
    pattern: '*!ident@*',
    description: 'Ban by ident only',
    example: '*!john@*',
  ),
];

class BanMaskService {
  const BanMaskService();

  String generateBanMask({
    required String nick,
    required String ident,
    required String host,
    required int type,
  }) {
    final processedIdent = ident.startsWith('~') ? ident.substring(1) : ident;
    final processedHost = _processHost(host, type);

    switch (type) {
      case 0:
        return '*!$processedIdent@$host';
      case 1:
        return '*!*$processedIdent@$host';
      case 2:
        return '*!*@$host';
      case 3:
        return '*!*$processedIdent@$processedHost';
      case 4:
        return '*!*@$processedHost';
      case 5:
        return '$nick!$processedIdent@$host';
      case 6:
        return '$nick!*$processedIdent@$host';
      case 7:
        return '$nick!*@$host';
      case 8:
        return '$nick!*$processedIdent@$processedHost';
      case 9:
        return '$nick!*@$processedHost';
      case 10:
        return '$nick!*@*';
      case 11:
        return '*!$processedIdent@*';
      default:
        return '*!*@$host';
    }
  }

  String _processHost(String host, int type) {
    if (!const <int>[3, 4, 8, 9].contains(type)) {
      return host;
    }
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
      return host.replaceFirst(RegExp(r'\.\d+$'), '.*');
    }
    final parts = host.split('.');
    if (parts.length >= 2) {
      return '*.${parts.skip(parts.length - 2).join('.')}';
    }
    return '*.$host';
  }
}
