import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/log_entry.dart';
import 'package:intl/intl.dart';

class LogPanel extends StatefulWidget {
  final List<LogEntry> logs;
  final VoidCallback onClear;

  const LogPanel({super.key, required this.logs, required this.onClear});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  String _filter = 'ALL';

  List<LogEntry> get _filteredLogs {
    if (_filter == 'ALL') return widget.logs;
    return widget.logs.where((l) {
      switch (_filter) {
        case 'REQ':
          return l.type == LogType.request;
        case 'RES':
          return l.type == LogType.response;
        case 'ERR':
          return l.type == LogType.error;
        case 'OK':
          return l.type == LogType.success;
        case 'INFO':
          return l.type == LogType.info;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF0D1F3C),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['ALL', 'REQ', 'RES', 'OK', 'ERR', 'INFO']
                        .map((f) => _filterChip(f))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onClear,
                child: const Row(
                  children: [
                    Icon(Icons.delete_outline,
                        color: Color(0xFF4A6080), size: 14),
                    SizedBox(width: 4),
                    Text('Clear',
                        style: TextStyle(
                            color: Color(0xFF4A6080), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Log list
        Expanded(
          child: widget.logs.isEmpty
              ? const Center(
                  child: Text(
                    'No logs yet.\nStart by initiating the SDK.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF2A4060), fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _filteredLogs.length,
                  itemBuilder: (ctx, i) => _LogCard(entry: _filteredLogs[i]),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label) {
    final active = _filter == label;
    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00D4FF).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active
                ? const Color(0xFF00D4FF)
                : const Color(0xFF1E3A5F),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                active ? const Color(0xFF00D4FF) : const Color(0xFF4A6080),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LogCard extends StatefulWidget {
  final LogEntry entry;
  const _LogCard({required this.entry});

  @override
  State<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<_LogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final timeStr = DateFormat('HH:mm:ss.SSS').format(e.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F3C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: e.color.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: e.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      e.tag,
                      style: TextStyle(
                        color: e.color,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.title,
                      style: TextStyle(
                        color: e.color.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Color(0xFF3A5070),
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF3A5070),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),

          // Body
          if (_expanded)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF071320),
                border: Border(
                  top: BorderSide(
                      color: e.color.withOpacity(0.15), width: 1),
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: SelectableText(
                      e.body,
                      style: const TextStyle(
                        color: Color(0xFF8AB8D0),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: e.body));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy,
                          color: Color(0xFF2A4060), size: 14),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
