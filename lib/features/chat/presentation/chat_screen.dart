import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/dcc/services/dcc_file_picker.dart';
import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:androidircx/irc/parser/message_content_parser.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:androidircx/media/services/media_download_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    this.filePicker,
    this.mediaDownloadService,
  });

  final ChatSessionController controller;
  final DccFilePicker? filePicker;
  final MediaDownloadService? mediaDownloadService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();
  final TextEditingController _messageSearchController =
      TextEditingController();
  List<CommandSuggestion> _composerSuggestions = const [];
  List<ComposerAutocompleteSuggestion> _autocompleteSuggestions = const [];
  bool _messageSearchVisible = false;
  _HistoryKindFilter _messageSearchFilter = _HistoryKindFilter.all;
  IrcMessage? _pendingReplyMessage;

  ChatSessionController get _controller => widget.controller;
  DccFilePicker get _filePicker =>
      widget.filePicker ?? const MethodChannelDccFilePicker();
  MediaDownloadService get _mediaDownloadService =>
      widget.mediaDownloadService ?? createMediaDownloadService();

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
                      : _controller.activeTab.type == ChatTabType.dcc &&
                            _controller.activeDccSession != null
                      ? _dccSummary(_controller.activeDccSession!)
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
                  icon: Icon(
                    _messageSearchVisible ? Icons.search_off : Icons.search,
                  ),
                  tooltip: _messageSearchVisible
                      ? 'Close search'
                      : 'Search messages',
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
                onPressed:
                    _controller.connection.phase == ConnectionPhase.connected
                    ? _controller.disconnect
                    : _controller.start,
                icon: Icon(
                  _controller.connection.phase == ConnectionPhase.connected
                      ? Icons.link_off
                      : Icons.wifi_tethering,
                ),
                tooltip:
                    _controller.connection.phase == ConnectionPhase.connected
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
                    subtitle: Text(
                      '${_controller.network.host}:${_controller.network.port}',
                    ),
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
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
                                  itemCount: _controller
                                      .activeChannelUserDetails
                                      .length,
                                  itemBuilder: (context, index) {
                                    final entry = _controller
                                        .activeChannelUserDetails[index];
                                    final nick = entry.nick;
                                    return ListTile(
                                      leading: const Icon(Icons.person_outline),
                                      title: Text(nick),
                                      subtitle: entry.details.isEmpty
                                          ? null
                                          : Text(entry.details),
                                      onTap: () {
                                        _composerController.text =
                                            '/whois $nick';
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
                    onFilterChanged: (filter) =>
                        setState(() => _messageSearchFilter = filter),
                    onChanged: (_) => setState(() {}),
                    onClose: _toggleMessageSearch,
                  ),
                if ((_controller.activeChannelTopic ?? '').trim().isNotEmpty)
                  _ChannelTopicBar(
                    topic: _controller.activeChannelTopic!.trim(),
                  ),
                if (_controller.activeTab.type == ChatTabType.dcc &&
                    _controller.activeDccSession != null)
                  _DccSessionBanner(
                    session: _controller.activeDccSession!,
                    onAccept: _controller.acceptActiveDccSession,
                    onDecline: _controller.declineActiveDccSession,
                    onClose: _controller.closeActiveDccSession,
                  ),
                if (_controller.activeTab.type == ChatTabType.server)
                  _ServiceQuickActions(
                    onRun: (service, command) async {
                      await _controller.sendServiceShortcut(service, command);
                    },
                  ),
                Expanded(
                  child: _MessageList(
                    messages: visibleMessages,
                    showAttachmentPreviews:
                        _controller.settings.showAttachmentPreviews,
                    resolveReplyTarget: (replyId) => _controller.messageByMsgId(
                      _controller.activeTabId,
                      replyId,
                    ),
                    resolveReactions: _controller.reactionsForMessage,
                    onRedactMessage: _controller.redactMessage,
                    onQuoteMessage: (message) => _insertIntoComposer(
                      '> ${stripIrcFormatting(message.content)}',
                    ),
                    onReplyWithNick: (message) {
                      final prefix = message.sender == _controller.currentNick
                          ? ''
                          : '${message.sender}: ';
                      _insertIntoComposer(prefix);
                    },
                    onReplyToMessage: _setPendingReply,
                    onDownloadAttachment: _downloadAttachment,
                  ),
                ),
                if (_controller.commandHistory.isNotEmpty)
                  _CommandHistoryBar(
                    entries: _controller.commandHistory,
                    onSelect: (value) =>
                        setState(() => _composerController.text = value),
                  ),
                if (_controller.activeTypingUsers.isNotEmpty)
                  _TypingIndicator(users: _controller.activeTypingUsers),
                if (_pendingReplyMessage != null)
                  _PendingReplyBar(
                    message: _pendingReplyMessage!,
                    onCancel: () => setState(() => _pendingReplyMessage = null),
                  ),
                const Divider(height: 1),
                _ComposerArea(
                  suggestions: _composerSuggestions,
                  autocompleteSuggestions: _autocompleteSuggestions,
                  controller: _composerController,
                  hintText: _controller.activeTab.type == ChatTabType.server
                      ? 'Type raw IRC or /join #channel'
                      : _controller.activeTab.type == ChatTabType.dcc
                      ? (_controller.activeDccSession?.type ==
                                DccSessionType.chat
                            ? 'Type DCC chat message'
                            : 'DCC SEND tabs do not accept messages')
                      : 'Message ${_controller.activeTab.name}',
                  onChanged: _handleComposerChanged,
                  onSubmitted: _submit,
                  canSendDccFile:
                      _controller.activeTab.type == ChatTabType.query,
                  onPickDccFile: _pickAndSendDccFile,
                  onSuggestionSelected: _applyComposerSuggestion,
                  onAutocompleteSelected: _applyAutocompleteSuggestion,
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
    final replyTo = _pendingReplyMessage?.tags['msgid'];
    setState(() {
      _pendingReplyMessage = null;
      _composerSuggestions = const [];
      _autocompleteSuggestions = const [];
    });
    _controller.handleComposerSubmit(text, replyTo: replyTo);
  }

  Future<void> _pickAndSendDccFile() async {
    final targetTab = _controller.activeTab;
    if (targetTab.type != ChatTabType.query) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open a private query tab before sending DCC files.'),
        ),
      );
      return;
    }

    try {
      final filePath = await _filePicker.pickFile();
      if (!mounted || filePath == null) {
        return;
      }
      await _controller.sendDccFileToNick(
        nick: targetTab.name,
        filePath: filePath,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to send DCC file: $error')),
      );
    }
  }

  Future<void> _downloadAttachment(IrcMessageAttachment attachment) async {
    final url = attachment.uri;
    if (url == null || url.trim().isEmpty) {
      return;
    }
    try {
      final result = await _mediaDownloadService.download(
        url,
        directoryPath: _controller.settings.mediaDownloadDirectoryPath,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloaded ${result.fileName} (${_formatByteCount(result.bytesDownloaded)}).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to download media: $error')),
      );
    }
  }

  void _handleComposerChanged(String value) {
    _controller.updateTypingState(value);
    final autocompleteSuggestions = _controller
        .autocompleteSuggestionsForComposer(
          value,
          cursorOffset: _composerController.selection.baseOffset,
        );
    final commandSuggestions = autocompleteSuggestions.isEmpty
        ? _controller.commandSuggestionsForComposer(value)
        : const <CommandSuggestion>[];
    setState(() {
      _composerSuggestions = commandSuggestions;
      _autocompleteSuggestions = autocompleteSuggestions;
    });
  }

  void _applyComposerSuggestion(CommandSuggestion suggestion) {
    final current = _composerController.text;
    final next = suggestion.source == CommandSuggestionSource.history
        ? suggestion.text
        : _replaceFirstComposerToken(current, suggestion.text);
    setState(() {
      _composerController.text = next;
      _composerController.selection = TextSelection.collapsed(
        offset: next.length,
      );
      _composerSuggestions = const [];
      _autocompleteSuggestions = const [];
    });
    _controller.updateTypingState(next);
  }

  void _applyAutocompleteSuggestion(ComposerAutocompleteSuggestion suggestion) {
    final next = _controller.applyComposerAutocompleteSuggestion(
      _composerController.text,
      suggestion,
    );
    setState(() {
      _composerController.text = next;
      _composerController.selection = TextSelection.collapsed(
        offset: (suggestion.tokenStart + suggestion.text.length + 1).clamp(
          0,
          next.length,
        ),
      );
      _autocompleteSuggestions = const [];
      _composerSuggestions = const [];
    });
    _controller.updateTypingState(next);
  }

  String _replaceFirstComposerToken(String current, String replacement) {
    final leading = current.length - current.trimLeft().length;
    final restStart = current.indexOf(RegExp(r'\s'), leading);
    if (restStart == -1) {
      return '${current.substring(0, leading)}$replacement ';
    }
    return '${current.substring(0, leading)}$replacement${current.substring(restStart)}';
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
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
      _composerController.selection = TextSelection.collapsed(
        offset: next.length,
      );
    });
  }

  void _setPendingReply(IrcMessage message) {
    setState(() {
      _pendingReplyMessage = message.tags['msgid'] == null ? null : message;
    });
  }

  String _statusText(ConnectionSnapshot snapshot) {
    switch (snapshot.phase) {
      case ConnectionPhase.idle:
        return 'Idle';
      case ConnectionPhase.connecting:
        return snapshot.message ?? 'Connecting';
      case ConnectionPhase.registering:
        return snapshot.message ?? 'Registering';
      case ConnectionPhase.authenticating:
        return snapshot.message ?? 'Authenticating';
      case ConnectionPhase.connected:
        return 'Connected';
      case ConnectionPhase.reconnecting:
        return snapshot.message ?? 'Reconnecting';
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
      case ChatTabType.dcc:
        return Icons.swap_horiz;
    }
  }

  String _dccSummary(DccSession session) {
    final status = session.status.name;
    return switch (session.type) {
      DccSessionType.chat =>
        '${session.direction} chat • ${session.host ?? '?'}:${session.port ?? 0} • $status',
      DccSessionType.send =>
        '${session.direction}${session.isReverse ? ' reverse' : ''} file • ${_formatDccTransferProgress(session)} • $status',
      DccSessionType.unknown => '${session.direction} DCC • $status',
    };
  }
}

