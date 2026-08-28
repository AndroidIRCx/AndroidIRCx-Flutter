import 'package:flutter/material.dart';

class JoinChannelRequest {
  const JoinChannelRequest({required this.channel});

  final String channel;
}

class JoinChannelDialog extends StatefulWidget {
  const JoinChannelDialog({super.key});

  @override
  State<JoinChannelDialog> createState() => _JoinChannelDialogState();
}

class _JoinChannelDialogState extends State<JoinChannelDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '#');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join channel'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Channel'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(
              context,
            ).pop(JoinChannelRequest(channel: _controller.text.trim()));
          },
          child: const Text('Join'),
        ),
      ],
    );
  }
}
