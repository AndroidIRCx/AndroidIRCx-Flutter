import 'dart:async';

import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/channel_notification_rules_repository.dart';
import 'package:androidircx/features/chat/data/channel_notes_repository.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:flutter/material.dart';

/// Per-channel settings: topic overview, auto-join on connect, a local
/// channel note, and the recent message log — consolidated in one screen.
class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({
    super.key,
    required this.controller,
    required this.tab,
    this.networkController,
    this.notesRepository,
  });

  final ChatSessionController controller;
  final ChatTab tab;

  /// Needed to persist the auto-join toggle; hidden when absent.
  final NetworkListController? networkController;
  final ChannelNotesRepository? notesRepository;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  late final ChannelNotesRepository _notes;
  final TextEditingController _noteController = TextEditingController();
  bool _autoJoin = false;
  bool _noteLoaded = false;

  @override
  void initState() {
    super.initState();
    _notes = widget.notesRepository ?? ChannelNotesRepository();
    _autoJoin = widget.controller.network.autoJoinChannels.any(
      (channel) => channel.toLowerCase() == widget.tab.name.toLowerCase(),
    );
    unawaited(_loadNote());
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    final note = await _notes.getNote(
      widget.controller.network.id,
      widget.tab.name,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _noteController.text = note;
      _noteLoaded = true;
    });
  }

  Future<void> _saveNote() async {
    await _notes.setNote(
      widget.controller.network.id,
      widget.tab.name,
      _noteController.text,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _noteController.text.trim().isEmpty
              ? 'Channel note cleared.'
              : 'Channel note saved.',
        ),
      ),
    );
  }

  Future<void> _toggleAutoJoin(bool value) async {
    final networkController = widget.networkController;
    if (networkController == null) {
      return;
    }
    setState(() => _autoJoin = value);
    await networkController.setChannelAutoJoin(
      networkId: widget.controller.network.id,
      channel: widget.tab.name,
      autoJoin: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = widget.controller.topicForTab(widget.tab.id);
    final messages = widget.controller.messagesForTab(widget.tab.id);
    final recent = messages.length <= 50
        ? messages
        : messages.sublist(messages.length - 50);
    return Scaffold(
      appBar: AppBar(title: Text(widget.tab.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if ((topic ?? '').trim().isNotEmpty) ...[
              Text('Topic', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(stripIrcFormatting(topic!)),
              const SizedBox(height: 16),
            ],
            if (widget.networkController != null)
              SwitchListTile(
                key: const Key('channel-settings-auto-join'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-join on connect'),
                subtitle: const Text(
                  'Join this channel automatically when the network connects.',
                ),
                value: _autoJoin,
                onChanged: (value) => unawaited(_toggleAutoJoin(value)),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notifications'),
              subtitle: const Text(
                'Override the global notification rules for this channel.',
              ),
              trailing: DropdownButton<ChannelNotificationRule>(
                key: const Key('channel-settings-notification-rule'),
                value: widget.controller.notificationRuleFor(widget.tab.name),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  unawaited(
                    widget.controller.setChannelNotificationRule(
                      widget.tab.name,
                      value,
                    ),
                  );
                  setState(() {});
                },
                items: ChannelNotificationRule.values
                    .map(
                      (rule) => DropdownMenuItem(
                        value: rule,
                        child: Text(channelNotificationRuleLabel(rule)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 8),
            Text('Channel note', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              key: const Key('channel-settings-note'),
              controller: _noteController,
              enabled: _noteLoaded,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Notes for this channel (stored only on this device)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                key: const Key('channel-settings-save-note'),
                onPressed: _noteLoaded ? () => unawaited(_saveNote()) : null,
                child: const Text('Save note'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Recent log (${recent.length})',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              const Text('No messages yet.')
            else
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final message in recent)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          _logLine(message),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _logLine(IrcMessage message) {
    final time = message.timestamp.toLocal();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '[$hh:$mm] ${message.sender}: ${stripIrcFormatting(message.content)}';
  }
}