String _dccTransferSubtitle(DccSession session) {
  final parts = <String>[
    'File: ${session.filename ?? 'file'}',
    _formatDccTransferProgress(session),
    session.status.name,
  ];
  final speed = session.bytesPerSecond;
  if (_isActiveDccTransfer(session) && speed != null && speed > 0) {
    parts.add('${_formatByteRate(speed)}/s');
  }
  final eta = session.estimatedRemaining;
  if (_isActiveDccTransfer(session) && eta != null && eta > Duration.zero) {
    parts.add('ETA ${_formatDurationShort(eta)}');
  }
  if (session.isReverse) {
    parts.add('reverse');
  }
  if (session.resumeOffset > 0) {
    parts.add('resume ${_formatByteCount(session.resumeOffset)}');
  }
  return parts.join(' • ');
}

String _formatDccTransferProgress(DccSession session) {
  final transferred = session.bytesTransferred;
  final total = session.size;
  if (total != null && total > 0) {
    final percent = ((transferred / total) * 100).clamp(0, 100);
    return '${_formatByteCount(transferred)} / ${_formatByteCount(total)} (${percent.toStringAsFixed(0)}%)';
  }
  if (transferred > 0) {
    return _formatByteCount(transferred);
  }
  return _formatByteCount(total ?? 0);
}

