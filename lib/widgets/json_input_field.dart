import 'dart:convert';
import 'package:flutter/material.dart';

class JsonInputField extends StatefulWidget {
  final TextEditingController controller;
  final String label;

  const JsonInputField({
    super.key,
    required this.controller,
    required this.label,
  });

  @override
  State<JsonInputField> createState() => _JsonInputFieldState();
}

class _JsonInputFieldState extends State<JsonInputField> {
  bool _isExpanded = true;
  bool _isValidJson = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validateJson);
    _validateJson();
  }

  void _validateJson() {
    if (widget.controller.text.isEmpty) {
      setState(() => _isValidJson = true);
      return;
    }
    try {
      jsonDecode(widget.controller.text);
      setState(() => _isValidJson = true);
    } catch (_) {
      setState(() => _isValidJson = false);
    }
  }

  void _formatJson() {
    try {
      final parsed = jsonDecode(widget.controller.text);
      widget.controller.text =
          const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                color: Color(0xFF8A9BB0),
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (!_isValidJson)
              const Text(
                '⚠ Invalid JSON',
                style: TextStyle(color: Color(0xFFEF9A9A), fontSize: 10),
              ),
            if (_isValidJson && widget.controller.text.isNotEmpty)
              const Text(
                '✓ Valid JSON',
                style: TextStyle(color: Color(0xFF69F0AE), fontSize: 10),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _formatJson,
              child: const Text(
                'Format',
                style: TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontSize: 10,
                    decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Icon(
                _isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: const Color(0xFF4A6080),
                size: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_isExpanded)
          TextField(
            controller: widget.controller,
            maxLines: 10,
            minLines: 5,
            style: const TextStyle(
              color: Color(0xFFCFE2F0),
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF071320),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: _isValidJson
                      ? const Color(0xFF1E3A5F)
                      : const Color(0xFFEF9A9A).withOpacity(0.5),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: _isValidJson
                      ? const Color(0xFF1E3A5F)
                      : const Color(0xFFEF9A9A).withOpacity(0.5),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: _isValidJson
                      ? const Color(0xFF00D4FF)
                      : const Color(0xFFEF9A9A),
                  width: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_validateJson);
    super.dispose();
  }
}
