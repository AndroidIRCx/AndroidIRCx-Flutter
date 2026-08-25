import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Explains what data the app stores and how, and links to the privacy policy.
/// Shown during onboarding and reachable from Settings.
class DataPrivacyScreen extends StatelessWidget {
  const DataPrivacyScreen({super.key});

  static const String privacyPolicyUrl = 'https://androidircx.com/privacy';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Data & privacy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Your data stays on your device',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const _PrivacyPoint(
              icon: Icons.phone_android,
              title: 'Local-first',
              body:
                  'Networks, settings, and chat history are stored on this '
                  'device. AndroidIRCX has no account and no cloud sync.',
            ),
            const _PrivacyPoint(
              icon: Icons.lock_outline,
              title: 'Encrypted history',
              body:
                  'Message history is encrypted with a key protected by your '
                  'fingerprint/PIN, so a stolen database file cannot be read.',
            ),
            const _PrivacyPoint(
              icon: Icons.vpn_key_outlined,
              title: 'Secrets in secure storage',
              body:
                  'Server, SASL, and channel passwords and client '
                  'certificates are kept in the platform secure storage '
                  '(Android Keystore), never in plain files or exports.',
            ),
            const _PrivacyPoint(
              icon: Icons.dns_outlined,
              title: 'Direct IRC connections',
              body:
                  'The app connects straight to the IRC servers you choose. '
                  'Message content is sent to those servers per the IRC '
                  'protocol; use TLS and SASL for privacy in transit.',
            ),
            const _PrivacyPoint(
              icon: Icons.insights_outlined,
              title: 'Ads, analytics & crash reports',
              body:
                  'AndroidIRCX uses Google AdMob banner ads and opt-in '
                  'rewarded ads that can temporarily hide banners. Anonymous '
                  'usage analytics and crash reports (Firebase Analytics/'
                  'Crashlytics) are OFF by default and only collected if you '
                  'opt in; you can change this any time in Settings.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openPolicy(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open privacy policy'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPolicy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(privacyPolicyUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the privacy policy.')),
      );
    }
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
