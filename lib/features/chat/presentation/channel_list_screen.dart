import 'package:androidircx/core/models/channel_list_entry.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:flutter/material.dart';

/// Browses the server channel list (LIST) with search and one-tap join.
class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key, required this.controller});

  final ChatSessionController controller;

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Refresh the list on open unless one is already loaded.
    if (widget.controller.channelListing.isEmpty) {
      widget.controller.requestChannelList();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChannelListEntry> get _filtered {
    final query = _query.trim().toLowerCase();
    final entries = widget.controller.channelListing;
    final visible = query.isEmpty
        ? entries
        : entries
            .where((entry) =>
                entry.name.toLowerCase().contains(query) ||
                entry.topic.toLowerCase().contains(query))
            .toList(growable: false);
    return [...visible]
      ..sort((a, b) => b.userCount.compareTo(a.userCount));
  }

  Future<void> _join(ChannelListEntry entry) async {
    await widget.controller.joinChannel(
      JoinChannelRequest(channel: entry.name),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final entries = _filtered;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Channel list'),
            actions: [
              IconButton(
                onPressed: widget.controller.requestChannelList,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search channels or topics',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (widget.controller.channelListInProgress)
                  const LinearProgressIndicator(),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            widget.controller.channelListInProgress
                                ? 'Loading channels…'
                                : 'No channels. Pull refresh to request LIST.',
                          ),
                        )
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return ListTile(
                              leading: const Icon(Icons.tag),
                              title: Text(entry.name),
                              subtitle: entry.topic.isEmpty
                                  ? null
                                  : Text(
                                      entry.topic,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: Text('${entry.userCount}'),
                              onTap: () => _join(entry),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