String _formatByteCount(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final display = value >= 10 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$display ${units[unit]}';
}

String _formatByteRate(double bytesPerSecond) {
  return _formatByteCount(bytesPerSecond);
}

String _formatDurationShort(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) {
    return '${seconds}s';
  }
  final minutes = duration.inMinutes;
  if (minutes < 60) {
    return '${minutes}m ${seconds % 60}s';
  }
  return '${duration.inHours}h ${minutes % 60}m';
}

bool _isActiveDccTransfer(DccSession session) {
  return session.status == DccSessionStatus.offering ||
      session.status == DccSessionStatus.connecting ||
      session.status == DccSessionStatus.connected;
}

class _ComposerArea extends StatelessWidget {
  const _ComposerArea({
    required this.suggestions,
    required this.autocompleteSuggestions,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onSubmitted,
    required this.canSendDccFile,
    required this.onPickDccFile,
    required this.onSuggestionSelected,
    required this.onAutocompleteSelected,
  });

  final List<CommandSuggestion> suggestions;
  final List<ComposerAutocompleteSuggestion> autocompleteSuggestions;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final bool canSendDccFile;
  final VoidCallback onPickDccFile;
  final ValueChanged<CommandSuggestion> onSuggestionSelected;
  final ValueChanged<ComposerAutocompleteSuggestion> onAutocompleteSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (suggestions.isNotEmpty)
          _CommandSuggestionsPanel(
            suggestions: suggestions,
            onSelect: onSuggestionSelected,
          ),
        if (suggestions.isEmpty && autocompleteSuggestions.isNotEmpty)
          _AutocompleteSuggestionsPanel(
            suggestions: autocompleteSuggestions,
            onSelect: onAutocompleteSelected,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmitted(),
                  decoration: InputDecoration(hintText: hintText),
                ),
              ),
              const SizedBox(width: 12),
              if (canSendDccFile) ...[
                IconButton(
                  onPressed: onPickDccFile,
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Send DCC file',
                ),
                const SizedBox(width: 8),
              ],
              FilledButton(onPressed: onSubmitted, child: const Text('Send')),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommandSuggestionsPanel extends StatelessWidget {
  const _CommandSuggestionsPanel({
    required this.suggestions,
    required this.onSelect,
  });

  final List<CommandSuggestion> suggestions;
  final ValueChanged<CommandSuggestion> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            final isAlias = suggestion.source == CommandSuggestionSource.alias;
            final isHistory =
                suggestion.source == CommandSuggestionSource.history;
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                isHistory
                    ? Icons.history
                    : isAlias
                    ? Icons.flash_on_outlined
                    : Icons.terminal,
                size: 18,
                color: isAlias ? theme.colorScheme.primary : null,
              ),
              title: Row(
                children: [
                  Text(suggestion.text),
                  if (isAlias || isHistory) ...[
                    const SizedBox(width: 8),
                    InputChip(
                      label: Text(isAlias ? 'alias' : 'history'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ],
              ),
              subtitle: (suggestion.description ?? suggestion.usage) == null
                  ? null
                  : Text(
                      suggestion.description ?? suggestion.usage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => onSelect(suggestion),
            );
          },
        ),
      ),
    );
  }
}

