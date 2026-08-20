import 'dart:convert';

import 'package:androidircx/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Visual editor for the custom theme: pick brightness and per-role colors and
/// it generates the theme JSON (the same shape the raw-JSON field accepts).
class ThemeEditorScreen extends StatefulWidget {
  const ThemeEditorScreen({
    super.key,
    required this.initialJson,
    required this.onSaved,
  });

  final String initialJson;
  final Future<void> Function(String json) onSaved;

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

const _colorRoles = <String, String>{
  'primary': 'Primary',
  'secondary': 'Secondary',
  'tertiary': 'Accent',
  'scaffold': 'Background',
  'surface': 'Surface',
  'card': 'Card',
  'panel': 'Panel',
  'messageOwn': 'My messages',
  'messageOther': 'Other messages',
  'messageSystem': 'System',
  'messageError': 'Error',
  'messageDcc': 'DCC',
  'messageMedia': 'Media',
  'messageRaw': 'Raw',
  'attachment': 'Attachment',
  'topic': 'Topic',
};

const _swatches = <Color>[
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFFF4511E),
  Color(0xFFFDD835),
  Color(0xFF00ACC1),
  Color(0xFF6D4C41),
  Color(0xFF546E7A),
  Color(0xFFEC407A),
  Color(0xFF212121),
  Color(0xFFFAFAFA),
  Color(0xFF37474F),
];

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late Map<String, Object?> _theme;

  @override
  void initState() {
    super.initState();
    _theme = _parseInitial(widget.initialJson);
  }

  Map<String, Object?> _parseInitial(String json) {
    if (json.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, Object?>) {
          return Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        // fall through to template
      }
    }
    return Map<String, Object?>.from(
      jsonDecode(customThemeJsonTemplate()) as Map,
    );
  }

  bool get _isDark => (_theme['brightness'] as String?) == 'dark';

  Color _colorFor(String key) {
    final hex = _theme[key] as String? ?? '#808080';
    return _hexToColor(hex);
  }

  Future<void> _editColor(String key, String label) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        label: label,
        initial: _colorFor(key),
      ),
    );
    if (picked != null) {
      setState(() => _theme[key] = _colorToHex(picked));
    }
  }

  Future<void> _save() async {
    await widget.onSaved(jsonEncode(_theme));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme editor'),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark base'),
              value: _isDark,
              onChanged: (value) => setState(
                () => _theme['brightness'] = value ? 'dark' : 'light',
              ),
            ),
            const Divider(height: 1),
            for (final entry in _colorRoles.entries)
              ListTile(
                title: Text(entry.value),
                subtitle: Text(_theme[entry.key] as String? ?? ''),
                trailing: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _colorFor(entry.key),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                onTap: () => _editColor(entry.key, entry.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.label, required this.initial});

  final String label;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late final TextEditingController _hex;
  late Color _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _hex = TextEditingController(text: _colorToHex(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _applyHex(String value) {
    final color = _tryHexToColor(value);
    if (color != null) {
      setState(() => _current = color);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: _current,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final swatch in _swatches)
                GestureDetector(
                  onTap: () => setState(() {
                    _current = swatch;
                    _hex.text = _colorToHex(swatch);
                  }),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: swatch,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hex,
            decoration: const InputDecoration(
              labelText: 'Hex (#RRGGBB)',
              border: OutlineInputBorder(),
            ),
            onChanged: _applyHex,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_current),
          child: const Text('Use'),
        ),
      ],
    );
  }
}

Color _hexToColor(String hex) => _tryHexToColor(hex) ?? const Color(0xFF808080);

Color? _tryHexToColor(String hex) {
  var value = hex.trim().replaceAll('#', '');
  if (value.length == 6) {
    value = 'FF$value';
  }
  if (value.length != 8) {
    return null;
  }
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

String _colorToHex(Color color) {
  int channel(double v) => (v * 255).round().clamp(0, 255);
  final r = channel(color.r).toRadixString(16).padLeft(2, '0');
  final g = channel(color.g).toRadixString(16).padLeft(2, '0');
  final b = channel(color.b).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
