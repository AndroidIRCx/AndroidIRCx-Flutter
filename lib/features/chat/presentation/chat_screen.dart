import 'dart:async';

import 'package:androidircx/app/theme/app_theme.dart';
import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/dcc/services/dcc_file_picker.dart';
import 'package:androidircx/features/chat/application/ban_mask_service.dart';
import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/chat/data/channel_notes_repository.dart';
import 'package:androidircx/features/chat/data/user_list_entry.dart';
import 'package:androidircx/features/chat/data/user_notes_repository.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/chat/presentation/channel_list_screen.dart';
import 'package:androidircx/features/chat/presentation/connection_details_screen.dart';
import 'package:androidircx/features/chat/presentation/media_player_screen.dart';
import 'package:androidircx/features/chat/presentation/ignore_list_screen.dart';
import 'package:androidircx/features/chat/presentation/irc_formatted_text.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/features/chat/presentation/user_lists_screen.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:androidircx/irc/parser/message_content_parser.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:androidircx/media/services/link_preview_service.dart';
import 'package:androidircx/media/services/media_download_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    this.filePicker,
    this.mediaDownloadService,
    this.sessionRegistry,
    this.networkController,
    this.onSwitchNetwork,
    this.onManageNetworks,
    this.channelNotesRepository,
    this.userNotesRepository,
  });

  final ChatSessionController controller;
  final DccFilePicker? filePicker;
  final MediaDownloadService? mediaDownloadService;

  /// Local per-channel notes store; defaults to a shared-preferences backed
  /// instance. Injectable for tests.
  final ChannelNotesRepository? channelNotesRepository;

  /// Local per-user (nick) notes store; defaults to a shared-preferences
  /// backed instance. Injectable for tests.
  final UserNotesRepository? userNotesRepository;

  /// Live sessions across all networks, used by the in-chat network switcher.
  final SessionRegistry? sessionRegistry;

  /// All saved networks, so the switcher can list servers you have not
  /// connected to yet.
  final NetworkListController? networkController;

  /// Switches the chat to [network] (connecting it if needed). When null the
  /// network switcher is hidden.
  final Future<void> Function(NetworkConfig network)? onSwitchNetwork;

  /// Opens the full connection manager (network list).
  final VoidCallback? onManageNetworks;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();
  final TextEditingController _messageSearchController =
      TextEditingController();
  final TextEditingController _nickSearchController = TextEditingController();
  List<CommandSuggestion> _composerSuggestions = const [];
  List<ComposerAutocompleteSuggestion> _autocompleteSuggestions = const [];
  bool _messageSearchVisible = false;
  _HistoryKindFilter _messageSearchFilter = _HistoryKindFilter.all;
  String _nickSearchQuery = '';
  IrcMessage? _pendingReplyMessage;

  ChatSessionController get _controller => widget.controller;
  DccFilePicker get _filePicker =>
      widget.filePicker ?? const MethodChannelDccFilePicker();
  MediaDownloadService get _mediaDownloadService =>
      widget.mediaDownloadService ?? createMediaDownloadService();
  ChannelNotesRepository? _defaultChannelNotes;
  ChannelNotesRepository get _channelNotesRepository =>
      widget.channelNotesRepository ??
      (_defaultChannelNotes ??= ChannelNotesRepository());
  UserNotesRepository? _defaultUserNotes;
  UserNotesRepository get _userNotesRepository =>
      widget.userNotesRepository ??
      (_defaultUserNotes ??= UserNotesRepository());

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _composerController.dispose();
    _messageSearchController.dispose();
    _nickSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true):
            _controller.selectNextTab,
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true):
            _controller.selectPreviousTab,
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _controller,
          if (widget.sessionRegistry != null) widget.sessionRegistry!,
          if (widget.networkController != null) widget.networkController!,
        ]),
        builder: (context, _) {
          final baseMessages = _messageSearchVisible
              ? _controller.messagesForTab(
                  _controller.activeTabId,
                  query: _messageSearchController.text,
                  kinds: _messageSearchFilter.kinds,
                )
              : _controller.activeMessages;
          final visibleMessages = _controller.settings.hideJoinPartQuit
              ? baseMessages
                    .where((message) => message.kind != IrcMessageKind.event)
                    .toList(growable: false)
              : baseMessages;
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
                  onPressed: _openChannelList,
                  icon: const Icon(Icons.format_list_bulleted),
                  tooltip: 'Channel list',
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
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (widget.onSwitchNetwork != null &&
                        widget.networkController != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Text(
                          'NETWORKS',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                        ),
                      ),
                      for (final network in widget.networkController!.networks)
                        _buildNetworkSwitchTile(network),
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('Manage networks'),
                        subtitle: const Text('Add, edit, or browse servers'),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onManageNetworks?.call();
                        },
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      title: Text(_controller.network.name),
                      subtitle: Text(
                        '${_controller.network.host}:${_controller.network.port}',
                      ),
                    ),
                    const Divider(height: 1),
                    for (final tab in _controller.tabs)
                      _buildTabTile(context, tab),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.block),
                      title: const Text('Ignore list'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                IgnoreListScreen(controller: _controller),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.rule_outlined),
                      title: const Text('User lists'),
                      subtitle: const Text(
                        'Notify, protected, blacklist, auto-mode',
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                UserListsScreen(controller: _controller),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Connection details'),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ConnectionDetailsScreen(
                              controller: _controller,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            endDrawer: _controller.activeTab.type == ChatTabType.channel
                ? _buildNickListDrawer(context)
                : null,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // In short viewports (landscape, or portrait with the keyboard
                  // open) the chrome around the message list (status/topic
                  // banners on top, composer + its bars on the bottom) can be
                  // taller than the available height and would crush the list to
                  // zero. When space is tight, cap the top/bottom chrome and let
                  // each scroll internally so the message list always keeps room
                  // and nothing overflows. In normal viewports the caps are the
                  // full height (a no-op), so interactive banners such as the DCC
                  // accept/decline actions stay at their natural, hittable size.
                  final tight = constraints.maxHeight < 380;
                  final topChromeMaxHeight = tight
                      ? constraints.maxHeight * 0.35
                      : constraints.maxHeight;
                  final bottomClusterMaxHeight = tight
                      ? constraints.maxHeight * 0.5
                      : constraints.maxHeight;
                  return Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: topChromeMaxHeight,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                                  onFilterChanged: (filter) => setState(
                                    () => _messageSearchFilter = filter,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  onClose: _toggleMessageSearch,
                                ),
                              if ((_controller.activeChannelTopic ?? '')
                                  .trim()
                                  .isNotEmpty)
                                _ChannelTopicBar(
                                  topic: _controller.activeChannelTopic!.trim(),
                                ),
                              if (_controller.activeTab.type ==
                                      ChatTabType.dcc &&
                                  _controller.activeDccSession != null)
                                _DccSessionBanner(
                                  session: _controller.activeDccSession!,
                                  onAccept: _controller.acceptActiveDccSession,
                                  onDecline:
                                      _controller.declineActiveDccSession,
                                  onClose: _controller.closeActiveDccSession,
                                ),
                              if (_controller.activeTab.type ==
                                  ChatTabType.server)
                                _ServiceQuickActions(
                                  onRun: (service, command) async {
                                    await _controller.sendServiceShortcut(
                                      service,
                                      command,
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: _MessageList(
                          messages: visibleMessages,
                          knownNicks: <String>{
                            ..._controller.activeChannelUsers,
                            _controller.currentNick,
                          },
                          channelPrefixes: _controller.channelPrefixChars,
                          nickPrefixes: _controller.nickPrefixChars,
                          showAttachmentPreviews:
                              _controller.settings.showAttachmentPreviews,
                          resolveReplyTarget: (replyId) => _controller
                              .messageByMsgId(_controller.activeTabId, replyId),
                          resolveReactions: _controller.reactionsForMessage,
                          onRedactMessage: _controller.redactMessage,
                          onQuoteMessage: (message) => _insertIntoComposer(
                            '> ${stripIrcFormatting(message.content)}',
                          ),
                          onReplyWithNick: (message) {
                            final prefix =
                                message.sender == _controller.currentNick
                                ? ''
                                : '${message.sender}: ';
                            _insertIntoComposer(prefix);
                          },
                          onReplyToMessage: _setPendingReply,
                          onDownloadAttachment: _downloadAttachment,
                          onNickTap: (nick) => unawaited(
                            _controller.performChannelUserAction(
                              nick,
                              ChannelUserAction.query,
                            ),
                          ),
                          onNickLongPress: (nick) =>
                              unawaited(_showChannelUserActions(nick)),
                          onChannelTap: (channel) => unawaited(
                            _controller.joinChannel(
                              JoinChannelRequest(channel: channel),
                            ),
                          ),
                          showTimestamps: _controller.settings.showTimestamps,
                          onLoadOlder:
                              _controller.hasPersistentHistory &&
                                  !_messageSearchVisible
                              ? () async {
                                  await _controller.loadOlderHistory(
                                    _controller.activeTabId,
                                  );
                                }
                              : null,
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: bottomClusterMaxHeight,
                        ),
                        child: SingleChildScrollView(
                          reverse: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_controller.commandHistory.isNotEmpty)
                                _CommandHistoryBar(
                                  entries: _controller.commandHistory,
                                  onSelect: (value) => setState(
                                    () => _composerController.text = value,
                                  ),
                                ),
                              if (_controller.activeTypingUsers.isNotEmpty)
                                _TypingIndicator(
                                  users: _controller.activeTypingUsers,
                                ),
                              if (_pendingReplyMessage != null)
                                _PendingReplyBar(
                                  message: _pendingReplyMessage!,
                                  onCancel: () => setState(
                                    () => _pendingReplyMessage = null,
                                  ),
                                ),
                              const Divider(height: 1),
                              _ComposerArea(
                                suggestions: _composerSuggestions,
                                autocompleteSuggestions:
                                    _autocompleteSuggestions,
                                controller: _composerController,
                                hintText:
                                    _controller.activeTab.type ==
                                        ChatTabType.server
                                    ? 'Type raw IRC or /join #channel'
                                    : _controller.activeTab.type ==
                                          ChatTabType.dcc
                                    ? (_controller.activeDccSession?.type ==
                                              DccSessionType.chat
                                          ? 'Type DCC chat message'
                                          : 'DCC SEND tabs do not accept messages')
                                    : 'Message ${_controller.activeTab.name}',
                                onChanged: _handleComposerChanged,
                                onSubmitted: _submit,
                                canSendDccFile:
                                    _controller.activeTab.type ==
                                    ChatTabType.query,
                                onPickDccFile: _pickAndSendDccFile,
                                onSuggestionSelected: _applyComposerSuggestion,
                                onAutocompleteSelected:
                                    _applyAutocompleteSuggestion,
                                enterToSend: _controller.settings.enterToSend,
                                showSendButton:
                                    _controller.settings.showSendButton,
                                onCameraPhoto: () =>
                                    _captureAndSendMedia(ImageSource.camera),
                                onGalleryImage: () =>
                                    _captureAndSendMedia(ImageSource.gallery),
                                onCameraVideo: () => _captureAndSendMedia(
                                  ImageSource.camera,
                                  video: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
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

  Future<void> _pickAndSendDccFileToNick(String nick) async {
    try {
      final filePath = await _filePicker.pickFile();
      if (!mounted || filePath == null) {
        return;
      }
      await _controller.sendDccFileToNick(nick: nick, filePath: filePath);
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

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _captureAndSendMedia(
    ImageSource source, {
    bool video = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final nick = _controller.activeTab.name;
    try {
      final XFile? file = video
          ? await _imagePicker.pickVideo(source: source)
          : await _imagePicker.pickImage(source: source);
      if (file == null) {
        return;
      }
      await _controller.sendDccFileToNick(nick: nick, filePath: file.path);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Capture failed: $error')));
    }
  }

  Future<void> _openChannelList() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChannelListScreen(controller: _controller),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    await _controller.reloadSettings();
  }

  Future<void> _showChannelUserActions(String nick) async {
    final network = _controller.network.id;
    final note = await _userNotesRepository.getNote(network, nick);
    final info = _controller.userInfoForNick(nick);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final isIgnored = _controller.ignoreMasks.contains(
          nick.trim().toLowerCase(),
        );
        Widget action(String label, IconData icon, ChannelUserAction act) {
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_controller.performChannelUserAction(nick, act));
            },
          );
        }

        Widget directAction(
          String label,
          IconData icon,
          VoidCallback onSelected,
        ) {
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onSelected();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    nick,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    note.isEmpty ? 'Channel user actions' : 'Note: $note',
                  ),
                ),
                const Divider(height: 1),
                directAction('Copy nick', Icons.copy, () {
                  unawaited(Clipboard.setData(ClipboardData(text: nick)));
                }),
                ListTile(
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(note.isEmpty ? 'Add note' : 'Edit note'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_showUserNoteDialog(nick, note));
                  },
                ),
                for (final type in UserListType.autoModeTypes)
                  _autoModeToggleTile(sheetContext, nick, type),
                if (info.userhost.isNotEmpty)
                  directAction('Copy userhost', Icons.alternate_email, () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: info.userhost)),
                    );
                  }),
                if (info.hostmask.isNotEmpty)
                  directAction('Copy hostmask', Icons.dns_outlined, () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: info.hostmask)),
                    );
                  }),
                directAction('User info', Icons.badge_outlined, () {
                  unawaited(_showUserInfoPanel(nick));
                }),
                _userListToggleTile(sheetContext, nick, UserListType.notify),
                _userListToggleTile(
                  sheetContext,
                  nick,
                  UserListType.protectedUser,
                ),
                _userListToggleTile(sheetContext, nick, UserListType.other),
                const Divider(height: 1),
                action('WHOIS', Icons.badge_outlined, ChannelUserAction.whois),
                action('WHOWAS', Icons.history, ChannelUserAction.whowas),
                action(
                  'Open query',
                  Icons.chat_bubble_outline,
                  ChannelUserAction.query,
                ),
                action(
                  isIgnored ? 'Unignore' : 'Ignore',
                  isIgnored ? Icons.visibility : Icons.block,
                  ChannelUserAction.ignoreToggle,
                ),
                const Divider(height: 1),
                action(
                  'CTCP PING',
                  Icons.settings_ethernet,
                  ChannelUserAction.ctcpPing,
                ),
                action(
                  'CTCP VERSION',
                  Icons.info_outline,
                  ChannelUserAction.ctcpVersion,
                ),
                action('CTCP TIME', Icons.schedule, ChannelUserAction.ctcpTime),
                action(
                  'DCC Chat',
                  Icons.forum_outlined,
                  ChannelUserAction.dccChat,
                ),
                directAction('DCC Send file', Icons.file_upload_outlined, () {
                  unawaited(_pickAndSendDccFileToNick(nick));
                }),
                directAction('Add blacklist rule', Icons.gpp_bad_outlined, () {
                  unawaited(_showBlacklistEntryDialog(nick));
                }),
                const Divider(height: 1),
                if (_controller.canModerateActiveChannel) ...[
                  action('Op', Icons.shield_outlined, ChannelUserAction.op),
                  action(
                    'Deop',
                    Icons.remove_moderator_outlined,
                    ChannelUserAction.deop,
                  ),
                ],
                if (_controller.canVoiceOrKickActiveChannel) ...[
                  action(
                    'Voice',
                    Icons.volume_up_outlined,
                    ChannelUserAction.voice,
                  ),
                  action(
                    'Devoice',
                    Icons.volume_off_outlined,
                    ChannelUserAction.devoice,
                  ),
                  directAction('Kick', Icons.logout, () {
                    unawaited(
                      _showKickBanDialog(nick, ChannelModerationAction.kick),
                    );
                  }),
                ],
                if (_controller.canModerateActiveChannel) ...[
                  directAction('Ban', Icons.block, () {
                    unawaited(
                      _showKickBanDialog(nick, ChannelModerationAction.ban),
                    );
                  }),
                  directAction('Kick + Ban', Icons.gpp_bad_outlined, () {
                    unawaited(
                      _showKickBanDialog(nick, ChannelModerationAction.kickBan),
                    );
                  }),
                  directAction('Quiet', Icons.volume_off_outlined, () {
                    unawaited(
                      _showKickBanDialog(nick, ChannelModerationAction.quiet),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
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

  Widget _buildNickListDrawer(BuildContext context) {
    final allEntries = _controller.activeChannelUserDetails;
    final normalizedQuery = _nickSearchQuery.trim().toLowerCase();
    final filteredEntries = normalizedQuery.isEmpty
        ? allEntries
        : allEntries
              .where(
                (entry) =>
                    entry.nick.toLowerCase().contains(normalizedQuery) ||
                    entry.details.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);
    final groups = _groupChannelUsers(filteredEntries);
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text(_controller.activeTab.name),
              subtitle: Text(
                normalizedQuery.isEmpty
                    ? '${allEntries.length} users'
                    : '${filteredEntries.length} of ${allEntries.length} users',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                key: const ValueKey('channel-user-search'),
                controller: _nickSearchController,
                decoration: InputDecoration(
                  hintText: 'Search users',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _nickSearchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _nickSearchController.clear();
                              _nickSearchQuery = '';
                            });
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {
                    _nickSearchQuery = value;
                  });
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: allEntries.isEmpty
                  ? const Center(child: Text('No nick list yet.'))
                  : filteredEntries.isEmpty
                  ? const Center(child: Text('No matching users.'))
                  : ListView(
                      children: [
                        for (final group in groups) ...[
                          _NickStatusHeader(
                            group: group,
                            color: _nickStatusColor(colorScheme, group.prefix),
                          ),
                          for (final entry in group.entries)
                            _NickStatusTile(
                              entry: entry,
                              color: _nickStatusColor(
                                colorScheme,
                                entry.prefix,
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                unawaited(_showChannelUserActions(entry.nick));
                              },
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSwitchTile(NetworkConfig network) {
    final isCurrent = network.id == _controller.network.id;
    final snapshot = widget.sessionRegistry?.connectionFor(network.id);
    final connected = snapshot?.phase == ConnectionPhase.connected;
    return ListTile(
      selected: isCurrent,
      leading: Icon(
        connected ? Icons.check_circle : Icons.circle_outlined,
        size: 20,
        color: connected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(network.name),
      subtitle: Text(
        snapshot == null
            ? '${network.host}:${network.port}'
            : '${network.host}:${network.port} • ${_statusText(snapshot)}',
      ),
      onTap: isCurrent
          ? () => Navigator.of(context).pop()
          : () async {
              Navigator.of(context).pop();
              await widget.onSwitchNetwork?.call(network);
            },
    );
  }

  Widget _buildTabTile(BuildContext context, ChatTab tab) {
    final selected = tab.id == _controller.activeTabId;
    return ListTile(
      selected: selected,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(_iconForTab(tab.type)),
          if (tab.hasActivity)
            Positioned(
              right: -10,
              top: -8,
              child: _UnreadBadge(count: tab.unreadCount),
            ),
        ],
      ),
      title: Text(tab.name),
      trailing: tab.type == ChatTabType.server
          ? IconButton(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_showTabOptions(tab));
              },
              icon: const Icon(Icons.more_vert, size: 18),
              tooltip: 'Tab options',
            )
          : SizedBox(
              width: 96,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(_showTabOptions(tab));
                    },
                    icon: const Icon(Icons.more_vert, size: 18),
                    tooltip: 'Tab options',
                  ),
                  IconButton(
                    onPressed: () => _controller.closeTab(tab.id),
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Close tab',
                  ),
                ],
              ),
            ),
      onTap: () {
        _controller.selectTab(tab.id);
        Navigator.of(context).pop();
      },
      onLongPress: tab.type == ChatTabType.channel
          ? () {
              Navigator.of(context).pop();
              unawaited(_showChannelNoteDialog(tab));
            }
          : null,
    );
  }

  Future<void> _showTabOptions(ChatTab tab) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        Widget action(String label, IconData icon, VoidCallback onTap) {
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTap();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(title: Text(tab.name), subtitle: Text(tab.type.name)),
                const Divider(height: 1),
                action('Open', Icons.open_in_new, () {
                  _controller.selectTab(tab.id);
                }),
                action('Copy name', Icons.copy, () {
                  unawaited(Clipboard.setData(ClipboardData(text: tab.name)));
                }),
                action('Recent log', Icons.article_outlined, () {
                  unawaited(_showTabLog(tab));
                }),
                if (tab.type == ChatTabType.channel) ...[
                  action('Channel note', Icons.sticky_note_2_outlined, () {
                    unawaited(_showChannelNoteDialog(tab));
                  }),
                  action('Refresh topic', Icons.topic_outlined, () {
                    _controller.selectTab(tab.id);
                    unawaited(_controller.handleComposerSubmit('/topic'));
                  }),
                  action('Refresh modes', Icons.tune, () {
                    _controller.selectTab(tab.id);
                    unawaited(_controller.handleComposerSubmit('/mode'));
                  }),
                  action('Ban list', Icons.block, () {
                    _controller.selectTab(tab.id);
                    unawaited(_controller.handleComposerSubmit('/banlist'));
                  }),
                  action('Quiet list', Icons.volume_off_outlined, () {
                    _controller.selectTab(tab.id);
                    unawaited(_controller.handleComposerSubmit('/quietlist'));
                  }),
                ],
                if (tab.type != ChatTabType.server)
                  action('Close', Icons.close, () {
                    _controller.closeTab(tab.id);
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTabLog(ChatTab tab) async {
    final messages = _controller.messagesForTab(tab.id);
    await showDialog<void>(
      context: context,
      builder: (context) => _TabLogDialog(tab: tab, messages: messages),
    );
  }

  Future<void> _showChannelNoteDialog(ChatTab tab) async {
    final network = _controller.network.id;
    final existing = await _channelNotesRepository.getNote(network, tab.name);
    if (!mounted) {
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(
        title: 'Note for ${tab.name}',
        hint: 'Notes for this channel (stored only on this device)',
        initialText: existing,
      ),
    );
    if (result == null) {
      return;
    }
    await _channelNotesRepository.setNote(network, tab.name, result);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.trim().isEmpty
              ? 'Channel note cleared.'
              : 'Channel note saved.',
        ),
      ),
    );
  }

  Future<void> _showUserNoteDialog(String nick, String existing) async {
    final network = _controller.network.id;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(
        title: 'Note for $nick',
        hint: 'Notes about this user (stored only on this device)',
        initialText: existing,
      ),
    );
    if (result == null) {
      return;
    }
    await _userNotesRepository.setNote(network, nick, result);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.trim().isEmpty ? 'User note cleared.' : 'User note saved.',
        ),
      ),
    );
  }

  UserListEntry? _existingAutoModeEntry(String nick, UserListType type) {
    final normalized = '${nick.trim().toLowerCase()}!*@*';
    for (final entry in _controller.autoModeEntries) {
      if (entry.type == type &&
          entry.normalizedMask.toLowerCase() == normalized &&
          (entry.network == null || entry.network == _controller.network.id)) {
        return entry;
      }
    }
    return null;
  }

  Widget _autoModeToggleTile(
    BuildContext sheetContext,
    String nick,
    UserListType type,
  ) {
    final existing = _existingAutoModeEntry(nick, type);
    final active = existing != null;
    return ListTile(
      leading: Icon(switch (type) {
        UserListType.autoOp => Icons.shield_moon_outlined,
        UserListType.autoHalfOp => Icons.shield_outlined,
        UserListType.autoVoice => Icons.record_voice_over_outlined,
        _ => Icons.rule_outlined,
      }),
      title: Text(type.label),
      trailing: active
          ? const Icon(Icons.check, size: 18)
          : const Icon(Icons.add, size: 18),
      onTap: () {
        Navigator.of(sheetContext).pop();
        unawaited(_toggleAutoMode(nick, type, existing));
      },
    );
  }

  UserListEntry? _existingUserListEntry(String nick, UserListType type) {
    final normalized = '${nick.trim().toLowerCase()}!*@*';
    for (final entry in _controller.userListEntriesForType(type)) {
      if (entry.normalizedMask.toLowerCase() == normalized &&
          (entry.network == null || entry.network == _controller.network.id)) {
        return entry;
      }
    }
    return null;
  }

  Widget _userListToggleTile(
    BuildContext sheetContext,
    String nick,
    UserListType type,
  ) {
    final existing = _existingUserListEntry(nick, type);
    final active = existing != null;
    return ListTile(
      leading: Icon(switch (type) {
        UserListType.notify => Icons.notifications_active_outlined,
        UserListType.protectedUser => Icons.verified_user_outlined,
        UserListType.other => Icons.label_outline,
        UserListType.blacklist => Icons.gpp_bad_outlined,
        _ => Icons.rule_outlined,
      }),
      title: Text(type.label),
      trailing: active
          ? const Icon(Icons.check, size: 18)
          : const Icon(Icons.add, size: 18),
      onTap: () {
        Navigator.of(sheetContext).pop();
        unawaited(_toggleUserList(nick, type, existing));
      },
    );
  }

  Future<void> _toggleAutoMode(
    String nick,
    UserListType type,
    UserListEntry? existing,
  ) async {
    if (existing != null) {
      await _controller.removeAutoModeEntry(existing);
    } else {
      await _controller.addAutoModeEntry(
        UserListEntry(type: type, mask: nick, network: _controller.network.id),
      );
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing != null
              ? 'Removed $nick from ${type.label}.'
              : 'Added $nick to ${type.label}.',
        ),
      ),
    );
  }

  Future<void> _toggleUserList(
    String nick,
    UserListType type,
    UserListEntry? existing,
  ) async {
    if (existing != null) {
      await _controller.removeUserListEntry(existing);
    } else {
      await _controller.addUserListEntry(
        UserListEntry(type: type, mask: nick, network: _controller.network.id),
      );
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing != null
              ? 'Removed $nick from ${type.label}.'
              : 'Added $nick to ${type.label}.',
        ),
      ),
    );
  }

  Future<void> _showBlacklistEntryDialog(String nick) async {
    final entry = await showDialog<UserListEntry>(
      context: context,
      builder: (context) =>
          _BlacklistEntryDialog(nick: nick, network: _controller.network.id),
    );
    if (entry == null) {
      return;
    }
    await _controller.addUserListEntry(entry);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added $nick to blacklist.')));
  }

  Future<void> _showKickBanDialog(
    String nick,
    ChannelModerationAction action,
  ) async {
    final request = await showDialog<_KickBanRequest>(
      context: context,
      builder: (context) => _KickBanDialog(
        nick: nick,
        action: action,
        maskPreview: (type) => _controller.banMaskPreviewForNick(nick, type),
      ),
    );
    if (request == null) {
      return;
    }
    await _controller.performChannelModerationAction(
      nick: nick,
      action: action,
      reason: request.reason,
      banMaskType: request.banMaskType,
      timedRemoval: request.timedRemoval,
    );
  }

  Future<void> _showUserInfoPanel(String nick) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UserInfoSheet(
        info: _controller.userInfoForNick(nick),
        onWhois: () {
          Navigator.of(context).pop();
          unawaited(
            _controller.performChannelUserAction(nick, ChannelUserAction.whois),
          );
        },
        onWhowas: () {
          Navigator.of(context).pop();
          unawaited(
            _controller.performChannelUserAction(
              nick,
              ChannelUserAction.whowas,
            ),
          );
        },
        onChannelTap: (channel) {
          Navigator.of(context).pop();
          unawaited(
            _controller.joinChannel(JoinChannelRequest(channel: channel)),
          );
        },
      ),
    );
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

