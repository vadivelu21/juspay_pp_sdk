import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:hyper_webview_flutter/hyper_webview_flutter.dart';
import '../models/log_entry.dart';

class PaymentWebviewScreen extends StatefulWidget {
  final String url;
  final String orderId;
  final void Function(LogEntry) onLog;

  const PaymentWebviewScreen({
    super.key,
    required this.url,
    required this.orderId,
    required this.onLog,
  });

  @override
  State<PaymentWebviewScreen> createState() => _PaymentWebviewScreenState();
}

class _PaymentWebviewScreenState extends State<PaymentWebviewScreen> {
  late WebViewController _controller;
  final HyperWebviewFlutter _hyperWebview = HyperWebviewFlutter();

  bool _isLoading = true;
  int _loadProgress = 0;
  String _currentUrl = '';

  // Safe log — defers setState calls that happen during build phase
  void _safeLog(LogEntry entry) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLog(entry);
    });
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;

    // Defer the first log — initState fires during parent build
    _safeLog(LogEntry(
      title: '▲ WebView — Loading Payment URL',
      body: 'Order: ${widget.orderId}\nURL: ${widget.url}',
      type: LogType.request,
    ));

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Hyper/track=cug')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _currentUrl = url;
              });
            }
            widget.onLog(LogEntry(
              title: '→ WebView — Page Started',
              body: url,
              type: LogType.info,
            ));
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
              });
            }
            widget.onLog(LogEntry(
              title: '✓ WebView — Page Loaded',
              body: url,
              type: LogType.success,
            ));
          },
          onProgress: (progress) {
            if (mounted) setState(() => _loadProgress = progress);
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _isLoading = false);
            widget.onLog(LogEntry(
              title: '✕ WebView — Resource Error',
              body: 'Code: ${error.errorCode}\n'
                  'Type: ${error.errorType}\n'
                  'Description: ${error.description}\n'
                  'URL: ${error.url ?? 'unknown'}',
              type: LogType.error,
            ));
          },
          onNavigationRequest: (request) {
            widget.onLog(LogEntry(
              title: '→ WebView — Navigation Request',
              body:
                  'URL: ${request.url}\nIs main frame: ${request.isMainFrame}',
              type: LogType.info,
            ));
            // Detect payment completion redirects
            final url = request.url.toLowerCase();
            if (url.contains('return_url') ||
                url.contains('callback') ||
                url.contains('success') ||
                url.contains('failure') ||
                url.contains('cancel')) {
              widget.onLog(LogEntry(
                title: '▼ WebView — Payment Redirect Detected',
                body: request.url,
                type: LogType.response,
              ));
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Attach HyperWebview — defer log only
    _hyperWebview.attach(_controller);
    _safeLog(LogEntry(
      title: '● WebView — HyperWebview Attached',
      body:
          'HyperWebviewFlutter attached to WebViewController.\nUserAgent: Hyper/track=cug',
      type: LogType.info,
    ));
  }

  @override
  void dispose() {
    widget.onLog(LogEntry(
      title: '● WebView — Screen Closed',
      body: 'Last URL: $_currentUrl',
      type: LogType.info,
    ));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08111E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF4DA3FF), size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PP — WebView',
              style: TextStyle(
                  color: Color(0xFFE8F4FF),
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              widget.orderId,
              style: const TextStyle(
                  color: Color(0xFF3A6080),
                  fontSize: 10,
                  fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF4DA3FF), size: 20),
            onPressed: () {
              _controller.reload();
              widget.onLog(LogEntry(
                title: '↺ WebView — Reloaded',
                body: _currentUrl,
                type: LogType.info,
              ));
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _isLoading
              ? LinearProgressIndicator(
                  value: _loadProgress > 0 ? _loadProgress / 100 : null,
                  backgroundColor: const Color(0xFF0F2540),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF0066FF)),
                  minHeight: 2,
                )
              : const SizedBox(height: 2),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          // URL bar at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF0B1A2E).withOpacity(0.95),
              child: Row(
                children: [
                  Icon(
                    _currentUrl.startsWith('https')
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    color: _currentUrl.startsWith('https')
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFFB74D),
                    size: 11,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _currentUrl,
                      style: const TextStyle(
                          color: Color(0xFF3A5070),
                          fontSize: 10,
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
