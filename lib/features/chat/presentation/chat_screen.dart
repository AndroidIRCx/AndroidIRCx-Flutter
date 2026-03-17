import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:androidircx/irc/parser/message_content_parser.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final TextEditingController _messageSearchController = TextEditingController();
  bool _messageSearchVisible = false;
  _HistoryKindFilter _messageSearchFilter = _HistoryKindFilter.all;

  ChatSessionController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _composerController.dispose();
    _messageSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final visibleMessages = _messageSearchVisible
            ? _controller.messagesForTab(
                _controller.activeTabId,
                query: _messageSearchController.text,
                kinds: _messageSearchFilter.kinds,
              )
            : _controller.activeMessages;
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
              if (_controller.settings.showHeaderSearchButton)
                IconButton(
                  onPressed: _toggleMessageSearch,
                  icon: Icon(_messageSearchVisible ? Icons.search_off : Icons.search),
                  tooltip: _messageSearchVisible ? 'Close search' : 'Search messages',
                ),
              IconButton(
                onPressed: _openHistoryTools,
                icon: const Icon(Icons.history),
                tooltip: 'History tools',
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
                if (_messageSearchVisible)
                  _InlineMessageSearchBar(
                    controller: _messageSearchController,
                    filter: _messageSearchFilter,
                    resultCount: visibleMessages.length,
                    onFilterChanged: (filter) => setState(() => _messageSearchFilter = filter),
                    onChanged: (_) => setState(() {}),
                    onClose: _toggleMessageSearch,
                  ),
                if ((_controller.activeChannelTopic ?? '').trim().isNotEmpty)
                  _ChannelTopicBar(topic: _controller.activeChannelTopic!.trim()),
                if (_controller.activeTab.type == ChatTabType.server)
                  _ServiceQuickActions(
                    onRun: (service, command) async {
                      await _controller.sendServiceShortcut(service, command);
                    },
                  ),
                Expanded(
                  child: _MessageList(
                    messages: visibleMessages,
                    showAttachmentPreviews: _controller.settings.showAttachmentPreviews,
                    onQuoteMessage: (message) =>
                        _insertIntoComposer('> ${stripIrcFormatting(message.content)}'),
                    onReplyWithNick: (message) {
                      final prefix =
                          message.sender == _controller.currentNick ? '' : '${message.sender}: ';
                      _insertIntoComposer(prefix);
                    },
                  ),
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

  Future<void> _openHistoryTools() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HistoryToolsSheet(controller: _controller),
    );
  }

  void _toggleMessageSearch() {
    setState(() {
      if (_messageSearchVisible) {
        _messageSearchVisible = false;
        _messageSearchController.clear();
        _messageSearchFilter = _HistoryKindFilter.all;
      } else {
        _messageSearchVisible = true;
      }
    });
  }

  void _insertIntoComposer(String text) {
    final existing = _composerController.text;
    final next = existing.isEmpty ? text : '$existing $text';
    setState(() {
      _composerController.text = next;
      _composerController.selection = TextSelection.collapsed(offset: next.length);
    });
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

class _InlineMessageSearchBar extends StatelessWidget {
  const _InlineMessageSearchBar({
    required this.controller,
    required this.filter,
    required this.resultCount,
    required this.onFilterChanged,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final _HistoryKindFilter filter;
  final int resultCount;
  final ValueChanged<_HistoryKindFilter> onFilterChanged;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      labelText: 'Search current tab',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close message search',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _HistoryKindFilter.values
                        .map(
                          (item) => ChoiceChip(
                            label: Text(item.label),
                            selected: filter == item,
                            onSelected: (_) => onFilterChanged(item),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$resultCount matches',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryToolsSheet extends StatefulWidget {
  const _HistoryToolsSheet({
    required this.controller,
  });

  final ChatSessionController controller;

  @override
  State<_HistoryToolsSheet> createState() => _HistoryToolsSheetState();
}

class _HistoryToolsSheetState extends State<_HistoryToolsSheet> {
  final TextEditingController _searchController = TextEditingController();
  _HistoryKindFilter _filter = _HistoryKindFilter.all;

  ChatSessionController get _controller => widget.controller;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _controller.messagesForTab(
      _controller.activeTabId,
      query: _searchController.text,
      kinds: _filter.kinds,
    );
    final exportText = _controller.exportTabHistory(
      _controller.activeTabId,
      query: _searchController.text,
      kinds: _filter.kinds,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'History tools',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search current tab history',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _HistoryKindFilter.values
                  .map(
                    (filter) => ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            if (_controller.activeTab.type != ChatTabType.server) ...[
              Text(
                'Server playback',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _controller.canRequestServerHistory
                        ? () => _requestRecentHistory(context, 25)
                        : null,
                    child: const Text('Recent 25'),
                  ),
                  FilledButton.tonal(
                    onPressed: _controller.canRequestServerHistory
                        ? () => _requestRecentHistory(context, 100)
                        : null,
                    child: const Text('Recent 100'),
                  ),
                  OutlinedButton(
                    onPressed: _controller.canRequestOlderServerHistory
                        ? () => _requestOlderHistory(context, 50)
                        : null,
                    child: const Text('Older 50'),
                  ),
                  OutlinedButton(
                    onPressed: _controller.canRequestNewerServerHistory
                        ? () => _requestNewerHistory(context, 50)
                        : null,
                    child: const Text('Newer 50'),
                  ),
                  OutlinedButton(
                    onPressed: _controller.canRequestNewerServerHistory
                        ? () => _requestAroundHistory(context, 50)
                        : null,
                    child: const Text('Around latest'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '${messages.length} matching messages',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: messages.isEmpty
                    ? const Center(child: Text('No history matches this filter.'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(message.sender),
                            subtitle: Text(
                              message.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: exportText.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: exportText));
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('History copied to clipboard.')),
                            );
                          },
                    icon: const Icon(Icons.copy_all),
                    label: const Text('Copy export'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestRecentHistory(BuildContext context, int limit) async {
    final success = await _controller.requestRecentHistory(limit: limit);
    if (!mounted || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Requested recent history ($limit messages).'
              : 'Unable to request server history.',
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _requestOlderHistory(BuildContext context, int limit) async {
    final success = await _controller.requestOlderHistory(limit: limit);
    if (!mounted || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Requested older history ($limit messages).'
              : 'Unable to request older history.',
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _requestNewerHistory(BuildContext context, int limit) async {
    final success = await _controller.requestNewerHistory(limit: limit);
    if (!mounted || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Requested newer history ($limit messages).'
              : 'Unable to request newer history.',
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _requestAroundHistory(BuildContext context, int limit) async {
    final success = await _controller.requestAroundLatestHistory(limit: limit);
    if (!mounted || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Requested surrounding history ($limit messages).'
              : 'Unable to request surrounding history.',
        ),
      ),
    );
    setState(() {});
  }
}

enum _HistoryKindFilter {
  all('All', <IrcMessageKind>{}),
  chat('Chat', <IrcMessageKind>{IrcMessageKind.chat}),
  system('System', <IrcMessageKind>{IrcMessageKind.system}),
  raw('Raw', <IrcMessageKind>{IrcMessageKind.raw});

  const _HistoryKindFilter(this.label, this.kinds);

  final String label;
  final Set<IrcMessageKind> kinds;
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
      child: _IrcFormattedText(
        topic,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        baseStyle: Theme.of(context).textTheme.bodySmall,
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

class _ServiceQuickActions extends StatelessWidget {
  const _ServiceQuickActions({
    required this.onRun,
  });

  final Future<void> Function(String service, String command) onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const actions = <(String, String, String)>[
      ('NickServ', 'HELP', 'NickServ HELP'),
      ('ChanServ', 'HELP', 'ChanServ HELP'),
      ('HostServ', 'HELP', 'HostServ HELP'),
      ('MemoServ', 'HELP', 'MemoServ HELP'),
      ('BotServ', 'HELP', 'BotServ HELP'),
      ('OperServ', 'HELP', 'OperServ HELP'),
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            label: Text(
              action.$3,
              style: theme.textTheme.labelMedium,
            ),
            onPressed: () => onRun(action.$1, action.$2),
          );
        },
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.showAttachmentPreviews,
    required this.onQuoteMessage,
    required this.onReplyWithNick,
  });

  final List<IrcMessage> messages;
  final bool showAttachmentPreviews;
  final ValueChanged<IrcMessage> onQuoteMessage;
  final ValueChanged<IrcMessage> onReplyWithNick;

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
        final bubbleColor = switch (message.kind) {
          IrcMessageKind.system => const Color(0xFFF6F8F1),
          IrcMessageKind.raw => const Color(0xFFF7F7FA),
          IrcMessageKind.chat => message.isOwn
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.white,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: align,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.sender,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (message.isPlayback) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'History',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              GestureDetector(
                onLongPress: () => _showMessageActions(context, message),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: message.isPlayback
                        ? bubbleColor.withValues(alpha: 0.88)
                        : bubbleColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IrcFormattedText(
                          message.content,
                          baseStyle: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (showAttachmentPreviews)
                          _MessageAttachments(content: message.content),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMessageActions(BuildContext context, IrcMessage message) async {
    final urls = extractUrls(stripIrcFormatting(message.content));
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy clean text'),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: stripIrcFormatting(message.content)),
                    );
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Copy raw text'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: message.content));
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Copy sender'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: message.sender));
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                ),
                if (urls.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Copy first link'),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: urls.first));
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    },
                  ),
                if (urls.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Open first link'),
                    onTap: () async {
                      await _openExternalUrl(urls.first);
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.format_quote),
                  title: const Text('Quote in composer'),
                  onTap: () {
                    onQuoteMessage(message);
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Reply with nick'),
                  onTap: () {
                    onReplyWithNick(message);
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IrcFormattedText extends StatelessWidget {
  const _IrcFormattedText(
    this.text, {
    this.baseStyle,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? baseStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final segments = parseIrcTextWithLinks(text);
    if (segments.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return Text.rich(
      TextSpan(
        children: segments
            .map(
              (segment) => TextSpan(
                text: segment.text,
                style: _resolveTextStyle(baseStyle, segment),
                recognizer: segment.isLink
                    ? (TapGestureRecognizer()..onTap = () => _openExternalUrl(segment.url!))
                    : null,
              ),
            )
            .toList(growable: false),
      ),
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  TextStyle _resolveTextStyle(TextStyle? base, IrcLinkSegment segment) {
    final style = segment.style;
    var foreground = style.color;
    var background = style.background;

    if (style.reverse && foreground != null && background != null) {
      final swappedForeground = background;
      background = foreground;
      foreground = swappedForeground;
    } else if (style.reverse && foreground != null) {
      background = foreground;
      foreground = null;
    } else if (style.reverse && background != null) {
      foreground = background;
      background = null;
    }

    var textStyle = base ?? const TextStyle();
    final foregroundHex = foreground == null ? null : getIrcColorHex(foreground);
    final backgroundHex = background == null ? null : getIrcColorHex(background);

    if (foregroundHex != null) {
      textStyle = textStyle.copyWith(color: _parseHexColor(foregroundHex));
    }
    if (backgroundHex != null) {
      textStyle = textStyle.copyWith(backgroundColor: _parseHexColor(backgroundHex));
    }
    if (style.bold) {
      textStyle = textStyle.copyWith(fontWeight: FontWeight.bold);
    }
    if (style.italic) {
      textStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
    }

    final decorations = <TextDecoration>{};
    if (style.underline || segment.isLink) {
      decorations.add(TextDecoration.underline);
    }
    if (style.strikethrough) {
      decorations.add(TextDecoration.lineThrough);
    }
    if (decorations.isNotEmpty) {
      textStyle = textStyle.copyWith(
        decoration: TextDecoration.combine(decorations.toList(growable: false)),
      );
    }

    if (segment.isLink && foregroundHex == null) {
      textStyle = textStyle.copyWith(color: const Color(0xFF1565C0));
    }

    return textStyle;
  }

  Color _parseHexColor(String value) {
    final normalized = value.replaceFirst('#', '');
    return Color(int.parse('FF$normalized', radix: 16));
  }
}

class _MessageAttachments extends StatelessWidget {
  const _MessageAttachments({
    required this.content,
  });

  final String content;

  @override
  Widget build(BuildContext context) {
    final parts = parseMessageContent(stripIrcFormatting(content));
    final previews = parts
        .where((part) => part.type != ParsedMessagePartType.text)
        .toList(growable: false);
    if (previews.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: previews
            .map((part) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AttachmentCard(part: part),
                ))
            .toList(growable: false),
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.part,
  });

  final ParsedMessagePart part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = part.url;
    final isImage = part.type == ParsedMessagePartType.image && url != null;
    final title = switch (part.type) {
      ParsedMessagePartType.image => 'Image',
      ParsedMessagePartType.media => 'Encrypted media',
      ParsedMessagePartType.url => 'Link',
      ParsedMessagePartType.text => 'Text',
    };
    final icon = switch (part.type) {
      ParsedMessagePartType.image => Icons.image_outlined,
      ParsedMessagePartType.media => Icons.lock_outline,
      ParsedMessagePartType.url when url != null && isVideoUrl(url) => Icons.movie_outlined,
      ParsedMessagePartType.url when url != null && isAudioUrl(url) => Icons.audiotrack_outlined,
      ParsedMessagePartType.url when url != null && isDownloadableFileUrl(url) => Icons.download_outlined,
      ParsedMessagePartType.url => Icons.link,
      ParsedMessagePartType.text => Icons.notes,
    };

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: url == null
            ? null
            : () => isImage ? _showImagePreview(context, url) : _openExternalUrl(url),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isImage) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 120,
                      alignment: Alignment.center,
                      color: theme.colorScheme.surfaceContainer,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) {
                        return child;
                      }
                      return Container(
                        height: 120,
                        alignment: Alignment.center,
                        color: theme.colorScheme.surfaceContainer,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.labelLarge,
                        ),
                        Text(
                          part.mediaId ?? part.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (url != null)
                    IconButton(
                      onPressed: () => _copyToClipboard(context, url),
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: 'Copy link',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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

Future<void> _openExternalUrl(String rawUrl) async {
  final normalized = rawUrl.contains('://') ? rawUrl : 'https://$rawUrl';
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    return;
  }

  await launchUrl(uri, mode: LaunchMode.platformDefault);
}

Future<void> _copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Copied to clipboard.')),
  );
}

Future<void> _showImagePreview(BuildContext context, String url) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close image preview',
              ),
            ),
          ],
        ),
      );
    },
  );
}