String? _dccLimitationNote(DccSession session) {
  if (session.isReverse) {
    return 'Reverse DCC opens a local listener and asks the peer to connect back. NAT, firewall, and peer support can still block the transfer.';
  }
  return null;
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

String _formatClock(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
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
    required this.enterToSend,
    required this.showSendButton,
    required this.onCameraPhoto,
    required this.onGalleryImage,
    required this.onCameraVideo,
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
  final bool enterToSend;
  final bool showSendButton;
  final VoidCallback onCameraPhoto;
  final VoidCallback onGalleryImage;
  final VoidCallback onCameraVideo;

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
                  keyboardType: enterToSend
                      ? TextInputType.text
                      : TextInputType.multiline,
                  textInputAction: enterToSend
                      ? TextInputAction.send
                      : TextInputAction.newline,
                  onChanged: onChanged,
                  onSubmitted: enterToSend ? (_) => onSubmitted() : null,
                  decoration: InputDecoration(hintText: hintText),
                ),
              ),
              const SizedBox(width: 12),
              if (canSendDccFile) ...[
                PopupMenuButton<String>(
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Attach',
                  onSelected: (value) {
                    switch (value) {
                      case 'file':
                        onPickDccFile();
                      case 'camera':
                        onCameraPhoto();
                      case 'gallery':
                        onGalleryImage();
                      case 'video':
                        onCameraVideo();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'file',
                      child: Text('Send file (DCC)'),
                    ),
                    PopupMenuItem<String>(
                      value: 'camera',
                      child: Text('Camera photo'),
                    ),
                    PopupMenuItem<String>(
                      value: 'gallery',
                      child: Text('Gallery image'),
                    ),
                    PopupMenuItem<String>(
                      value: 'video',
                      child: Text('Record video'),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              if (showSendButton || !enterToSend)
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
    final ircTheme = context.ircUiTheme;
    final limitationNote = _dccLimitationNote(session);
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
        color: ircTheme.messageDcc,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ircTheme.messageBorder),
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
          if (limitationNote != null) ...[
            const SizedBox(height: 6),
            Text(
              limitationNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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

class _KickBanRequest {
  const _KickBanRequest({
    required this.banMaskType,
    this.reason,
    this.timedRemoval,
  });

  final int banMaskType;
  final String? reason;
  final Duration? timedRemoval;
}

class _KickBanDialog extends StatefulWidget {
  const _KickBanDialog({
    required this.nick,
    required this.action,
    required this.maskPreview,
  });

  final String nick;
  final ChannelModerationAction action;
  final String Function(int type) maskPreview;

  @override
  State<_KickBanDialog> createState() => _KickBanDialogState();
}

class _KickBanDialogState extends State<_KickBanDialog> {
  static const List<String> _presetReasons = <String>[
    '',
    'Spam',
    'Flooding',
    'Abuse',
    'Off-topic',
    'Policy violation',
  ];

  final TextEditingController _reason = TextEditingController();
  final TextEditingController _duration = TextEditingController();
  String _presetReason = '';
  int _banType = 10;

  @override
  void dispose() {
    _reason.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_duration.text.trim());
    Navigator.of(context).pop(
      _KickBanRequest(
        banMaskType: _banType,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        timedRemoval: minutes == null || minutes <= 0
            ? null
            : Duration(minutes: minutes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.action) {
      ChannelModerationAction.kick => 'Kick ${widget.nick}',
      ChannelModerationAction.ban => 'Ban ${widget.nick}',
      ChannelModerationAction.kickBan => 'Kick + ban ${widget.nick}',
      ChannelModerationAction.quiet => 'Quiet ${widget.nick}',
    };
    final needsMask = widget.action != ChannelModerationAction.kick;
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (needsMask) ...[
              DropdownButtonFormField<int>(
                initialValue: _banType,
                decoration: const InputDecoration(labelText: 'Ban mask'),
                items: [
                  for (final type in banMaskTypes)
                    DropdownMenuItem(
                      value: type.id,
                      child: Text('${type.id}: ${type.pattern}'),
                    ),
                ],
                onChanged: (value) => setState(() => _banType = value ?? 10),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.maskPreview(_banType),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            DropdownButtonFormField<String>(
              initialValue: _presetReason,
              decoration: const InputDecoration(labelText: 'Preset reason'),
              items: [
                for (final reason in _presetReasons)
                  DropdownMenuItem(
                    value: reason,
                    child: Text(reason.isEmpty ? 'Custom' : reason),
                  ),
              ],
              onChanged: (value) {
                final next = value ?? '';
                setState(() => _presetReason = next);
                if (next.isNotEmpty) {
                  _reason.text = next;
                }
              },
            ),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'optional',
              ),
            ),
            if (needsMask)
              TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Timed removal minutes',
                  hintText: 'blank = permanent',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Send')),
      ],
    );
  }
}

class _BlacklistEntryDialog extends StatefulWidget {
  const _BlacklistEntryDialog({required this.nick, required this.network});

  final String nick;
  final String network;

  @override
  State<_BlacklistEntryDialog> createState() => _BlacklistEntryDialogState();
}

class _BlacklistEntryDialogState extends State<_BlacklistEntryDialog> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _duration = TextEditingController();
  final TextEditingController _customRaw = TextEditingController();
  BlacklistAction _action = BlacklistAction.ignore;

  @override
  void dispose() {
    _reason.dispose();
    _duration.dispose();
    _customRaw.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_duration.text.trim());
    Navigator.of(context).pop(
      UserListEntry(
        type: UserListType.blacklist,
        mask: widget.nick,
        network: widget.network,
        blacklistAction: _action,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        duration: minutes == null || minutes <= 0
            ? null
            : Duration(minutes: minutes),
        customRaw: _customRaw.text.trim().isEmpty
            ? null
            : _customRaw.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Blacklist ${widget.nick}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<BlacklistAction>(
              initialValue: _action,
              decoration: const InputDecoration(labelText: 'Action'),
              items: [
                for (final action in BlacklistAction.values)
                  DropdownMenuItem(value: action, child: Text(action.label)),
              ],
              onChanged: (value) => setState(() => _action = value ?? _action),
            ),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'optional',
              ),
            ),
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration minutes',
                hintText: 'blank = permanent',
              ),
            ),
            if (_action == BlacklistAction.custom)
              TextField(
                controller: _customRaw,
                decoration: const InputDecoration(
                  labelText: 'Custom raw template',
                  hintText: 'GLINE {hostmask} {duration} :{reason}',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _UserInfoSheet extends StatelessWidget {
  const _UserInfoSheet({
    required this.info,
    required this.onWhois,
    required this.onWhowas,
    required this.onChannelTap,
  });

  final IrcUserInfo info;
  final VoidCallback onWhois;
  final VoidCallback onWhowas;
  final ValueChanged<String> onChannelTap;

  @override
  Widget build(BuildContext context) {
    final rows = <({IconData icon, String label, String value})>[
      if (info.hostmask.isNotEmpty)
        (icon: Icons.dns_outlined, label: 'Hostmask', value: info.hostmask),
      if ((info.account ?? '').isNotEmpty)
        (icon: Icons.verified_outlined, label: 'Account', value: info.account!),
      if ((info.realName ?? '').isNotEmpty)
        (icon: Icons.person_outline, label: 'Real name', value: info.realName!),
      if ((info.awayMessage ?? '').isNotEmpty)
        (
          icon: Icons.hourglass_empty,
          label: 'Away',
          value: info.awayMessage == '__away__' ? 'away' : info.awayMessage!,
        ),
      if ((info.server ?? '').isNotEmpty)
        (
          icon: Icons.storage_outlined,
          label: 'Server',
          value: [info.server, info.serverInfo].whereType<String>().join(' '),
        ),
      if (info.idleSeconds != null)
        (
          icon: Icons.timer_outlined,
          label: 'Idle',
          value: '${info.idleSeconds}s',
        ),
      if (info.signedOn != null)
        (
          icon: Icons.login,
          label: 'Signed on',
          value: info.signedOn.toString(),
        ),
      if (info.isRegistered)
        (icon: Icons.how_to_reg, label: 'Registered', value: 'yes'),
      if (info.isOper)
        (icon: Icons.security, label: 'IRC operator', value: 'yes'),
      if (info.isSecure)
        (icon: Icons.lock_outline, label: 'Secure connection', value: 'yes'),
      for (final extra in info.extra)
        (icon: Icons.info_outline, label: 'Info', value: extra),
    ];

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            children: [
              ListTile(
                title: Text(
                  info.nick,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: Text(info.fromWhowas ? 'WHOWAS cache' : 'User info'),
              ),
              OverflowBar(
                alignment: MainAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: onWhois,
                    icon: const Icon(Icons.refresh),
                    label: const Text('WHOIS'),
                  ),
                  TextButton.icon(
                    onPressed: onWhowas,
                    icon: const Icon(Icons.history),
                    label: const Text('WHOWAS'),
                  ),
                ],
              ),
              const Divider(height: 1),
              for (final row in rows)
                ListTile(
                  leading: Icon(row.icon),
                  title: Text(row.label),
                  subtitle: Text(row.value),
                  onLongPress: () =>
                      Clipboard.setData(ClipboardData(text: row.value)),
                ),
              if (info.channels.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    'Channels',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final channel in info.channels)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ActionChip(
                          label: Text(channel),
                          onPressed: () => onChannelTap(channel),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TabLogDialog extends StatelessWidget {
  const _TabLogDialog({required this.tab, required this.messages});

  final ChatTab tab;
  final List<IrcMessage> messages;

  @override
  Widget build(BuildContext context) {
    final export = messages
        .map(
          (message) =>
              '[${message.timestamp.toIso8601String()}] <${message.sender}> ${stripIrcFormatting(message.content)}',
        )
        .join('\n');
    return AlertDialog(
      title: Text('Recent log: ${tab.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: messages.isEmpty
            ? const Text('No messages in this tab.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: messages.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      stripIrcFormatting(message.content),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${message.sender} · ${message.kind.name}'),
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: export.isEmpty
              ? null
              : () => Clipboard.setData(ClipboardData(text: export)),
          icon: const Icon(Icons.copy_all),
          label: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
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
    final ircTheme = context.ircUiTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ircTheme.topic,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ircTheme.messageBorder),
      ),
      child: IrcFormattedText(
        topic,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        baseStyle: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.clamp(1, 99).toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.surface),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
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

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.hint,
    required this.initialText,
  });

  final String title;
  final String hint;
  final String initialText;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.knownNicks,
    required this.channelPrefixes,
    required this.nickPrefixes,
    required this.showAttachmentPreviews,
    required this.resolveReplyTarget,
    required this.resolveReactions,
    required this.onRedactMessage,
    required this.onQuoteMessage,
    required this.onReplyWithNick,
    required this.onReplyToMessage,
    required this.onDownloadAttachment,
    required this.onNickTap,
    required this.onNickLongPress,
    required this.onChannelTap,
    this.onLoadOlder,
    this.showTimestamps = true,
  });

  final List<IrcMessage> messages;
  final Set<String> knownNicks;
  final String channelPrefixes;
  final String nickPrefixes;
  final bool showAttachmentPreviews;
  final bool showTimestamps;
  final Future<void> Function()? onLoadOlder;
  final IrcMessage? Function(String replyId) resolveReplyTarget;
  final Map<String, int> Function(IrcMessage message) resolveReactions;
  final Future<bool> Function(IrcMessage message) onRedactMessage;
  final ValueChanged<IrcMessage> onQuoteMessage;
  final ValueChanged<IrcMessage> onReplyWithNick;
  final ValueChanged<IrcMessage> onReplyToMessage;
  final Future<void> Function(IrcMessageAttachment attachment)
  onDownloadAttachment;
  final ValueChanged<String> onNickTap;
  final ValueChanged<String> onNickLongPress;
  final ValueChanged<String> onChannelTap;

  @override
  Widget build(BuildContext context) {
    final ircTheme = context.ircUiTheme;
    if (messages.isEmpty) {
      // Shrink-to-fit so the placeholder never overflows a short viewport
      // (landscape / keyboard open).
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                'No messages yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    final hasLoadOlder = onLoadOlder != null;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length + (hasLoadOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasLoadOlder && index == messages.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton.icon(
                onPressed: onLoadOlder,
                icon: const Icon(Icons.history),
                label: const Text('Load earlier messages'),
              ),
            ),
          );
        }
        final message = messages[messages.length - 1 - index];
        final isRedacted = message.tags['redacted'] == 'true';
        final reactions = resolveReactions(message);
        final bubbleColor = switch (message.kind) {
          IrcMessageKind.system ||
          IrcMessageKind.event => ircTheme.messageSystem,
          IrcMessageKind.error => ircTheme.messageError,
          IrcMessageKind.dcc => ircTheme.messageDcc,
          IrcMessageKind.raw => ircTheme.messageRaw,
          IrcMessageKind.media => ircTheme.messageMedia,
          IrcMessageKind.chat ||
          IrcMessageKind.action ||
          IrcMessageKind.notice =>
            message.isOwn ? ircTheme.messageOwn : ircTheme.messageOther,
        };
        final messageStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: ircTheme.messageFontSize,
          fontFamily: ircTheme.messageFontFamily,
          fontStyle: isRedacted ? FontStyle.italic : null,
          color: isRedacted
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        );
        final metaStyle = messageStyle?.copyWith(
          fontSize: (ircTheme.messageFontSize - 2).clamp(9, 100).toDouble(),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
        final senderStyle = messageStyle?.copyWith(
          fontWeight: FontWeight.w600,
          color:
              ircTheme.nickColorFor(message.sender) ??
              Theme.of(context).colorScheme.onSurface,
        );
        final leadingSpans = <InlineSpan>[
          if (_isInteractiveSender(message))
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => onNickTap(message.sender),
                onLongPress: () => onNickLongPress(message.sender),
                child: RichText(
                  text: TextSpan(text: message.sender, style: senderStyle),
                ),
              ),
            )
          else
            TextSpan(text: message.sender, style: senderStyle),
          if (showTimestamps)
            TextSpan(
              text: '  ${_formatClock(message.timestamp)}',
              style: metaStyle,
            ),
          if (message.isPlayback)
            TextSpan(text: '  · history', style: metaStyle),
          const TextSpan(text: '   '),
        ];
        return Padding(
          padding: EdgeInsets.only(bottom: ircTheme.messageSpacing),
          child: Align(
            alignment: message.isOwn
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: GestureDetector(
              onLongPress: () => _showMessageActions(context, message),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: message.isPlayback
                      ? bubbleColor.withValues(alpha: 0.88)
                      : bubbleColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ircTheme.messageBorder),
                ),
                child: Padding(
                  padding: ircTheme.messagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((message.tags['draft/reply'] ?? '').trim().isNotEmpty)
                        _ReplyPreview(
                          referenced: resolveReplyTarget(
                            message.tags['draft/reply']!.trim(),
                          ),
                          replyId: message.tags['draft/reply']!.trim(),
                        ),
                      IrcFormattedText(
                        message.content,
                        baseStyle: messageStyle,
                        leading: leadingSpans,
                        knownNicks: <String>{...knownNicks, message.sender},
                        channelPrefixes: channelPrefixes,
                        nickPrefixes: nickPrefixes,
                        contextNick: message.sender,
                        onNickTap: onNickTap,
                        onNickLongPress: onNickLongPress,
                        onChannelTap: onChannelTap,
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

  bool _isInteractiveSender(IrcMessage message) {
    final sender = message.sender.trim();
    if (sender.isEmpty || sender == '*') {
      return false;
    }
    switch (message.kind) {
      case IrcMessageKind.chat:
      case IrcMessageKind.action:
      case IrcMessageKind.notice:
        return true;
      case IrcMessageKind.system:
      case IrcMessageKind.raw:
      case IrcMessageKind.error:
      case IrcMessageKind.event:
      case IrcMessageKind.dcc:
      case IrcMessageKind.media:
        return false;
    }
  }
}

class _NickStatusGroup {
  _NickStatusGroup({
    required this.prefix,
    required this.title,
    required this.entries,
  });

  final String? prefix;
  final String title;
  final List<ChannelUserDetails> entries;
}

List<_NickStatusGroup> _groupChannelUsers(List<ChannelUserDetails> entries) {
  final groups = <_NickStatusGroup>[
    _NickStatusGroup(prefix: '~', title: 'Owners', entries: []),
    _NickStatusGroup(prefix: '&', title: 'Admins', entries: []),
    _NickStatusGroup(prefix: '@', title: 'Operators', entries: []),
    _NickStatusGroup(prefix: '%', title: 'Half operators', entries: []),
    _NickStatusGroup(prefix: '+', title: 'Voiced', entries: []),
    _NickStatusGroup(prefix: null, title: 'Regular', entries: []),
  ];

  for (final entry in entries) {
    final rank = entry.statusRank;
    if (rank >= 0 && rank < groups.length - 1) {
      groups[rank].entries.add(entry);
    } else {
      groups.last.entries.add(entry);
    }
  }

  for (final group in groups) {
    group.entries.sort(
      (a, b) => a.nick.toLowerCase().compareTo(b.nick.toLowerCase()),
    );
  }
  return groups.where((group) => group.entries.isNotEmpty).toList();
}

Color _nickStatusColor(ColorScheme colorScheme, String? prefix) {
  return switch (prefix) {
    '~' => const Color(0xFF9C27B0),
    '&' => const Color(0xFFF44336),
    '@' => const Color(0xFFFF9800),
    '%' => const Color(0xFF2196F3),
    '+' => const Color(0xFF4CAF50),
    _ => colorScheme.onSurfaceVariant,
  };
}

class _NickStatusHeader extends StatelessWidget {
  const _NickStatusHeader({required this.group, required this.color});

  final _NickStatusGroup group;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        group.prefix == null
            ? '${group.title} (${group.entries.length})'
            : '${group.prefix} ${group.title} (${group.entries.length})',
        style: textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NickStatusTile extends StatelessWidget {
  const _NickStatusTile({
    required this.entry,
    required this.color,
    required this.onTap,
  });

  final ChannelUserDetails entry;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final prefix = entry.prefix;
    return ListTile(
      leading: SizedBox.square(
        dimension: 40,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: color.withValues(alpha: 0.12),
            shape: CircleBorder(
              side: BorderSide(color: color.withValues(alpha: 0.35)),
            ),
          ),
          child: Center(
            child: prefix == null
                ? Icon(Icons.person_outline, size: 20, color: color)
                : Text(
                    prefix,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
          ),
        ),
      ),
      title: Text(
        entry.nick,
        style: TextStyle(
          color: color,
          fontWeight: prefix == null ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
      subtitle: entry.details.isEmpty ? null : Text(entry.details),
      onTap: onTap,
    );
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AttachmentCard(
                      attachment: attachment,
                      onDownloadAttachment: onDownloadAttachment,
                    ),
                    if (attachment.type == IrcMessageAttachmentType.url &&
                        (attachment.uri ?? '').isNotEmpty)
                      _LinkPreviewCard(url: attachment.uri!),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

/// Shared link-preview service; overridable in tests to avoid real network.
LinkPreviewService linkPreviewService = LinkPreviewService();

class _LinkPreviewCard extends StatefulWidget {
  const _LinkPreviewCard({required this.url});

  final String url;

  @override
  State<_LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<_LinkPreviewCard> {
  late final Future<LinkPreview?> _future = linkPreviewService.fetch(
    widget.url,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LinkPreview?>(
      future: _future,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        if (preview == null || !preview.hasContent) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: InkWell(
            onTap: () => launchUrl(
              Uri.parse(widget.url),
              mode: LaunchMode.externalApplication,
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((preview.imageUrl ?? '').isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        preview.imageUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_siteLabel(preview).isNotEmpty) ...[
                    Row(
                      children: [
                        if ((preview.faviconUrl ?? '').isNotEmpty) ...[
                          Image.network(
                            preview.faviconUrl!,
                            height: 16,
                            width: 16,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            _siteLabel(preview),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if ((preview.title ?? '').isNotEmpty)
                    Text(
                      preview.title!,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if ((preview.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.description!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _siteLabel(LinkPreview preview) {
    final site = preview.siteName?.trim();
    if (site != null && site.isNotEmpty) {
      return site;
    }
    final host = Uri.tryParse(preview.url)?.host;
    return host ?? '';
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
    final ircTheme = context.ircUiTheme;
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
      color: ircTheme.attachment,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          switch (attachmentTapAction(attachment)) {
            case AttachmentTapAction.none:
              break;
            case AttachmentTapAction.imagePreview:
              unawaited(_showImagePreview(context, url!));
            case AttachmentTapAction.playVideo:
              _openMediaPlayer(context, url!, isAudio: false, title: title);
            case AttachmentTapAction.playAudio:
              _openMediaPlayer(context, url!, isAudio: true, title: title);
            case AttachmentTapAction.external:
              unawaited(_openExternalUrl(url!));
          }
        },
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
    final statusColor = _colorForPhase(context, snapshot.phase);

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
        color: Color.lerp(statusColor, theme.colorScheme.surface, 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForPhase(snapshot.phase), size: 18, color: statusColor),
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Current nick: ${controller.currentNick}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if ((snapshot.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              snapshot.message!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (snapshot.phase == ConnectionPhase.error ||
              snapshot.phase == ConnectionPhase.disconnected) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: controller.reconnectNow,
                  child: const Text('Reconnect now'),
                ),
                if (reconnectDelay != null) ...[
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

  Color _colorForPhase(BuildContext context, ConnectionPhase phase) {
    final scheme = Theme.of(context).colorScheme;
    final ircTheme = context.ircUiTheme;
    return switch (phase) {
      ConnectionPhase.idle => scheme.onSurfaceVariant,
      ConnectionPhase.connecting ||
      ConnectionPhase.registering ||
      ConnectionPhase.authenticating ||
      ConnectionPhase.reconnecting => scheme.primary,
      ConnectionPhase.connected => scheme.primary,
      ConnectionPhase.disconnecting ||
      ConnectionPhase.disconnected => scheme.tertiary,
      ConnectionPhase.error => Color.lerp(
        scheme.error,
        ircTheme.messageError,
        0.2,
      )!,
    };
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

/// How tapping an attachment should behave. Extracted for testing.
enum AttachmentTapAction { none, imagePreview, playVideo, playAudio, external }

AttachmentTapAction attachmentTapAction(IrcMessageAttachment attachment) {
  final url = attachment.uri;
  if (url == null) {
    return AttachmentTapAction.none;
  }
  switch (attachment.type) {
    case IrcMessageAttachmentType.image:
      return AttachmentTapAction.imagePreview;
    case IrcMessageAttachmentType.video:
      return AttachmentTapAction.playVideo;
    case IrcMessageAttachmentType.audio:
      return AttachmentTapAction.playAudio;
    case IrcMessageAttachmentType.url:
      if (isVideoUrl(url)) {
        return AttachmentTapAction.playVideo;
      }
      if (isAudioUrl(url)) {
        return AttachmentTapAction.playAudio;
      }
      return AttachmentTapAction.external;
    case IrcMessageAttachmentType.file:
    case IrcMessageAttachmentType.media:
    case IrcMessageAttachmentType.dccChat:
    case IrcMessageAttachmentType.dccSend:
      return AttachmentTapAction.external;
  }
}

void _openMediaPlayer(
  BuildContext context,
  String url, {
  required bool isAudio,
  String? title,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) =>
          MediaPlayerScreen(url: url, isAudio: isAudio, title: title),
    ),
  );
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