class _AutocompleteSuggestionsPanel extends StatelessWidget {
  const _AutocompleteSuggestionsPanel({
    required this.suggestions,
    required this.onSelect,
  });

  final List<ComposerAutocompleteSuggestion> suggestions;
  final ValueChanged<ComposerAutocompleteSuggestion> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            final isChannel =
                suggestion.type == ComposerAutocompleteSuggestionType.channel;
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                isChannel ? Icons.tag : Icons.person_outline,
                size: 18,
              ),
              title: Text(suggestion.text),
              subtitle: Text(isChannel ? 'channel' : 'nick'),
              onTap: () => onSelect(suggestion),
            );
          },
        ),
      ),
    );
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

class _PendingReplyBar extends StatelessWidget {
  const _PendingReplyBar({required this.message, required this.onCancel});

  final IrcMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${message.sender}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  stripIrcFormatting(message.content),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.users});

  final List<String> users;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (users.length) {
      0 => '',
      1 => '${users.first} is typing…',
      2 => '${users.first} and ${users.last} are typing…',
      _ =>
        '${users.first}, ${users[1]} and ${users.length - 2} more are typing…',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _DccSessionBanner extends StatelessWidget {
  const _DccSessionBanner({
    required this.session,
    required this.onAccept,
    required this.onDecline,
    required this.onClose,
  });

  final DccSession session;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = switch (session.type) {
      DccSessionType.chat =>
        'Peer: ${session.peerNick} • ${session.host ?? '?'}:${session.port ?? 0} • ${session.status.name}',
      DccSessionType.send => _dccTransferSubtitle(session),
      DccSessionType.unknown =>
        'Peer: ${session.peerNick} • ${session.status.name}',
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.type == DccSessionType.chat
                ? 'DCC CHAT session'
                : 'DCC transfer session',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (session.status == DccSessionStatus.pending)
                FilledButton.tonal(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              if (session.status == DccSessionStatus.pending)
                FilledButton.tonal(
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              if (session.status != DccSessionStatus.closed)
                FilledButton.tonal(
                  onPressed: onClose,
                  child: const Text('Close'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.referenced, required this.replyId});

  final IrcMessage? referenced;
  final String replyId;

  @override
  Widget build(BuildContext context) {
    final title = referenced == null
        ? 'Reply'
        : 'Reply to ${referenced!.sender}';
    final body = referenced == null
        ? 'Referenced message: $replyId'
        : stripIrcFormatting(referenced!.content);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HistoryToolsSheet extends StatefulWidget {
  const _HistoryToolsSheet({required this.controller});

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
                    ? const Center(
                        child: Text('No history matches this filter.'),
                      )
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
                            await Clipboard.setData(
                              ClipboardData(text: exportText),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('History copied to clipboard.'),
                              ),
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
  chat('Chat', <IrcMessageKind>{
    IrcMessageKind.chat,
    IrcMessageKind.action,
    IrcMessageKind.notice,
    IrcMessageKind.media,
  }),
  system('System', <IrcMessageKind>{
    IrcMessageKind.system,
    IrcMessageKind.error,
    IrcMessageKind.event,
  }),
  dcc('DCC', <IrcMessageKind>{IrcMessageKind.dcc}),
  raw('Raw', <IrcMessageKind>{IrcMessageKind.raw});

  const _HistoryKindFilter(this.label, this.kinds);

  final String label;
  final Set<IrcMessageKind> kinds;
}

class _ChannelTopicBar extends StatelessWidget {
  const _ChannelTopicBar({required this.topic});

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
  const _CommandHistoryBar({required this.entries, required this.onSelect});

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
            label: Text(entry.command, style: theme.textTheme.labelMedium),
            onPressed: () => onSelect(entry.command),
          );
        },
      ),
    );
  }
}

class _ServiceQuickActions extends StatelessWidget {
  const _ServiceQuickActions({required this.onRun});

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
            label: Text(action.$3, style: theme.textTheme.labelMedium),
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
    required this.resolveReplyTarget,
    required this.resolveReactions,
    required this.onRedactMessage,
    required this.onQuoteMessage,
    required this.onReplyWithNick,
    required this.onReplyToMessage,
    required this.onDownloadAttachment,
  });

  final List<IrcMessage> messages;
  final bool showAttachmentPreviews;
  final IrcMessage? Function(String replyId) resolveReplyTarget;
  final Map<String, int> Function(IrcMessage message) resolveReactions;
  final Future<bool> Function(IrcMessage message) onRedactMessage;
  final ValueChanged<IrcMessage> onQuoteMessage;
  final ValueChanged<IrcMessage> onReplyWithNick;
  final ValueChanged<IrcMessage> onReplyToMessage;
  final Future<void> Function(IrcMessageAttachment attachment)
  onDownloadAttachment;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(child: Text('No messages yet.'));
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        final align = message.isOwn
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start;
        final isRedacted = message.tags['redacted'] == 'true';
        final reactions = resolveReactions(message);
        final bubbleColor = switch (message.kind) {
          IrcMessageKind.system ||
          IrcMessageKind.event => const Color(0xFFF6F8F1),
          IrcMessageKind.error => const Color(0xFFFFEBEE),
          IrcMessageKind.dcc => const Color(0xFFEAF7F3),
          IrcMessageKind.raw => const Color(0xFFF7F7FA),
          IrcMessageKind.chat ||
          IrcMessageKind.action ||
          IrcMessageKind.notice ||
          IrcMessageKind.media =>
            message.isOwn
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((message.tags['draft/reply'] ?? '')
                            .trim()
                            .isNotEmpty)
                          _ReplyPreview(
                            referenced: resolveReplyTarget(
                              message.tags['draft/reply']!.trim(),
                            ),
                            replyId: message.tags['draft/reply']!.trim(),
                          ),
                        _IrcFormattedText(
                          message.content,
                          baseStyle: isRedacted
                              ? Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                )
                              : Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (showAttachmentPreviews && !isRedacted)
                          _MessageAttachments(
                            message: message,
                            onDownloadAttachment: onDownloadAttachment,
                          ),
                        if (reactions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: reactions.entries
                                .map(
                                  (entry) => Chip(
                                    label: Text('${entry.key} ${entry.value}'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ],
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

  Future<void> _showMessageActions(
    BuildContext context,
    IrcMessage message,
  ) async {
    final urls = extractUrls(stripIrcFormatting(message.content));
    final canRedact = (message.tags['msgid'] ?? '').trim().isNotEmpty;
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
                    await Clipboard.setData(
                      ClipboardData(text: message.content),
                    );
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
                    await Clipboard.setData(
                      ClipboardData(text: message.sender),
                    );
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
                  leading: const Icon(Icons.subdirectory_arrow_right),
                  title: const Text('Reply to message'),
                  onTap: () {
                    onReplyToMessage(message);
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
                if (canRedact)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Delete message'),
                    onTap: () async {
                      await onRedactMessage(message);
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
                    ? (TapGestureRecognizer()
                        ..onTap = () => _openExternalUrl(segment.url!))
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
    var foregroundHex =
        style.colorHex ??
        (style.color == null ? null : getIrcColorHex(style.color!));
    var backgroundHex =
        style.backgroundHex ??
        (style.background == null ? null : getIrcColorHex(style.background!));

    if (style.reverse && foregroundHex != null && backgroundHex != null) {
      final swappedForeground = backgroundHex;
      backgroundHex = foregroundHex;
      foregroundHex = swappedForeground;
    } else if (style.reverse && foregroundHex != null) {
      backgroundHex = foregroundHex;
      foregroundHex = null;
    } else if (style.reverse && backgroundHex != null) {
      foregroundHex = backgroundHex;
      backgroundHex = null;
    }

    var textStyle = base ?? const TextStyle();
    if (foregroundHex != null) {
      textStyle = textStyle.copyWith(color: _parseHexColor(foregroundHex));
    }
    if (backgroundHex != null) {
      textStyle = textStyle.copyWith(
        backgroundColor: _parseHexColor(backgroundHex),
      );
    }
    if (style.bold) {
      textStyle = textStyle.copyWith(fontWeight: FontWeight.bold);
    }
    if (style.italic) {
      textStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
    }
    if (style.monospace) {
      textStyle = textStyle.copyWith(fontFamily: 'monospace');
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
    required this.message,
    required this.onDownloadAttachment,
  });

  final IrcMessage message;
  final Future<void> Function(IrcMessageAttachment attachment)
  onDownloadAttachment;

  @override
  Widget build(BuildContext context) {
    final previews = message.attachments.isNotEmpty
        ? message.attachments
        : parseMessageContent(stripIrcFormatting(message.content))
              .where((part) => part.type != ParsedMessagePartType.text)
              .map(_attachmentFromParsedPart)
              .toList(growable: false);
    if (previews.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: previews
            .map(
              (attachment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AttachmentCard(
                  attachment: attachment,
                  onDownloadAttachment: onDownloadAttachment,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.attachment,
    required this.onDownloadAttachment,
  });

  final IrcMessageAttachment attachment;
  final Future<void> Function(IrcMessageAttachment attachment)
  onDownloadAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = attachment.uri;
    final isImage =
        attachment.type == IrcMessageAttachmentType.image && url != null;
    final title = attachment.label.trim().isNotEmpty
        ? attachment.label
        : switch (attachment.type) {
            IrcMessageAttachmentType.image => 'Image',
            IrcMessageAttachmentType.video => 'Video',
            IrcMessageAttachmentType.audio => 'Audio',
            IrcMessageAttachmentType.file => 'File',
            IrcMessageAttachmentType.media => 'Encrypted media',
            IrcMessageAttachmentType.dccChat => 'DCC CHAT',
            IrcMessageAttachmentType.dccSend => 'DCC SEND',
            IrcMessageAttachmentType.url => 'Link',
          };
    final icon = switch (attachment.type) {
      IrcMessageAttachmentType.image => Icons.image_outlined,
      IrcMessageAttachmentType.video => Icons.movie_outlined,
      IrcMessageAttachmentType.audio => Icons.audiotrack_outlined,
      IrcMessageAttachmentType.file => Icons.download_outlined,
      IrcMessageAttachmentType.media => Icons.lock_outline,
      IrcMessageAttachmentType.dccChat => Icons.chat_bubble_outline,
      IrcMessageAttachmentType.dccSend => Icons.file_present_outlined,
      IrcMessageAttachmentType.url when url != null && isVideoUrl(url) =>
        Icons.movie_outlined,
      IrcMessageAttachmentType.url when url != null && isAudioUrl(url) =>
        Icons.audiotrack_outlined,
      IrcMessageAttachmentType.url
          when url != null && isDownloadableFileUrl(url) =>
        Icons.download_outlined,
      IrcMessageAttachmentType.url => Icons.link,
    };
    final subtitle = _attachmentSubtitle(attachment);
    final canDownload = _canDownloadAttachment(attachment);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: url == null
            ? null
            : () => isImage
                  ? _showImagePreview(context, url)
                  : _openExternalUrl(url),
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
                        Text(title, style: theme.textTheme.labelLarge),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (url != null)
                    IconButton(
                      key: Key('attachment-copy-${attachment.uri}'),
                      onPressed: () => _copyToClipboard(context, url),
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: 'Copy link',
                    ),
                  if (canDownload)
                    IconButton(
                      key: Key('attachment-download-${attachment.uri}'),
                      onPressed: () => onDownloadAttachment(attachment),
                      icon: const Icon(Icons.download_outlined),
                      tooltip: 'Download file',
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

IrcMessageAttachment _attachmentFromParsedPart(ParsedMessagePart part) {
  final type = switch (part.type) {
    ParsedMessagePartType.image => IrcMessageAttachmentType.image,
    ParsedMessagePartType.video => IrcMessageAttachmentType.video,
    ParsedMessagePartType.audio => IrcMessageAttachmentType.audio,
    ParsedMessagePartType.file => IrcMessageAttachmentType.file,
    ParsedMessagePartType.media => IrcMessageAttachmentType.media,
    ParsedMessagePartType.url ||
    ParsedMessagePartType.text => IrcMessageAttachmentType.url,
  };
  final label = switch (part.type) {
    ParsedMessagePartType.image => 'Image',
    ParsedMessagePartType.video => 'Video',
    ParsedMessagePartType.audio => 'Audio',
    ParsedMessagePartType.file => 'File',
    ParsedMessagePartType.media => 'Encrypted media',
    ParsedMessagePartType.url || ParsedMessagePartType.text => 'Link',
  };
  return IrcMessageAttachment(
    type: type,
    label: label,
    uri: part.url,
    mediaId: part.mediaId,
  );
}

String _attachmentSubtitle(IrcMessageAttachment attachment) {
  final parts = <String?>[
    attachment.mediaId,
    attachment.fileName,
    attachment.uri,
    attachment.peerNick == null ? null : 'peer ${attachment.peerNick}',
    attachment.size == null ? null : '${attachment.size} bytes',
    attachment.status,
  ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();
  if (parts.isEmpty) {
    return attachment.type.name;
  }
  return parts.join(' • ');
}

bool _canDownloadAttachment(IrcMessageAttachment attachment) {
  final url = attachment.uri;
  if (url == null || url.trim().isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  return switch (attachment.type) {
    IrcMessageAttachmentType.image ||
    IrcMessageAttachmentType.video ||
    IrcMessageAttachmentType.audio ||
    IrcMessageAttachmentType.file ||
    IrcMessageAttachmentType.media => true,
    IrcMessageAttachmentType.url ||
    IrcMessageAttachmentType.dccChat ||
    IrcMessageAttachmentType.dccSend => false,
  };
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.controller, required this.network});

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
      case ConnectionPhase.registering:
        return 'Registering';
      case ConnectionPhase.authenticating:
        return 'Authenticating';
      case ConnectionPhase.connected:
        return 'Connected';
      case ConnectionPhase.reconnecting:
        return reconnectDelay == null ? 'Reconnecting' : 'Retry scheduled';
      case ConnectionPhase.disconnecting:
        return 'Disconnecting';
      case ConnectionPhase.disconnected:
        return reconnectDelay == null
            ? 'Disconnected'
            : 'Disconnected, retry scheduled';
      case ConnectionPhase.error:
        return reconnectDelay == null
            ? 'Connection error'
            : 'Connection error, retry scheduled';
    }
  }

  IconData _iconForPhase(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return Icons.pause_circle_outline;
      case ConnectionPhase.connecting:
        return Icons.sync;
      case ConnectionPhase.registering:
        return Icons.how_to_reg_outlined;
      case ConnectionPhase.authenticating:
        return Icons.verified_user_outlined;
      case ConnectionPhase.connected:
        return Icons.check_circle_outline;
      case ConnectionPhase.reconnecting:
        return Icons.refresh;
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

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
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
