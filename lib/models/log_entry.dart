import 'package:flutter/material.dart';

enum LogType { request, response, info, error, success }

class LogEntry {
  final String title;
  final String body;
  final LogType type;
  final DateTime timestamp;

  LogEntry({
    required this.title,
    required this.body,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Color get color {
    switch (type) {
      case LogType.request:
        return const Color(0xFF4FC3F7); // light blue
      case LogType.response:
        return const Color(0xFF81C784); // green
      case LogType.info:
        return const Color(0xFFFFD54F); // amber
      case LogType.error:
        return const Color(0xFFEF9A9A); // red
      case LogType.success:
        return const Color(0xFF69F0AE); // bright green
    }
  }

  String get tag {
    switch (type) {
      case LogType.request:
        return '▲ REQ';
      case LogType.response:
        return '▼ RES';
      case LogType.info:
        return '● INFO';
      case LogType.error:
        return '✕ ERR';
      case LogType.success:
        return '✓ OK';
    }
  }
}
