import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:flutter/material.dart';

/// Manages the ignore/blacklist masks for a session. Masks may be a plain nick
/// or a `nick!user@host` glob with `*`/`?` wildcards.
class IgnoreListScreen extends StatefulWidget {
  const IgnoreListScreen({super.key, required this.controller});

  final ChatSessionController controller;

  @override
  State<IgnoreListScreen> createState() => _IgnoreListScreenState();
}

class _IgnoreListScreenState extends State<IgnoreListScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final mask = _input.text.trim();
    if (mask.isEmpty) {
      return;
    }
    widget.controller.addIgnoreMask(mask);
    _input.clear();
    setState(() {});
  }

  void _remove(String mask) {
    widget.controller.removeIgnoreMask(mask);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final masks = widget.controller.ignoreMasks;
        return Scaffold(
          appBar: AppBar(title: const Text('Ignore list')),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          onSubmitted: (_) => _add(),
                          decoration: const InputDecoration(
                            hintText: 'nick or nick!user@host',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(onPressed: _add, child: const Text('Add')),
                    ],
                  ),
                ),
                Expanded(
                  child: masks.isEmpty
                      ? const Center(child: Text('No ignored masks.'))
                      : ListView.separated(
                          itemCount: masks.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final mask = masks[index];
                            return ListTile(
                              leading: const Icon(Icons.block),
                              title: Text(mask),
                              trailing: IconButton(
                                onPressed: () => _remove(mask),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove',
                              ),
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
