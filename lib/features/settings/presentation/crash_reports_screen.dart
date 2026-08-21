import 'package:androidircx/core/diagnostics/crash_report.dart';
import 'package:androidircx/core/diagnostics/crash_reporter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lists on-device crash reports and lets the user email one to the AndroidIRCX
/// contact address via their own mail client. Nothing is sent automatically.
class CrashReportsScreen extends StatefulWidget {
  CrashReportsScreen({super.key, CrashReporter? reporter, this.launcher})
    : reporter = reporter ?? CrashReporter();

  final CrashReporter reporter;

  /// Overridable mail launcher for tests. Returns whether the URI was launched.
  final Future<bool> Function(Uri uri)? launcher;

  @override
  State<CrashReportsScreen> createState() => _CrashReportsScreenState();
}

class _CrashReportsScreenState extends State<CrashReportsScreen> {
  List<CrashReport>? _reports;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reports = await widget.reporter.loadReports();
    if (!mounted) {
      return;
    }
    setState(() => _reports = reports);
  }

  Future<bool> _launch(Uri uri) {
    final launcher = widget.launcher;
    if (launcher != null) {
      return launcher(uri);
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _email(CrashReport report) async {
    final uri = widget.reporter.buildMailtoUri(report);
    final ok = await _launch(uri);
    if (!mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email app available to send the report.'),
        ),
      );
    }
  }

  Future<void> _clear() async {
    await widget.reporter.clear();
    await _load();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Crash reports cleared.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crash reports'),
        actions: [
          if (reports != null && reports.isNotEmpty)
            IconButton(
              key: const Key('crash-reports-clear'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear all',
              onPressed: _clear,
            ),
        ],
      ),
      body: reports == null
          ? const Center(child: CircularProgressIndicator())
          : reports.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: reports.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      'Reports are stored only on this device and sanitized of '
                      'passwords. Sending one opens your email app addressed to '
                      'the AndroidIRCX team — nothing is sent automatically.',
                    ),
                  );
                }
                final report = reports[index - 1];
                return _CrashReportTile(
                  report: report,
                  onEmail: () => _email(report),
                );
              },
            ),
    );
  }
}

class _CrashReportTile extends StatelessWidget {
  const _CrashReportTile({required this.report, required this.onEmail});

  final CrashReport report;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    final firstLine = report.message.split('\n').first;
    return ExpansionTile(
      leading: Icon(
        report.fatal ? Icons.error_outline : Icons.report_gmailerrorred,
        color: report.fatal
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        firstLine.isEmpty ? '(no message)' : firstLine,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${report.source} · ${report.timestamp.toLocal()}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            report.toPlainText(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onEmail,
            icon: const Icon(Icons.email_outlined),
            label: const Text('Email report'),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No crash reports',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'If the app ever crashes, a sanitized report appears here so you '
              'can email it to the AndroidIRCX team.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
