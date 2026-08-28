import 'dart:async';

import 'package:androidircx/features/chat/data/kick_ban_reasons_repository.dart';
import 'package:flutter/material.dart';

/// Manage the preset kick/ban reasons offered by the moderation dialog.
class KickBanReasonsScreen extends StatefulWidget {
  const KickBanReasonsScreen({super.key, this.repository});

  final KickBanReasonsRepository? repository;

  @override
  State<KickBanReasonsScreen> createState() => _KickBanReasonsScreenState();
}

class _KickBanReasonsScreenState extends State<KickBanReasonsScreen> {
  late final KickBanReasonsRepository _repository;
  List<String> _reasons = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? KickBanReasonsRepository();
    unawaited(_load());
  }

  Future<void> _load() async {
    final reasons = await _repository.loadReasons();
    if (!mounted) {
      return;
    }
    setState(() {
      _reasons = reasons;
      _loaded = true;
    });
  }

  Future<void> _save(List<String> next) async {
    setState(() => _reasons = next);
    await _repository.saveReasons(next);
  }

  Future<void> _addReason() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _AddReasonDialog(),
    );
    final trimmed = (reason ?? '').trim();
    if (trimmed.isEmpty || !mounted) {
      return;
    }
    if (_reasons.any((item) => item.toLowerCase() == trimmed.toLowerCase())) {
      return;
    }
    await _save([..._reasons, trimmed]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kick/ban reasons'),
        actions: [
          IconButton(
            key: const Key('kick-ban-reasons-reset'),
            tooltip: 'Restore defaults',
            icon: const Icon(Icons.restore),
            onPressed: () =>
                unawaited(_save(KickBanReasonsRepository.defaultReasons)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('kick-ban-reason-add'),
        onPressed: () => unawaited(_addReason()),
        tooltip: 'Add reason',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final reason in _reasons)
                    ListTile(
                      key: Key('kick-ban-reason-row-$reason'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(reason),
                      trailing: IconButton(
                        key: Key('kick-ban-reason-remove-$reason'),
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => unawaited(
                          _save([
                            for (final item in _reasons)
                              if (item != reason) item,
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Owns its text controller so it outlives the dialog's exit animation.
class _AddReasonDialog extends StatefulWidget {
  const _AddReasonDialog();

  @override
  State<_AddReasonDialog> createState() => _AddReasonDialogState();
}

class _AddReasonDialogState extends State<_AddReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add reason'),
      content: TextField(
        key: const Key('kick-ban-reason-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Reason'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('kick-ban-reason-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
