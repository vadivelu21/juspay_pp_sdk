import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hypersdkflutter/hypersdkflutter.dart';
import '../models/log_entry.dart';

class JuspayController {
  final HyperSDK hyperSDK = HyperSDK();
  final List<LogEntry> logs = [];
  final void Function(void Function()) setState;

  bool isInitiated = false;
  String? sdkPayload; // stores sdk_payload from session response

  JuspayController({required this.setState});

  void addLog(LogEntry entry) {
    setState(() {
      logs.insert(0, entry);
    });
  }

  void clearLogs() {
    setState(() => logs.clear());
  }

  // ─── STEP 1: Initiate SDK ────────────────────────────────────────────────
  Future<void> initiateSDK(Map<String, dynamic> initiatePayload) async {
    final payloadStr = jsonEncode(initiatePayload);
    addLog(LogEntry(
      title: 'Initiate SDK — Request',
      body: const JsonEncoder.withIndent('  ').convert(initiatePayload),
      type: LogType.request,
    ));

    try {
      await hyperSDK.initiate(payloadStr, _initiateCallbackHandler);
      addLog(LogEntry(
        title: 'Initiate SDK — Called',
        body: 'hyperSDK.initiate() triggered. Waiting for callback...',
        type: LogType.info,
      ));
    } catch (e) {
      addLog(LogEntry(
        title: 'Initiate SDK — Exception',
        body: e.toString(),
        type: LogType.error,
      ));
    }
  }

  void _initiateCallbackHandler(MethodCall methodCall) {
    if (methodCall.method == 'initiate_result') {
      Map<String, dynamic> result = {};
      try {
        result = jsonDecode(methodCall.arguments ?? '{}');
      } catch (_) {}

      final error = result['error'] ?? false;
      setState(() => isInitiated = !error);

      addLog(LogEntry(
        title: 'Initiate SDK — Callback',
        body: const JsonEncoder.withIndent('  ').convert(result),
        type: error ? LogType.error : LogType.success,
      ));
    } else {
      addLog(LogEntry(
        title: 'Initiate — ${methodCall.method}',
        body: methodCall.arguments?.toString() ?? '{}',
        type: LogType.info,
      ));
    }
  }

  // ─── STEP 2: Create Order via Session API ───────────────────────────────
  Future<Map<String, dynamic>> createSession({
    required String sessionUrl,
    required Map<String, dynamic> requestPayload,
    String? apiKey,
  }) async {
    addLog(LogEntry(
      title: 'Session API — Request',
      body: 'POST $sessionUrl\n\n'
          '${apiKey != null ? 'Authorization: Basic ***\n\n' : ''}'
          '${const JsonEncoder.withIndent('  ').convert(requestPayload)}',
      type: LogType.request,
    ));

    try {
      // NOTE: In production, this call MUST come from your backend.
      // For testing purposes, we do it from the app.
      final uri = Uri.parse(sessionUrl);
      final httpClient = _createHttpClient();
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (apiKey != null && apiKey.isNotEmpty) {
        final encoded = base64Encode(utf8.encode('$apiKey:'));
        headers['Authorization'] = 'Basic $encoded';
      }

      final response = await httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode(requestPayload),
      );

      final body = jsonDecode(response.body);
      final success = response.statusCode == 200;

      if (success && body['sdk_payload'] != null) {
        sdkPayload = jsonEncode(body['sdk_payload']);
        setState(() {});
      }

      addLog(LogEntry(
        title: 'Session API — Response [${response.statusCode}]',
        body: const JsonEncoder.withIndent('  ').convert(body),
        type: success ? LogType.response : LogType.error,
      ));

      if (success && body['sdk_payload'] != null) {
        addLog(LogEntry(
          title: 'sdk_payload extracted ✓',
          body: const JsonEncoder.withIndent('  ').convert(body['sdk_payload']),
          type: LogType.success,
        ));
      }

      return {'success': success, 'statusCode': response.statusCode, 'body': body};
    } catch (e) {
      addLog(LogEntry(
        title: 'Session API — Error',
        body: e.toString(),
        type: LogType.error,
      ));
      return {'success': false, 'error': e.toString()};
    }
  }

  _HttpClient _createHttpClient() => _HttpClient();

  // ─── STEP 3: Process ────────────────────────────────────────────────────
  Future<void> processPayment(Map<String, dynamic> processPayload) async {
    final payloadStr = jsonEncode(processPayload);
    addLog(LogEntry(
      title: 'Process — Request',
      body: const JsonEncoder.withIndent('  ').convert(processPayload),
      type: LogType.request,
    ));

    try {
      final initiated = await hyperSDK.isInitialised();
      if (!initiated) {
        addLog(LogEntry(
          title: 'Process — Blocked',
          body: 'SDK is not yet initiated. Please initiate first.',
          type: LogType.error,
        ));
        return;
      }
      await hyperSDK.process(payloadStr, _processCallbackHandler);
      addLog(LogEntry(
        title: 'Process — Called',
        body: 'hyperSDK.process() triggered. Waiting for callback...',
        type: LogType.info,
      ));
    } catch (e) {
      addLog(LogEntry(
        title: 'Process — Exception',
        body: e.toString(),
        type: LogType.error,
      ));
    }
  }

  void _processCallbackHandler(MethodCall methodCall) {
    switch (methodCall.method) {
      case 'hide_loader':
        addLog(LogEntry(
          title: 'Process — hide_loader',
          body: 'SDK requesting loader to be hidden.',
          type: LogType.info,
        ));
        break;
      case 'process_result':
        Map<String, dynamic> args = {};
        try {
          args = jsonDecode(methodCall.arguments ?? '{}');
        } catch (_) {}

        final error = args['error'] ?? false;
        final innerPayload = args['payload'] ?? {};
        final status = innerPayload['status'] ?? '';

        addLog(LogEntry(
          title: 'Process — Result [status: $status]',
          body: const JsonEncoder.withIndent('  ').convert(args),
          type: _statusToLogType(error, status),
        ));
        break;
      default:
        addLog(LogEntry(
          title: 'Process — ${methodCall.method}',
          body: methodCall.arguments?.toString() ?? '',
          type: LogType.info,
        ));
    }
  }

  LogType _statusToLogType(bool error, String status) {
    if (status == 'charged') return LogType.success;
    if (error) return LogType.error;
    if (status == 'backpressed' || status == 'user_aborted') return LogType.info;
    return LogType.response;
  }

  Future<void> terminateSDK() async {
    await hyperSDK.terminate();
    setState(() => isInitiated = false);
    addLog(LogEntry(
      title: 'SDK Terminated',
      body: 'hyperSDK.terminate() called.',
      type: LogType.info,
    ));
  }

  Future<bool> checkIsInitialised() async {
    final result = await hyperSDK.isInitialised();
    addLog(LogEntry(
      title: 'isInitialised()',
      body: 'Result: $result',
      type: result ? LogType.success : LogType.info,
    ));
    return result;
  }

  Future<void> onBackPress() async {
    await hyperSDK.onBackPress();
  }
}

// Minimal HTTP client wrapper (uses dart:io via http package in actual app)
class _HttpClient {
  Future<_Response> post(
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    // This will be replaced by the actual http package call
    throw UnimplementedError('Use http package in actual app');
  }
}

class _Response {
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
}
