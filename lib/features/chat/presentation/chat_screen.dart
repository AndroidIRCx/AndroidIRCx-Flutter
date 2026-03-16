import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
  });

  final ChatSessionController controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();

  ChatSessionController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_controller.activeTab.name),
                Text(
                  _controller.activeTab.type == ChatTabType.channel &&
                          _controller.activeChannelSummary.isNotEmpty
                      ? _controller.activeChannelSummary
                      : _statusText(_controller.connection),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              if (_controller.activeTab.type == ChatTabType.channel)
                Builder(
                  builder: (context) {
                    return IconButton(
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                      icon: const Icon(Icons.people_outline),
                      tooltip: 'Nick list',
                    );
                  },
                ),
              IconButton(
                onPressed: _showJoinDialog,
                icon: const Icon(Icons.tag),
                tooltip: 'Join channel',
              ),
              IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
                tooltip: 'Settings',
              ),
              IconButton(
                onPressed: _controller.connection.phase == ConnectionPhase.connected
                    ? _controller.disconnect
                    : _controller.start,
                icon: Icon(
                  _controller.connection.phase == ConnectionPhase.connected
                      ? Icons.link_off
                      : Icons.wifi_tethering,
                ),
                tooltip: _controller.connection.phase == ConnectionPhase.connected
                    ? 'Disconnect'
                    : 'Connect',
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  ListTile(
                    title: Text(_controller.network.name),
                    subtitle:
                        Text('${_controller.network.host}:${_controller.network.port}'),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _controller.tabs.length,
                      itemBuilder: (context, index) {
                        final tab = _controller.tabs[index];
                        final selected = tab.id == _controller.activeTabId;
                        return ListTile(
                          selected: selected,
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(_iconForTab(tab.type)),
                              if (tab.hasActivity)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(tab.name),
                          trailing: tab.type == ChatTabType.server
                              ? null
                              : IconButton(
                                  onPressed: () => _controller.closeTab(tab.id),
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: 'Close tab',
                                ),
                          onTap: () {
                            _controller.selectTab(tab.id);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          endDrawer: _controller.activeTab.type == ChatTabType.channel
              ? Drawer(
                  child: SafeArea(
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(_controller.activeTab.name),
                          subtitle: Text(
                            '${_controller.activeChannelUsers.length} users',
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: _controller.activeChannelUsers.isEmpty
                              ? const Center(child: Text('No nick list yet.'))
                              : ListView.builder(
                                  itemCount: _controller.activeChannelUsers.length,
                                  itemBuilder: (context, index) {
                                    final nick = _controller.activeChannelUsers[index];
                                    return ListTile(
                                      leading: const Icon(Icons.person_outline),
                                      title: Text(nick),
                                      onTap: () {
                                        _composerController.text = '/whois $nick';
                                        Navigator.of(context).pop();
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            child: Column(
              children: [
                _ConnectionBanner(
                  controller: _controller,
                  network: _controller.network,
                ),
                if ((_controller.activeChannelTopic ?? '').trim().isNotEmpty)
                  _ChannelTopicBar(topic: _controller.activeChannelTopic!.trim()),
                Expanded(
                  child: _MessageList(messages: _controller.activeMessages),
                ),
                if (_controller.commandHistory.isNotEmpty)
                  _CommandHistoryBar(
                    entries: _controller.commandHistory,
                    onSelect: (value) => setState(() => _composerController.text = value),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composerController,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: _controller.activeTab.type == ChatTabType.server
                                ? 'Type raw IRC or /join #channel'
                                : 'Message ${_controller.activeTab.name}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _submit,
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showJoinDialog() async {
    final result = await showDialog<JoinChannelRequest>(
      context: context,
      builder: (context) {
        return const JoinChannelDialog();
      },
    );

    if (result != null) {
      await _controller.joinChannel(result);
    }
  }

  void _submit() {
    final text = _composerController.text;
    _composerController.clear();
    _controller.handleComposerSubmit(text);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(),
      ),
    );
    await _controller.reloadSettings();
  }

  String _statusText(ConnectionSnapshot snapshot) {
    switch (snapshot.phase) {
      case ConnectionPhase.idle:
        return 'Idle';
      case ConnectionPhase.connecting:
        return snapshot.message ?? 'Connecting';
      case ConnectionPhase.connected:
        return 'Connected';
      case ConnectionPhase.disconnecting:
        return 'Disconnecting';
      case ConnectionPhase.disconnected:
        return snapshot.message ?? 'Disconnected';
      case ConnectionPhase.error:
        return snapshot.message ?? 'Connection error';
    }
  }

  IconData _iconForTab(ChatTabType type) {
    switch (type) {
      case ChatTabType.server:
        return Icons.dns_outlined;
      case ChatTabType.channel:
        return Icons.tag;
      case ChatTabType.query:
        return Icons.alternate_email;
      case ChatTabType.notice:
        return Icons.info_outline;
    }
  }
}

class _ChannelTopicBar extends StatelessWidget {
  const _ChannelTopicBar({
    required this.topic,
  });

  final String topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(
        topic,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _CommandHistoryBar extends StatelessWidget {
  const _CommandHistoryBar({
    required this.entries,
    required this.onSelect,
  });

  final List<CommandHistoryEntry> entries;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = entries.take(5).toList(growable: false);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = items[index];
          return ActionChip(
            label: Text(
              entry.command,
              style: theme.textTheme.labelMedium,
            ),
            onPressed: () => onSelect(entry.command),
          );
        },
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
  });

  final List<IrcMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Text('No messages yet.'),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        final align = message.isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start;
        final bubbleColor = message.isOwn
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.white;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: align,
            children: [
              Text(
                message.sender,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 3),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(message.content),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.controller,
    required this.network,
  });

  final ChatSessionController controller;
  final NetworkConfig network;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.connection;
    final reconnectDelay = controller.pendingReconnectDelay;
    final theme = Theme.of(context);

    if (snapshot.phase == ConnectionPhase.connected &&
        reconnectDelay == null &&
        snapshot.message == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconForPhase(snapshot.phase),
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _titleForPhase(snapshot, reconnectDelay),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${network.host}:${network.port} • ${network.useTls ? 'TLS' : 'Plain TCP'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Current nick: ${controller.currentNick}',
            style: theme.textTheme.bodySmall,
          ),
          if ((snapshot.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(snapshot.message!, style: theme.textTheme.bodySmall),
          ],
          if (snapshot.phase == ConnectionPhase.error ||
              snapshot.phase == ConnectionPhase.disconnected) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: controller.reconnectNow,
                  child: const Text('Reconnect now'),
                ),
                if (reconnectDelay != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Auto retry in ${reconnectDelay.inSeconds}s',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _titleForPhase(ConnectionSnapshot snapshot, Duration? reconnectDelay) {
    switch (snapshot.phase) {
      case ConnectionPhase.idle:
        return 'Session idle';
      case ConnectionPhase.connecting:
        return 'Connecting';
      case ConnectionPhase.connected:
        return 'Connected';
      case ConnectionPhase.disconnecting:
        return 'Disconnecting';
      case ConnectionPhase.disconnected:
        return reconnectDelay == null ? 'Disconnected' : 'Disconnected, retry scheduled';
      case ConnectionPhase.error:
        return reconnectDelay == null ? 'Connection error' : 'Connection error, retry scheduled';
    }
  }

  IconData _iconForPhase(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return Icons.pause_circle_outline;
      case ConnectionPhase.connecting:
        return Icons.sync;
      case ConnectionPhase.connected:
        return Icons.check_circle_outline;
      case ConnectionPhase.disconnecting:
        return Icons.link_off;
      case ConnectionPhase.disconnected:
        return Icons.portable_wifi_off;
      case ConnectionPhase.error:
        return Icons.error_outline;
    }
  }
}
