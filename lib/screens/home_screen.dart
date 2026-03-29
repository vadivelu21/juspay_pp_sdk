import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hypersdkflutter/hypersdkflutter.dart';
import 'package:http/http.dart' as http;
import '../models/log_entry.dart';
import '../widgets/log_panel.dart';
import '../widgets/json_input_field.dart';
import 'payment_webview_screen.dart';
import 'pp_signature_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _generateUuidV4() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int x) => x.toRadixString(16).padLeft(2, '0');
  return '${h(b[0])}${h(b[1])}${h(b[2])}${h(b[3])}'
      '-${h(b[4])}${h(b[5])}'
      '-${h(b[6])}${h(b[7])}'
      '-${h(b[8])}${h(b[9])}'
      '-${h(b[10])}${h(b[11])}${h(b[12])}${h(b[13])}${h(b[14])}${h(b[15])}';
}

String _generateOrderId() => 't${DateTime.now().millisecondsSinceEpoch}';

Map<String, dynamic> _buildInitiatePayload() => {
      'requestId': _generateUuidV4(),
      'service': 'in.juspay.hyperpay',
      'payload': {
        'action': 'initiate',
        'clientId': 'msprod',
        'merchantId': 'Testvadivel',
        'customerId': 'customer_001',
        'customerEmail': 'test@example.com',
        'customerMobile': '9999999999',
        'environment': 'sandbox',
      },
    };

Map<String, dynamic> _buildSessionPayload() => {
      'order_id': _generateOrderId(),
      'amount': 1000,
      'currency': 'INR',
      'customer_id': 'customer_001',
      'customer_email': 'test@example.com',
      'customer_phone': '9999999999',
      'payment_page_client_id': 'msprod',
      'action': 'paymentPage',
      'return_url': 'https://your-app.com/payment/callback',
      'description': 'Test Order',
    };

const _defaultSessionUrl = 'https://sandbox.juspay.in/session';
const _enc = JsonEncoder.withIndent('  ');

// ─────────────────────────────────────────────────────────────────────────────
// EC SDK pre-filled payload templates
// clientAuthToken is replaced dynamically after Get Customer API call
// ─────────────────────────────────────────────────────────────────────────────

const _ecPayloadTemplates = <String, Map<String, dynamic>>{
  'Display Payment Options': {
    'requestId': '__UUID__',
    'service': 'in.juspay.ec',
    'payload': {
      'action': 'getPaymentMethods',
      'merchantId': 'Testvadivel',
      'clientId': 'msprod',
      'clientAuthToken': '__CLIENT_AUTH_TOKEN__',
      'environment': 'sandbox',
      'customerId': 'cth_8XSdhGQvbNV59QY4',
      'options.getClientAuthToken': 'true',
    },
  },
  'Card Transaction': {
    'requestId': '__UUID__',
    'service': 'in.juspay.ec',
    'payload': {
      'action': 'cardTxn',
      'merchantId': 'Testvadivel',
      'clientId': 'msprod',
      'clientAuthToken': '__CLIENT_AUTH_TOKEN__',
      'environment': 'sandbox',
      'orderId': '__ORDER_ID__',
      'amount': '10.00',
      'currency': 'INR',
      'customerId': 'cth_8XSdhGQvbNV59QY4',
      'customerEmail': 'test@example.com',
      'customerMobile': '9999999999',
      'paymentMethodType': 'CARD',
      'cardNumber': '4111111111111111',
      'cardExpMonth': '12',
      'cardExpYear': '2026',
      'cardSecurityCode': '123',
      'cardHolderName': 'Test User',
      'saveToLocker': false,
      'redirectAfterPayment': true,
      'format': 'json',
    },
  },
  'UPI Collect': {
    'requestId': '__UUID__',
    'service': 'in.juspay.ec',
    'payload': {
      'action': 'upiTxn',
      'merchantId': 'Testvadivel',
      'clientId': 'msprod',
      'clientAuthToken': '__CLIENT_AUTH_TOKEN__',
      'environment': 'sandbox',
      'orderId': '__ORDER_ID__',
      'amount': '10.00',
      'currency': 'INR',
      'customerId': 'cth_8XSdhGQvbNV59QY4',
      'customerEmail': 'test@example.com',
      'customerMobile': '9999999999',
      'paymentMethodType': 'UPI',
      'paymentMethod': 'UPI',
      'upiVpa': 'test@upi',
      'redirectAfterPayment': true,
      'format': 'json',
    },
  },
  'Net Banking': {
    'requestId': '__UUID__',
    'service': 'in.juspay.ec',
    'payload': {
      'action': 'nbTxn',
      'merchantId': 'Testvadivel',
      'clientId': 'msprod',
      'clientAuthToken': '__CLIENT_AUTH_TOKEN__',
      'environment': 'sandbox',
      'orderId': '__ORDER_ID__',
      'amount': '10.00',
      'currency': 'INR',
      'customerId': 'cth_8XSdhGQvbNV59QY4',
      'customerEmail': 'test@example.com',
      'customerMobile': '9999999999',
      'paymentMethodType': 'NB',
      'paymentMethod': 'NB_SBI',
      'redirectAfterPayment': true,
      'format': 'json',
    },
  },
  'List Saved Cards': {
    'requestId': '__UUID__',
    'service': 'in.juspay.ec',
    'payload': {
      'action': 'listCards',
      'merchantId': 'Testvadivel',
      'clientId': 'msprod',
      'clientAuthToken': '__CLIENT_AUTH_TOKEN__',
      'environment': 'sandbox',
      'customerId': 'cth_8XSdhGQvbNV59QY4',
    },
  },
  'Custom (Edit below)': <String, dynamic>{},
};

Map<String, dynamic> _fillTemplate(
    Map<String, dynamic> template, String clientAuthToken) {
  final filled = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
  filled['requestId'] = _generateUuidV4();

  void replace(Map<String, dynamic> map) {
    for (final key in map.keys) {
      if (map[key] is String) {
        if (map[key] == '__CLIENT_AUTH_TOKEN__') map[key] = clientAuthToken;
        if (map[key] == '__UUID__') map[key] = _generateUuidV4();
        if (map[key] == '__ORDER_ID__') map[key] = _generateOrderId();
      } else if (map[key] is Map<String, dynamic>) {
        replace(map[key] as Map<String, dynamic>);
      }
    }
  }

  replace(filled);
  return filled;
}

// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final hyperSDK = HyperSDK();
  bool _isInitiated = false;
  String? _extractedSdkPayload;

  final List<LogEntry> _logs = [];
  late TabController _tabController;

  // Integration tab controllers
  late final TextEditingController _sessionUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _initiateJsonCtrl;
  late final TextEditingController _sessionJsonCtrl;
  final TextEditingController _processJsonCtrl = TextEditingController();

  // EC SDK tab controllers
  late final TextEditingController _ecPayloadCtrl;
  String _selectedEcTemplate = 'Display Payment Options';
  String _ecClientAuthToken = '';
  String _ecClientAuthTokenExpiry = '';
  bool _ecFetchingToken = false;
  bool _ecProcessing = false;

  // EC Create Order form
  final _ecOrderIdCtrl =
      TextEditingController(text: 't\${DateTime.now().millisecondsSinceEpoch}');
  final _ecAmountCtrl = TextEditingController(text: '10.00');
  final _ecCustomerIdCtrl = TextEditingController(text: 'cth_8XSdhGQvbNV59QY4');
  final _ecCustomerEmailCtrl = TextEditingController(text: 'test@example.com');
  final _ecCustomerMobileCtrl = TextEditingController(text: '9999999999');
  bool _ecGetClientAuthToken = true;
  // Optional order fields
  final Map<String, bool> _ecOrderOptEnabled = {
    'customer_email': true,
    'customer_phone': true,
    'currency': true,
    'description': false,
    'return_url': false,
    'product_id': false,
    'billing_address_first_name': false,
    'billing_address_last_name': false,
    'billing_address_line1': false,
    'billing_address_city': false,
    'billing_address_state': false,
    'billing_address_country': false,
    'billing_address_postal_code': false,
    'billing_address_phone': false,
    'shipping_address_first_name': false,
    'gateway_id': false,
    'order_type': false,
    'metadata_gateway_ref': false,
    'metadata_subvention': false,
    'metadata_webhook': false,
    'udf1': false,
    'udf2': false,
    'udf3': false,
    'udf4': false,
    'udf5': false,
    'udf6': false,
    'udf7': false,
    'udf8': false,
    'udf9': false,
    'udf10': false,
  };
  final _ecCurrencyCtrl = TextEditingController(text: 'INR');
  final _ecDescriptionCtrl = TextEditingController(text: '');
  final _ecReturnUrlCtrl = TextEditingController(text: '');
  final _ecProductIdCtrl = TextEditingController(text: '');
  final _ecBillingFnCtrl = TextEditingController(text: '');
  final _ecBillingLnCtrl = TextEditingController(text: '');
  final _ecBillingLine1Ctrl = TextEditingController(text: '');
  final _ecBillingCityCtrl = TextEditingController(text: '');
  final _ecBillingStateCtrl = TextEditingController(text: '');
  final _ecBillingCountryCtrl = TextEditingController(text: 'India');
  final _ecBillingPostalCtrl = TextEditingController(text: '');
  final _ecBillingPhoneCtrl = TextEditingController(text: '');
  final _ecShipFnCtrl = TextEditingController(text: '');
  final _ecUdf1Ctrl = TextEditingController(text: '');
  final _ecUdf2Ctrl = TextEditingController(text: '');
  final _ecUdf3Ctrl = TextEditingController(text: '');
  final _ecUdf4Ctrl = TextEditingController(text: '');
  final _ecUdf5Ctrl = TextEditingController(text: '');
  final _ecUdf6Ctrl = TextEditingController(text: '');
  final _ecUdf7Ctrl = TextEditingController(text: '');
  final _ecUdf8Ctrl = TextEditingController(text: '');
  final _ecUdf9Ctrl = TextEditingController(text: '');
  final _ecUdf10Ctrl = TextEditingController(text: '');
  // Metadata extra fields
  final _ecGatewayIdCtrl = TextEditingController(text: '');
  final _ecOrderTypeCtrl = TextEditingController(text: '');
  final _ecGatewayRefIdCtrl = TextEditingController(text: '');
  final _ecSubventionAmtCtrl = TextEditingController(text: '');
  final _ecWebhookUrlCtrl = TextEditingController(text: '');
  // Bank account details
  final _ecBankAccNumCtrl = TextEditingController(text: '');
  final _ecBankIfscCtrl = TextEditingController(text: '');
  final _ecBankCodeCtrl = TextEditingController(text: '');
  final _ecBankBenCtrl = TextEditingController(text: '');
  final _ecBankAccIdCtrl = TextEditingController(text: '');
  final _ecBankAccTypeCtrl = TextEditingController(text: 'SAVINGS');
  bool _ecBankAccountEnabled = false;
  // Mutual fund details
  final _ecMfMemberIdCtrl = TextEditingController(text: '');
  final _ecMfUserIdCtrl = TextEditingController(text: '');
  final _ecMfPartnerCtrl = TextEditingController(text: 'NSE');
  final _ecMfOrderNumCtrl = TextEditingController(text: '');
  final _ecMfAmountCtrl = TextEditingController(text: '');
  final _ecMfInvTypeCtrl = TextEditingController(text: 'LUMPSUM');
  final _ecMfFolioCtrl = TextEditingController(text: '');
  final _ecMfPanCtrl = TextEditingController(text: '');
  final _ecMfAmcCodeCtrl = TextEditingController(text: '');
  final _ecMfSchemeCodeCtrl = TextEditingController(text: '');
  final _ecMfIhNumberCtrl = TextEditingController(text: '');
  bool _ecMutualFundEnabled = false;
  // Collapsed state
  bool _ecBillingExpanded = false;
  bool _ecUdfExpanded = false;
  // Custom extra fields
  final List<Map<String, TextEditingController>> _ecExtraFields = [];

  // Loading states
  bool _initiating = false;
  bool _sessionLoading = false;
  bool _processing = false;

  // WebView
  bool _webviewSessionLoading = false;
  String? _webviewPaymentUrl;
  String? _webviewOrderId;
  String? _webviewExpiry;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _sessionUrlCtrl = TextEditingController(text: _defaultSessionUrl);
    _apiKeyCtrl = TextEditingController();
    _initiateJsonCtrl =
        TextEditingController(text: _enc.convert(_buildInitiatePayload()));
    _sessionJsonCtrl =
        TextEditingController(text: _enc.convert(_buildSessionPayload()));
    _ecPayloadCtrl = TextEditingController(
        text: _enc.convert(_fillTemplate(
            _ecPayloadTemplates['Display Payment Options']!, '')));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sessionUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _initiateJsonCtrl.dispose();
    _sessionJsonCtrl.dispose();
    _processJsonCtrl.dispose();
    _ecOrderIdCtrl.dispose();
    _ecAmountCtrl.dispose();
    _ecCustomerIdCtrl.dispose();
    _ecCustomerEmailCtrl.dispose();
    _ecCustomerMobileCtrl.dispose();
    _ecCurrencyCtrl.dispose();
    _ecDescriptionCtrl.dispose();
    _ecReturnUrlCtrl.dispose();
    _ecProductIdCtrl.dispose();
    _ecBillingFnCtrl.dispose();
    _ecBillingLnCtrl.dispose();
    _ecBillingLine1Ctrl.dispose();
    _ecBillingCityCtrl.dispose();
    _ecBillingStateCtrl.dispose();
    _ecBillingCountryCtrl.dispose();
    _ecBillingPostalCtrl.dispose();
    _ecBillingPhoneCtrl.dispose();
    _ecShipFnCtrl.dispose();
    _ecUdf1Ctrl.dispose();
    _ecUdf2Ctrl.dispose();
    _ecUdf3Ctrl.dispose();
    _ecUdf4Ctrl.dispose();
    _ecUdf5Ctrl.dispose();
    _ecUdf6Ctrl.dispose();
    _ecUdf7Ctrl.dispose();
    _ecUdf8Ctrl.dispose();
    _ecUdf9Ctrl.dispose();
    _ecUdf10Ctrl.dispose();
    _ecGatewayIdCtrl.dispose();
    _ecOrderTypeCtrl.dispose();
    _ecGatewayRefIdCtrl.dispose();
    _ecSubventionAmtCtrl.dispose();
    _ecWebhookUrlCtrl.dispose();
    _ecBankAccNumCtrl.dispose();
    _ecBankIfscCtrl.dispose();
    _ecBankCodeCtrl.dispose();
    _ecBankBenCtrl.dispose();
    _ecBankAccIdCtrl.dispose();
    _ecBankAccTypeCtrl.dispose();
    _ecMfMemberIdCtrl.dispose();
    _ecMfUserIdCtrl.dispose();
    _ecMfPartnerCtrl.dispose();
    _ecMfOrderNumCtrl.dispose();
    _ecMfAmountCtrl.dispose();
    _ecMfInvTypeCtrl.dispose();
    _ecMfFolioCtrl.dispose();
    _ecMfPanCtrl.dispose();
    _ecMfAmcCodeCtrl.dispose();
    _ecMfSchemeCodeCtrl.dispose();
    _ecMfIhNumberCtrl.dispose();
    _ecPayloadCtrl.dispose();
    super.dispose();
  }

  // ─── Refresh helpers ──────────────────────────────────────────────────────
  void _refreshInitiateId() {
    try {
      final m = jsonDecode(_initiateJsonCtrl.text) as Map<String, dynamic>;
      m['requestId'] = _generateUuidV4();
      setState(() => _initiateJsonCtrl.text = _enc.convert(m));
    } catch (_) {}
  }

  void _refreshOrderId() {
    try {
      final m = jsonDecode(_sessionJsonCtrl.text) as Map<String, dynamic>;
      m['order_id'] = _generateOrderId();
      setState(() => _sessionJsonCtrl.text = _enc.convert(m));
    } catch (_) {}
  }

  // ─── Logging ──────────────────────────────────────────────────────────────
  void _log(LogEntry e) => setState(() => _logs.insert(0, e));
  void _clearLogs() => setState(() => _logs.clear());

  // ─── PP WebView: Create session and open WebView ──────────────────────────
  Future<void> _launchWebViewPayment() async {
    Map<String, dynamic> reqPayload;
    try {
      reqPayload = jsonDecode(_sessionJsonCtrl.text);
    } catch (e) {
      _log(LogEntry(
          title: 'WebView Session — Invalid JSON',
          body: e.toString(),
          type: LogType.error));
      return;
    }

    // Ensure fresh order_id
    reqPayload['order_id'] = _generateOrderId();
    setState(() {
      _sessionJsonCtrl.text = _enc.convert(reqPayload);
      _webviewSessionLoading = true;
    });

    final url = _sessionUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$apiKey:'))}';
    }

    _log(LogEntry(
      title: '▲ WebView Session — POST $url',
      body: (apiKey.isNotEmpty ? 'Authorization: Basic ***\n\n' : '') +
          _enc.convert(reqPayload),
      type: LogType.request,
    ));

    try {
      final res = await http.post(Uri.parse(url),
          headers: headers, body: jsonEncode(reqPayload));
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        body = {'raw': res.body};
      }

      final ok = res.statusCode == 200 || res.statusCode == 201;
      _log(LogEntry(
        title: '▼ WebView Session — Response [HTTP ${res.statusCode}]',
        body: _enc.convert(body),
        type: ok ? LogType.response : LogType.error,
      ));

      if (ok && body['payment_links'] != null) {
        final paymentLinks = body['payment_links'] as Map<String, dynamic>;
        final webUrl = paymentLinks['web'] as String? ?? '';
        final expiry = paymentLinks['expiry'] as String? ?? '';
        final orderId = body['order_id'] as String? ??
            reqPayload['order_id']?.toString() ??
            '';

        setState(() {
          _webviewPaymentUrl = webUrl;
          _webviewOrderId = orderId;
          _webviewExpiry = expiry;
        });

        _log(LogEntry(
          title: '✓ Payment Link Ready',
          body: 'Order ID: $orderId\nURL: $webUrl\nExpiry: $expiry',
          type: LogType.success,
        ));

        if (webUrl.isNotEmpty && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaymentWebviewScreen(
                url: webUrl,
                orderId: orderId,
                onLog: _log,
              ),
            ),
          );
        }
      } else {
        _log(LogEntry(
          title: '✕ WebView Session — No payment_links in response',
          body: _enc.convert(body),
          type: LogType.error,
        ));
      }
    } catch (e) {
      _log(LogEntry(
          title: 'WebView Session — Network Error',
          body: e.toString(),
          type: LogType.error));
    } finally {
      setState(() => _webviewSessionLoading = false);
    }
  }

  // ─── Step 1: Initiate ─────────────────────────────────────────────────────
  Future<void> _initiateSDK() async {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(_initiateJsonCtrl.text);
    } catch (e) {
      _log(LogEntry(
          title: 'Initiate — Invalid JSON',
          body: e.toString(),
          type: LogType.error));
      return;
    }
    setState(() => _initiating = true);
    _log(LogEntry(
        title: '▲ Initiate SDK — Payload',
        body: _enc.convert(payload),
        type: LogType.request));
    try {
      await hyperSDK.initiate(payload, _initiateCallback);
      _log(LogEntry(
          title: 'Initiate SDK — Called',
          body: 'Awaiting callback...',
          type: LogType.info));
    } catch (e) {
      _log(LogEntry(
          title: 'Initiate SDK — Exception',
          body: e.toString(),
          type: LogType.error));
    } finally {
      setState(() => _initiating = false);
    }
  }

  void _initiateCallback(MethodCall methodCall) {
    if (methodCall.method == 'initiate_result') {
      Map<String, dynamic> result = {};
      try {
        result = methodCall.arguments is String
            ? jsonDecode(methodCall.arguments)
            : Map<String, dynamic>.from(methodCall.arguments ?? {});
      } catch (_) {}
      final error = result['error'] ?? false;
      setState(() => _isInitiated = !error);
      _log(LogEntry(
        title: error ? '✕ Initiate — Failed' : '✓ Initiate — Success',
        body: _enc.convert(result),
        type: error ? LogType.error : LogType.success,
      ));
    } else {
      _log(LogEntry(
          title: 'Initiate ← ${methodCall.method}',
          body: methodCall.arguments?.toString() ?? '',
          type: LogType.info));
    }
  }

  // ─── Step 2: Session API ──────────────────────────────────────────────────
  Future<void> _createSession() async {
    Map<String, dynamic> reqPayload;
    try {
      reqPayload = jsonDecode(_sessionJsonCtrl.text);
    } catch (e) {
      _log(LogEntry(
          title: 'Session API — Invalid JSON',
          body: e.toString(),
          type: LogType.error));
      return;
    }
    final url = _sessionUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    setState(() => _sessionLoading = true);

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$apiKey:'))}';
    }
    _log(LogEntry(
      title: '▲ Session API — POST $url',
      body: (apiKey.isNotEmpty ? 'Authorization: Basic ***\n\n' : '') +
          _enc.convert(reqPayload),
      type: LogType.request,
    ));
    try {
      final res = await http.post(Uri.parse(url),
          headers: headers, body: jsonEncode(reqPayload));
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        body = {'raw': res.body};
      }
      final ok = res.statusCode == 200 || res.statusCode == 201;
      _log(LogEntry(
          title: '▼ Session — Response [HTTP ${res.statusCode}]',
          body: _enc.convert(body),
          type: ok ? LogType.response : LogType.error));
      if (ok && body['sdk_payload'] != null) {
        setState(() {
          _extractedSdkPayload = _enc.convert(body['sdk_payload']);
          _processJsonCtrl.text = _extractedSdkPayload!;
        });
        _log(LogEntry(
            title: '✓ sdk_payload Extracted',
            body: _extractedSdkPayload!,
            type: LogType.success));
      }
    } catch (e) {
      _log(LogEntry(
          title: 'Session API — Network Error',
          body: e.toString(),
          type: LogType.error));
    } finally {
      setState(() => _sessionLoading = false);
    }
  }

  // ─── Step 3: Process (Integration tab) ───────────────────────────────────
  Future<void> _processPayment() async {
    if (!_isInitiated) {
      _log(LogEntry(
          title: 'Process — Blocked',
          body: 'Initiate SDK first.',
          type: LogType.error));
      return;
    }
    Map<String, dynamic> processPayload;
    try {
      processPayload = jsonDecode(_processJsonCtrl.text);
    } catch (e) {
      _log(LogEntry(
          title: 'Process — Invalid JSON',
          body: e.toString(),
          type: LogType.error));
      return;
    }
    setState(() => _processing = true);
    _log(LogEntry(
        title: '▲ Process — Payload',
        body: _enc.convert(processPayload),
        type: LogType.request));
    try {
      // ignore: unawaited_futures
      hyperSDK.process(processPayload, _processCallback);
      _log(LogEntry(
          title: 'Process — Called',
          body: 'Awaiting callback...',
          type: LogType.info));
    } catch (e) {
      _log(LogEntry(
          title: 'Process — Exception',
          body: e.toString(),
          type: LogType.error));
    } finally {
      setState(() => _processing = false);
    }
  }

  void _processCallback(MethodCall methodCall) {
    _handleProcessMethodCall(methodCall, tag: 'PP');
  }

  // ─── EC SDK: Create Order API ───────────────────────────────────────────────
  void _ecRefreshOrderId() {
    setState(() =>
        _ecOrderIdCtrl.text = 't${DateTime.now().millisecondsSinceEpoch}');
  }

  Future<void> _createEcOrder() async {
    final apiKey = _apiKeyCtrl.text.trim();
    if (apiKey.isEmpty) {
      _log(LogEntry(
          title: 'EC Create Order — Error',
          body: 'API Key required (set in Integration tab Step 02).',
          type: LogType.error));
      return;
    }
    setState(() => _ecFetchingToken = true);

    const url = 'https://sandbox.juspay.in/orders';
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': 'Basic ${base64Encode(utf8.encode('$apiKey:'))}',
      'x-merchantid': 'Testvadivel',
    };

    final reqBody = <String, String>{
      'order_id': _ecOrderIdCtrl.text.trim(),
      'amount': _ecAmountCtrl.text.trim(),
      'customer_id': _ecCustomerIdCtrl.text.trim(),
      'options.get_client_auth_token': _ecGetClientAuthToken.toString(),
    };

    bool optEnabled(String k) => _ecOrderOptEnabled[k] == true;
    void addOpt(String k, TextEditingController ctrl) {
      if (optEnabled(k) && ctrl.text.isNotEmpty) reqBody[k] = ctrl.text.trim();
    }

    addOpt('customer_email', _ecCustomerEmailCtrl);
    addOpt('customer_phone', _ecCustomerMobileCtrl);
    addOpt('currency', _ecCurrencyCtrl);
    addOpt('description', _ecDescriptionCtrl);
    addOpt('return_url', _ecReturnUrlCtrl);
    addOpt('product_id', _ecProductIdCtrl);
    addOpt('billing_address_first_name', _ecBillingFnCtrl);
    addOpt('billing_address_last_name', _ecBillingLnCtrl);
    addOpt('billing_address_line1', _ecBillingLine1Ctrl);
    addOpt('billing_address_city', _ecBillingCityCtrl);
    addOpt('billing_address_state', _ecBillingStateCtrl);
    addOpt('billing_address_country', _ecBillingCountryCtrl);
    addOpt('billing_address_postal_code', _ecBillingPostalCtrl);
    addOpt('billing_address_phone', _ecBillingPhoneCtrl);
    addOpt('shipping_address_first_name', _ecShipFnCtrl);
    addOpt('gateway_id', _ecGatewayIdCtrl);
    addOpt('order_type', _ecOrderTypeCtrl);
    if (optEnabled('metadata_gateway_ref') &&
        _ecGatewayRefIdCtrl.text.isNotEmpty)
      reqBody['metadata.JUSPAY:gateway_reference_id'] =
          _ecGatewayRefIdCtrl.text.trim();
    if (optEnabled('metadata_subvention') &&
        _ecSubventionAmtCtrl.text.isNotEmpty)
      reqBody['metadata.subvention_amount'] = _ecSubventionAmtCtrl.text.trim();
    if (optEnabled('metadata_webhook') && _ecWebhookUrlCtrl.text.isNotEmpty)
      reqBody['metadata.webhook_url'] = _ecWebhookUrlCtrl.text.trim();
    if (_ecBankAccountEnabled && _ecBankAccNumCtrl.text.isNotEmpty) {
      reqBody['metadata.bank_account_details[0].bank_account_number'] =
          _ecBankAccNumCtrl.text.trim();
      if (_ecBankIfscCtrl.text.isNotEmpty)
        reqBody['metadata.bank_account_details[0].bank_ifsc'] =
            _ecBankIfscCtrl.text.trim();
      if (_ecBankCodeCtrl.text.isNotEmpty)
        reqBody['metadata.bank_account_details[0].juspay_bank_code'] =
            _ecBankCodeCtrl.text.trim();
      if (_ecBankBenCtrl.text.isNotEmpty)
        reqBody['metadata.bank_account_details[0].bank_beneficiary_name'] =
            _ecBankBenCtrl.text.trim();
      if (_ecBankAccIdCtrl.text.isNotEmpty)
        reqBody['metadata.bank_account_details[0].bank_account_id'] =
            _ecBankAccIdCtrl.text.trim();
      if (_ecBankAccTypeCtrl.text.isNotEmpty)
        reqBody['metadata.bank_account_details[0].bank_account_type'] =
            _ecBankAccTypeCtrl.text.trim();
    }
    if (_ecMutualFundEnabled && _ecMfMemberIdCtrl.text.isNotEmpty) {
      final mf = {
        'memberId': _ecMfMemberIdCtrl.text.trim(),
        'userId': _ecMfUserIdCtrl.text.trim(),
        'mfPartner': _ecMfPartnerCtrl.text.trim(),
        'orderNumber': _ecMfOrderNumCtrl.text.trim(),
        'amount': _ecMfAmountCtrl.text.trim(),
        'investmentType': _ecMfInvTypeCtrl.text.trim(),
        if (_ecMfFolioCtrl.text.isNotEmpty)
          'folioNumber': _ecMfFolioCtrl.text.trim(),
        if (_ecMfPanCtrl.text.isNotEmpty) 'panNumber': _ecMfPanCtrl.text.trim(),
        if (_ecMfAmcCodeCtrl.text.isNotEmpty)
          'amcCode': _ecMfAmcCodeCtrl.text.trim(),
        if (_ecMfSchemeCodeCtrl.text.isNotEmpty)
          'schemeCode': _ecMfSchemeCodeCtrl.text.trim(),
        if (_ecMfIhNumberCtrl.text.isNotEmpty)
          'ihNumber': _ecMfIhNumberCtrl.text.trim(),
      };
      reqBody['mutual_fund_details'] = jsonEncode([mf]);
    }
    addOpt('udf1', _ecUdf1Ctrl);
    addOpt('udf2', _ecUdf2Ctrl);
    addOpt('udf3', _ecUdf3Ctrl);
    addOpt('udf4', _ecUdf4Ctrl);
    addOpt('udf5', _ecUdf5Ctrl);
    addOpt('udf6', _ecUdf6Ctrl);
    addOpt('udf7', _ecUdf7Ctrl);
    addOpt('udf8', _ecUdf8Ctrl);
    addOpt('udf9', _ecUdf9Ctrl);
    addOpt('udf10', _ecUdf10Ctrl);
    for (final f in _ecExtraFields) {
      final k = f['key']!.text.trim();
      final v = f['value']!.text.trim();
      if (k.isNotEmpty) reqBody[k] = v;
    }

    final formEncoded = reqBody.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    _log(LogEntry(
      title: '▲ Create Order — POST $url',
      body:
          'Authorization: Basic ***\n\n${reqBody.entries.map((e) => "${e.key}: ${e.value}").join("\n")}',
      type: LogType.request,
    ));

    try {
      final res =
          await http.post(Uri.parse(url), headers: headers, body: formEncoded);
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        body = {'raw': res.body};
      }
      final ok = res.statusCode == 200 || res.statusCode == 201;
      _log(LogEntry(
        title: '▼ Create Order — Response [HTTP ${res.statusCode}]',
        body: _enc.convert(body),
        type: ok ? LogType.response : LogType.error,
      ));
      if (ok && body['juspay'] != null) {
        final token = body['juspay']['client_auth_token'] as String? ?? '';
        final expiry =
            body['juspay']['client_auth_token_expiry'] as String? ?? '';
        setState(() {
          _ecClientAuthToken = token;
          _ecClientAuthTokenExpiry = expiry;
        });
        _log(LogEntry(
          title: '✓ clientAuthToken from Create Order',
          body: 'Token: $token\nExpiry: $expiry',
          type: LogType.success,
        ));
        _applyEcTemplate(_selectedEcTemplate);
      } else {
        _log(LogEntry(
            title: '✕ Create Order — No client_auth_token',
            body: _enc.convert(body),
            type: LogType.error));
      }
    } catch (e) {
      _log(LogEntry(
          title: 'Create Order — Network Error',
          body: e.toString(),
          type: LogType.error));
    } finally {
      setState(() => _ecFetchingToken = false);
    }
  }

  // ─── EC SDK: Apply template — injects token + order form values ─────────────
  void _applyEcTemplate(String templateName) {
    setState(() => _selectedEcTemplate = templateName);
    if (templateName == 'Custom (Edit below)') return;
    final template = _ecPayloadTemplates[templateName];
    if (template == null) return;
    final filled = _fillTemplate(template, _ecClientAuthToken);
    // Inject form values into payload
    final p = filled['payload'] as Map<String, dynamic>? ?? {};
    if (p.containsKey('orderId')) p['orderId'] = _ecOrderIdCtrl.text.trim();
    if (p.containsKey('amount') &&
        templateName != 'List Saved Cards' &&
        templateName != 'Display Payment Options')
      p['amount'] = _ecAmountCtrl.text.trim();
    if (p.containsKey('customerId'))
      p['customerId'] = _ecCustomerIdCtrl.text.trim();
    if (p.containsKey('customerEmail'))
      p['customerEmail'] = _ecCustomerEmailCtrl.text.trim();
    if (p.containsKey('customerMobile'))
      p['customerMobile'] = _ecCustomerMobileCtrl.text.trim();
    if (p.containsKey('currency')) p['currency'] = _ecCurrencyCtrl.text.trim();
    setState(() => _ecPayloadCtrl.text = _enc.convert(filled));
  }

  void _refreshEcRequestId() {
    try {
      final m = jsonDecode(_ecPayloadCtrl.text) as Map<String, dynamic>;
      m['requestId'] = _generateUuidV4();
      setState(() => _ecPayloadCtrl.text = _enc.convert(m));
    } catch (_) {}
  }

  // ─── EC SDK: Process ──────────────────────────────────────────────────────
  Future<void> _ecProcess() async {
    if (!_isInitiated) {
      _log(LogEntry(
          title: 'EC Process — Blocked',
          body: 'SDK must be initiated first.',
          type: LogType.error));
      return;
    }
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(_ecPayloadCtrl.text);
    } catch (e) {
      _log(LogEntry(
          title: 'EC Process — Invalid JSON',
          body: e.toString(),
          type: LogType.error));
      return;
    }
    setState(() => _ecProcessing = true);
    _log(LogEntry(
        title: '▲ EC Process — Payload',
        body: _enc.convert(payload),
        type: LogType.request));
    try {
      // ignore: unawaited_futures
      hyperSDK.process(payload, _ecProcessCallback);
      _log(LogEntry(
          title: 'EC Process — Called',
          body: 'Awaiting callback...',
          type: LogType.info));
    } catch (e) {
      _log(LogEntry(
          title: 'EC Process — Exception',
          body: e.toString(),
          type: LogType.error));
    } finally {
      setState(() => _ecProcessing = false);
    }
  }

  void _ecProcessCallback(MethodCall methodCall) {
    _handleProcessMethodCall(methodCall, tag: 'EC');
  }

  // ─── Shared process callback handler ─────────────────────────────────────
  void _handleProcessMethodCall(MethodCall methodCall, {required String tag}) {
    switch (methodCall.method) {
      case 'hide_loader':
        _log(LogEntry(
            title: '[$tag] hide_loader',
            body: 'SDK requests loader hidden.',
            type: LogType.info));
        break;
      case 'process_result':
        Map<String, dynamic> args = {};
        try {
          args = methodCall.arguments is String
              ? jsonDecode(methodCall.arguments)
              : Map<String, dynamic>.from(methodCall.arguments ?? {});
        } catch (_) {}
        final error = args['error'] ?? false;
        final inner = (args['payload'] as Map?)?.cast<String, dynamic>() ?? {};
        final status = inner['status'] ?? '';
        final errorCode = args['errorCode'] ?? '';
        final errorMessage = args['errorMessage'] ?? '';
        _log(LogEntry(
          title:
              '▼ [$tag] Process Result — "$status"${errorCode.isNotEmpty ? ' | $errorCode' : ''}',
          body: _enc.convert(args),
          type: _resolveLogType(error, status),
        ));
        if (status == 'charged') {
          _log(LogEntry(
              title: '✓ [$tag] Payment Successful!',
              body: 'Verify via S2S order status API.',
              type: LogType.success));
        } else if (error && errorMessage.isNotEmpty) {
          _log(LogEntry(
              title: '✕ [$tag] Payment Error',
              body: 'Code: $errorCode\n$errorMessage',
              type: LogType.error));
        }
        break;
      default:
        _log(LogEntry(
            title: '[$tag] ← ${methodCall.method}',
            body: methodCall.arguments?.toString() ?? '',
            type: LogType.info));
    }
  }

  LogType _resolveLogType(bool error, String status) {
    if (status == 'charged') return LogType.success;
    if (error) return LogType.error;
    if (status == 'backpressed' || status == 'user_aborted')
      return LogType.info;
    return LogType.response;
  }

  Future<bool> _onWillPop() async {
    if (_isInitiated) {
      final r = await hyperSDK.onBackPress();
      return r.toLowerCase() != 'true';
    }
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF08111E),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            _buildStatusBar(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildIntegrationTab(),
                  PpSignatureScreen(
                    isInitiated: _isInitiated,
                    onLog: _log,
                    onProcess: (payload, callback) async {
                      hyperSDK.process(payload, callback);
                    },
                  ),
                  _buildEcSdkTab(),
                  LogPanel(logs: _logs, onClear: _clearLogs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0B1A2E),
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0066FF), Color(0xFF00C4FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payment_rounded,
                color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Juspay SDK Tester',
                  style: TextStyle(
                      color: Color(0xFFE8F4FF),
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Text('HyperCheckout Flutter',
                  style: TextStyle(
                      color: Color(0xFF3A6080),
                      fontSize: 10,
                      letterSpacing: 0.5)),
            ],
          ),
        ],
      ),
      actions: [
        if (_isInitiated)
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () async {
                await hyperSDK.terminate();
                setState(() => _isInitiated = false);
                _log(LogEntry(
                    title: 'SDK Terminated',
                    body: 'hyperSDK.terminate() called.',
                    type: LogType.info));
              },
              icon: const Icon(Icons.power_settings_new,
                  color: Color(0xFFFF6B6B), size: 15),
              label: const Text('Terminate',
                  style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 12)),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B6B).withOpacity(0.08),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1A2E),
        border: Border(bottom: BorderSide(color: Color(0xFF0F2540))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _pill(
                      Icons.memory_rounded,
                      'SDK',
                      _isInitiated ? 'READY' : 'IDLE',
                      _isInitiated
                          ? const Color(0xFF00E676)
                          : const Color(0xFF37474F)),
                  const SizedBox(width: 6),
                  _pill(
                      Icons.receipt_long_rounded,
                      'SESSION',
                      _extractedSdkPayload != null ? 'LOADED' : 'PENDING',
                      _extractedSdkPayload != null
                          ? const Color(0xFF00B0FF)
                          : const Color(0xFF37474F)),
                  const SizedBox(width: 6),
                  _pill(
                      Icons.key_rounded,
                      'TOKEN',
                      _ecClientAuthToken.isNotEmpty ? 'SET' : 'NONE',
                      _ecClientAuthToken.isNotEmpty
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFF37474F)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF0F2540),
                borderRadius: BorderRadius.circular(4)),
            child: Text('${_logs.length} logs',
                style: const TextStyle(
                    color: Color(0xFF2A4A6A),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 4),
          Text('$label: ',
              style: TextStyle(color: color.withOpacity(0.6), fontSize: 9)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF0B1A2E),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF0066FF),
        indicatorWeight: 2,
        labelColor: const Color(0xFF4DA3FF),
        unselectedLabelColor: const Color(0xFF2A4060),
        labelStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
        tabs: [
          const Tab(text: 'PP'),
          Tab(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('PP-SIG'),
                if (!_isInitiated)
                  const Text(
                    '🔒',
                    style: TextStyle(fontSize: 9, color: Color(0xFF37474F)),
                  ),
              ],
            ),
          ),
          Tab(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('EC SDK'),
                if (!_isInitiated)
                  const Text(
                    '🔒',
                    style: TextStyle(fontSize: 9, color: Color(0xFF37474F)),
                  ),
              ],
            ),
          ),
          const Tab(text: 'LOGS'),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Integration Tab
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildIntegrationTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildWebViewCard(),
        const SizedBox(height: 14),
        _StepShell(
          number: '01',
          title: 'Initiate SDK',
          subtitle: 'Boot up the Hyper engine',
          accent: const Color(0xFF4DA3FF),
          done: _isInitiated,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _rowLabel('Initiate Payload', _refreshInitiateId, 'New UUID',
                const Color(0xFF4DA3FF)),
            const SizedBox(height: 6),
            JsonInputField(controller: _initiateJsonCtrl, label: ''),
            const SizedBox(height: 12),
            _ActionButton(
                label: 'INITIATE SDK',
                icon: Icons.rocket_launch_rounded,
                color: const Color(0xFF4DA3FF),
                loading: _initiating,
                onPressed: _initiateSDK),
          ]),
        ),
        const SizedBox(height: 14),
        _StepShell(
          number: '02',
          title: 'Create Order',
          subtitle: 'POST /session → sdk_payload',
          accent: const Color(0xFFFFB74D),
          done: _extractedSdkPayload != null,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _field('Session URL', _sessionUrlCtrl,
                hint: 'https://sandbox.juspay.in/session'),
            const SizedBox(height: 8),
            _field('API Key', _apiKeyCtrl,
                hint: 'Your Juspay API key', obscure: true),
            const SizedBox(height: 10),
            _rowLabel('Request Payload', _refreshOrderId, 'New order_id',
                const Color(0xFFFFB74D)),
            const SizedBox(height: 6),
            JsonInputField(controller: _sessionJsonCtrl, label: ''),
            const SizedBox(height: 12),
            _ActionButton(
                label: 'CREATE SESSION',
                icon: Icons.cloud_upload_rounded,
                color: const Color(0xFFFFB74D),
                loading: _sessionLoading,
                onPressed: _createSession),
            if (_extractedSdkPayload != null) ...[
              const SizedBox(height: 10),
              _successBanner('sdk_payload extracted → auto-filled in Step 3',
                  _extractedSdkPayload!),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        _StepShell(
          number: '03',
          title: 'Process Payment',
          subtitle: 'hyperSDK.process() with sdk_payload',
          accent: const Color(0xFF69F0AE),
          done: false,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!_isInitiated)
              _warnBanner('SDK not initiated. Complete Step 1 first.'),
            if (_extractedSdkPayload == null)
              _warnBanner('No sdk_payload yet. Complete Step 2 first.'),
            const Text('Process Payload',
                style: TextStyle(
                    color: Color(0xFF6A8AAA),
                    fontSize: 11,
                    letterSpacing: 0.4)),
            const SizedBox(height: 6),
            JsonInputField(controller: _processJsonCtrl, label: ''),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'PROCESS PAYMENT',
              icon: Icons.send_rounded,
              color: const Color(0xFF69F0AE),
              loading: _processing,
              onPressed: (_isInitiated && _processJsonCtrl.text.isNotEmpty)
                  ? _processPayment
                  : null,
            ),
          ]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PP WebView Card
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildWebViewCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _webviewPaymentUrl != null
              ? const Color(0xFFCE93D8).withOpacity(0.5)
              : const Color(0xFF0F2540),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0B1A2E),
            const Color(0xFF130D2E),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFCE93D8).withOpacity(0.04),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              border: Border(
                  bottom: BorderSide(
                      color: const Color(0xFFCE93D8).withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCE93D8).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFCE93D8).withOpacity(0.4)),
                  ),
                  child: const Center(
                    child: Icon(Icons.web_rounded,
                        color: Color(0xFFCE93D8), size: 15),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PP — WebView',
                          style: TextStyle(
                              color: Color(0xFFD0E8FF),
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      Text('Session API → payment_links.web → WebView',
                          style: TextStyle(
                              color: Color(0xFF9E7AB0), fontSize: 10)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCE93D8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: const Color(0xFFCE93D8).withOpacity(0.3)),
                  ),
                  child: const Text('NO SDK REQUIRED',
                      style: TextStyle(
                          color: Color(0xFFCE93D8),
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCE93D8).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFFCE93D8).withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Color(0xFF9E7AB0), size: 13),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Uses Session URL + API Key + Payload from Step 02 below. Fill those first.',
                          style:
                              TextStyle(color: Color(0xFF9E7AB0), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Last URL preview
                if (_webviewPaymentUrl != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF00E676).withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF00E676), size: 13),
                          const SizedBox(width: 6),
                          Text('Order: ${_webviewOrderId ?? ""}',
                              style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                          if (_webviewExpiry != null) ...[
                            const Spacer(),
                            Text('Exp: ${_webviewExpiry!.split("T").first}',
                                style: const TextStyle(
                                    color: Color(0xFF4A6A8A), fontSize: 10)),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          _webviewPaymentUrl!,
                          style: const TextStyle(
                              color: Color(0xFF4A7A6A),
                              fontSize: 10,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'OPEN LAST URL',
                        icon: Icons.open_in_browser_rounded,
                        color: const Color(0xFFCE93D8),
                        loading: false,
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PaymentWebviewScreen(
                              url: _webviewPaymentUrl!,
                              orderId: _webviewOrderId ?? '',
                              onLog: _log,
                            ),
                          ));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        label: 'NEW SESSION',
                        icon: Icons.refresh_rounded,
                        color: const Color(0xFFCE93D8),
                        loading: _webviewSessionLoading,
                        onPressed: _launchWebViewPayment,
                      ),
                    ),
                  ]),
                ] else ...[
                  _ActionButton(
                    label: 'CREATE SESSION & OPEN',
                    icon: Icons.open_in_browser_rounded,
                    color: const Color(0xFFCE93D8),
                    loading: _webviewSessionLoading,
                    onPressed: _launchWebViewPayment,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EC SDK Tab
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEcSdkTab() {
    if (!_isInitiated) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF37474F).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF37474F).withOpacity(0.3)),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: Color(0xFF37474F), size: 28),
              ),
              const SizedBox(height: 16),
              const Text('EC SDK Locked',
                  style: TextStyle(
                      color: Color(0xFF8AA0B0),
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Complete Step 01 (Initiate SDK) in the\nIntegration tab to unlock EC SDK.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF3A5070), fontSize: 13),
              ),
              const SizedBox(height: 20),
              _ActionButton(
                label: 'GO TO INTEGRATION',
                icon: Icons.arrow_back_rounded,
                color: const Color(0xFF4DA3FF),
                loading: false,
                onPressed: () => _tabController.animateTo(0),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Create Order card
        _StepShell(
          number: '01',
          title: 'Create Order',
          subtitle: 'POST /orders → get client_auth_token',
          accent: const Color(0xFFFFB74D),
          done: _ecClientAuthToken.isNotEmpty,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // API Key info
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1828),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF0F2540)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFF3A5070), size: 13),
                const SizedBox(width: 6),
                const Expanded(
                    child: Text('API Key from Integration tab Step 02',
                        style:
                            TextStyle(color: Color(0xFF3A5070), fontSize: 11))),
                Text(
                  _apiKeyCtrl.text.isNotEmpty ? '●●●●●●' : 'Not set',
                  style: TextStyle(
                    color: _apiKeyCtrl.text.isNotEmpty
                        ? const Color(0xFF69F0AE)
                        : const Color(0xFFFF6B6B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
            // Mandatory fields
            _ecSectionLabel('MANDATORY'),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _field('order_id *', _ecOrderIdCtrl)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _ecRefreshOrderId,
                child: Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB74D).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFFFFB74D).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: Color(0xFFFFB74D), size: 15),
                ),
              ),
            ]),
            _field('amount *', _ecAmountCtrl),
            _field('customer_id *', _ecCustomerIdCtrl),
            // options.get_client_auth_token toggle
            Row(children: [
              const Text('options.get_client_auth_token *',
                  style: TextStyle(color: Color(0xFF6A8AAA), fontSize: 11)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(
                    () => _ecGetClientAuthToken = !_ecGetClientAuthToken),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _ecGetClientAuthToken
                        ? const Color(0xFF69F0AE).withOpacity(0.12)
                        : const Color(0xFFFF6B6B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _ecGetClientAuthToken
                          ? const Color(0xFF69F0AE)
                          : const Color(0xFFFF6B6B),
                    ),
                  ),
                  child: Text(
                    _ecGetClientAuthToken ? 'true' : 'false',
                    style: TextStyle(
                      color: _ecGetClientAuthToken
                          ? const Color(0xFF69F0AE)
                          : const Color(0xFFFF6B6B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Optional fields
            _ecSectionLabel('OPTIONAL'),
            const SizedBox(height: 6),
            _ecOptField(
                'customer_email', 'customer_email', _ecCustomerEmailCtrl),
            _ecOptField(
                'customer_phone', 'customer_phone', _ecCustomerMobileCtrl),
            _ecOptField('currency', 'currency', _ecCurrencyCtrl),
            _ecOptField('description', 'description', _ecDescriptionCtrl),
            _ecOptField('return_url', 'return_url', _ecReturnUrlCtrl),
            _ecOptField('product_id', 'product_id', _ecProductIdCtrl),
            _ecOptField('gateway_id', 'gateway_id (number)', _ecGatewayIdCtrl),
            _ecOptField('order_type', 'order_type', _ecOrderTypeCtrl),
            _ecOptField('metadata_gateway_ref',
                'metadata.JUSPAY:gateway_reference_id', _ecGatewayRefIdCtrl),
            _ecOptField('metadata_subvention', 'metadata.subvention_amount',
                _ecSubventionAmtCtrl),
            _ecOptField(
                'metadata_webhook', 'metadata.webhook_url', _ecWebhookUrlCtrl),

            // ── Collapsible: Billing Address ───────────────────────────────
            _ecCollapsibleHeader('BILLING ADDRESS', _ecBillingExpanded,
                () => setState(() => _ecBillingExpanded = !_ecBillingExpanded)),
            if (_ecBillingExpanded) ...[
              const SizedBox(height: 6),
              _ecOptField('billing_address_first_name',
                  'billing_address_first_name', _ecBillingFnCtrl),
              _ecOptField('billing_address_last_name',
                  'billing_address_last_name', _ecBillingLnCtrl),
              _ecOptField('billing_address_line1', 'billing_address_line1',
                  _ecBillingLine1Ctrl),
              _ecOptField('billing_address_city', 'billing_address_city',
                  _ecBillingCityCtrl),
              _ecOptField('billing_address_state', 'billing_address_state',
                  _ecBillingStateCtrl),
              _ecOptField('billing_address_country', 'billing_address_country',
                  _ecBillingCountryCtrl),
              _ecOptField('billing_address_postal_code',
                  'billing_address_postal_code', _ecBillingPostalCtrl),
              _ecOptField('billing_address_phone', 'billing_address_phone',
                  _ecBillingPhoneCtrl),
              _ecOptField('shipping_address_first_name',
                  'shipping_address_first_name', _ecShipFnCtrl),
            ],

            // ── Collapsible: Bank Account Details ──────────────────────────
            _ecCollapsibleHeader(
                'BANK ACCOUNT DETAILS (TPV)',
                _ecBankAccountEnabled,
                () => setState(
                    () => _ecBankAccountEnabled = !_ecBankAccountEnabled)),
            if (_ecBankAccountEnabled) ...[
              const SizedBox(height: 6),
              _ecSubLabel(
                  'bank_account_number OR bank_account_id is mandatory'),
              _ecPlainField('bank_account_number *', _ecBankAccNumCtrl),
              _ecPlainField('bank_ifsc', _ecBankIfscCtrl),
              _ecPlainField('juspay_bank_code (e.g. JP_HDFC)', _ecBankCodeCtrl),
              _ecPlainField('bank_beneficiary_name', _ecBankBenCtrl),
              _ecPlainField('bank_account_id', _ecBankAccIdCtrl),
              _ecDropdownField('bank_account_type', _ecBankAccTypeCtrl,
                  ['SAVINGS', 'CURRENT']),
            ],

            // ── Collapsible: Mutual Fund ───────────────────────────────────
            _ecCollapsibleHeader(
                'MUTUAL FUND DETAILS',
                _ecMutualFundEnabled,
                () => setState(
                    () => _ecMutualFundEnabled = !_ecMutualFundEnabled)),
            if (_ecMutualFundEnabled) ...[
              const SizedBox(height: 6),
              _ecPlainField('memberId *', _ecMfMemberIdCtrl),
              _ecPlainField('userId *', _ecMfUserIdCtrl),
              _ecDropdownField('mfPartner *', _ecMfPartnerCtrl,
                  ['NSE', 'BSE', 'KFIN', 'CAMS']),
              _ecPlainField('orderNumber *', _ecMfOrderNumCtrl),
              _ecPlainField('amount *', _ecMfAmountCtrl),
              _ecDropdownField(
                  'investmentType *', _ecMfInvTypeCtrl, ['LUMPSUM', 'SIP']),
              _ecPlainField('folioNumber', _ecMfFolioCtrl),
              _ecPlainField('panNumber (UPPERCASE)', _ecMfPanCtrl),
              _ecPlainField('amcCode', _ecMfAmcCodeCtrl),
              _ecPlainField('schemeCode', _ecMfSchemeCodeCtrl),
              _ecPlainField('ihNumber', _ecMfIhNumberCtrl),
            ],

            // ── Collapsible: UDF 1–10 ──────────────────────────────────────
            _ecCollapsibleHeader('UDF FIELDS (1–10)', _ecUdfExpanded,
                () => setState(() => _ecUdfExpanded = !_ecUdfExpanded)),
            if (_ecUdfExpanded) ...[
              const SizedBox(height: 6),
              _ecOptField('udf1', 'udf1', _ecUdf1Ctrl),
              _ecOptField('udf2', 'udf2', _ecUdf2Ctrl),
              _ecOptField('udf3', 'udf3', _ecUdf3Ctrl),
              _ecOptField('udf4', 'udf4', _ecUdf4Ctrl),
              _ecOptField('udf5', 'udf5', _ecUdf5Ctrl),
              _ecOptField('udf6', 'udf6', _ecUdf6Ctrl),
              _ecOptField('udf7', 'udf7', _ecUdf7Ctrl),
              _ecOptField('udf8', 'udf8', _ecUdf8Ctrl),
              _ecOptField('udf9', 'udf9', _ecUdf9Ctrl),
              _ecOptField('udf10', 'udf10', _ecUdf10Ctrl),
            ],
            // Extra custom fields
            if (_ecExtraFields.isNotEmpty) ...[
              _ecSectionLabel('CUSTOM FIELDS'),
              const SizedBox(height: 6),
              ..._ecExtraFields.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: f['key'],
                          style: const TextStyle(
                              color: Color(0xFFCCE4FF), fontSize: 12),
                          decoration: _ecInputDecoration('key'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: f['value'],
                          style: const TextStyle(
                              color: Color(0xFFCCE4FF), fontSize: 12),
                          decoration: _ecInputDecoration('value'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() {
                          f['key']!.dispose();
                          f['value']!.dispose();
                          _ecExtraFields.remove(f);
                        }),
                        child: const Icon(Icons.remove_circle_outline_rounded,
                            color: Color(0xFFFF6B6B), size: 18),
                      ),
                    ]),
                  )),
            ],
            const SizedBox(height: 8),
            // Add Field CTA
            GestureDetector(
              onTap: () => setState(() => _ecExtraFields.add({
                    'key': TextEditingController(),
                    'value': TextEditingController(),
                  })),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1828),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF1E3A5F), style: BorderStyle.solid),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_rounded,
                      color: Color(0xFF4DA3FF), size: 15),
                  const SizedBox(width: 6),
                  const Text('ADD FIELD',
                      style: TextStyle(
                          color: Color(0xFF4DA3FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ]),
              ),
            ),
            if (_ecClientAuthToken.isNotEmpty) ...[
              const SizedBox(height: 10),
              _tokenBanner(),
            ],
            const SizedBox(height: 12),
            _ActionButton(
              label: 'CREATE ORDER',
              icon: Icons.add_shopping_cart_rounded,
              color: const Color(0xFFFFB74D),
              loading: _ecFetchingToken,
              onPressed: _createEcOrder,
            ),
          ]),
        ),

        const SizedBox(height: 14),

        // Process card
        _StepShell(
          number: '02',
          title: 'EC Process',
          subtitle: 'hyperSDK.process() with EC payload',
          accent: const Color(0xFF69F0AE),
          done: false,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_ecClientAuthToken.isEmpty)
              _warnBanner(
                  'clientAuthToken not fetched. Complete Step 1 first.'),

            // Template selector
            const Text('Select Payload Template',
                style: TextStyle(
                    color: Color(0xFF6A8AAA),
                    fontSize: 11,
                    letterSpacing: 0.4)),
            const SizedBox(height: 8),
            _templateSelector(),
            const SizedBox(height: 12),

            // Payload editor
            _rowLabel('Process Payload', _refreshEcRequestId, 'New UUID',
                const Color(0xFF69F0AE)),
            const SizedBox(height: 6),
            JsonInputField(controller: _ecPayloadCtrl, label: ''),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'PROCESS EC SDK',
              icon: Icons.send_rounded,
              color: const Color(0xFF69F0AE),
              loading: _ecProcessing,
              onPressed: _isInitiated ? _ecProcess : null,
            ),
          ]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── EC SDK UI helpers ─────────────────────────────────────────────────────

  Widget _ecCollapsibleHeader(String label, bool expanded, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: expanded
              ? const Color(0xFFFFB74D).withOpacity(0.07)
              : const Color(0xFF0A1828),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: expanded
                ? const Color(0xFFFFB74D).withOpacity(0.4)
                : const Color(0xFF1A3050),
          ),
        ),
        child: Row(children: [
          Container(
              width: 3,
              height: 11,
              decoration: BoxDecoration(
                  color: expanded
                      ? const Color(0xFFFFB74D)
                      : const Color(0xFF3A5070),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 7),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: expanded
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFF4A6A8A),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0))),
          Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color:
                  expanded ? const Color(0xFFFFB74D) : const Color(0xFF3A5070),
              size: 16),
        ]),
      ),
    );
  }

  Widget _ecSubLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(color: Color(0xFF3A5070), fontSize: 10)),
    );
  }

  Widget _ecPlainField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF6A8AAA), fontSize: 10)),
        const SizedBox(height: 3),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Color(0xFFCCE4FF), fontSize: 12),
          decoration: _ecInputDecoration(null),
        ),
      ]),
    );
  }

  Widget _ecDropdownField(
      String label, TextEditingController ctrl, List<String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF6A8AAA), fontSize: 10)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1828),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFF0F2540)),
          ),
          child: DropdownButton<String>(
            value: options.contains(ctrl.text) ? ctrl.text : options.first,
            isExpanded: true,
            dropdownColor: const Color(0xFF0B1A2E),
            underline: const SizedBox(),
            style: const TextStyle(color: Color(0xFFCCE4FF), fontSize: 12),
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF4A6A8A), size: 18),
            items: options
                .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(o,
                          style: const TextStyle(
                              color: Color(0xFFCCE4FF), fontSize: 12)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => ctrl.text = v ?? ctrl.text),
          ),
        ),
      ]),
    );
  }

  Widget _ecSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(children: [
        Container(
            width: 3,
            height: 11,
            decoration: BoxDecoration(
                color: const Color(0xFFFFB74D),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF4A6A8A),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2)),
      ]),
    );
  }

  Widget _ecOptField(
      String toggleKey, String label, TextEditingController ctrl) {
    final enabled = _ecOrderOptEnabled[toggleKey] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => _ecOrderOptEnabled[toggleKey] = !enabled),
          child: Container(
            width: 34,
            height: 19,
            decoration: BoxDecoration(
              color: enabled
                  ? const Color(0xFFFFB74D).withOpacity(0.18)
                  : const Color(0xFF0F2540),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: enabled
                      ? const Color(0xFFFFB74D)
                      : const Color(0xFF1A3050)),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 140),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 13,
                height: 13,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFFFFB74D)
                      : const Color(0xFF2A4060),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.35,
            duration: const Duration(milliseconds: 140),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style:
                      const TextStyle(color: Color(0xFF6A8AAA), fontSize: 10)),
              const SizedBox(height: 2),
              TextField(
                controller: ctrl,
                enabled: enabled,
                style: const TextStyle(color: Color(0xFFCCE4FF), fontSize: 12),
                decoration: _ecInputDecoration(null),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  InputDecoration _ecInputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF1E3A5F), fontSize: 11),
      filled: true,
      fillColor: const Color(0xFF0A1828),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: Color(0xFF0F2540))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: Color(0xFF0F2540))),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: Color(0xFF0A1828))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: const BorderSide(color: Color(0xFFFFB74D), width: 1.5)),
    );
  }

  Widget _tokenBanner() {
    final short = _ecClientAuthToken.length > 20
        ? '${_ecClientAuthToken.substring(0, 20)}...'
        : _ecClientAuthToken;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB74D).withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFFFFB74D), size: 14),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(short,
                style: const TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 11,
                    fontFamily: 'monospace')),
            if (_ecClientAuthTokenExpiry.isNotEmpty)
              Text('Expires: $_ecClientAuthTokenExpiry',
                  style:
                      const TextStyle(color: Color(0xFF6A8AAA), fontSize: 10)),
          ]),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _ecClientAuthToken));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Token copied'), duration: Duration(seconds: 1)));
          },
          child: const Icon(Icons.copy_rounded,
              color: Color(0xFFFFB74D), size: 14),
        ),
      ]),
    );
  }

  Widget _templateSelector() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _ecPayloadTemplates.keys.map((name) {
        final selected = _selectedEcTemplate == name;
        return GestureDetector(
          onTap: () => _applyEcTemplate(name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF69F0AE).withOpacity(0.12)
                  : const Color(0xFF0A1828),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? const Color(0xFF69F0AE).withOpacity(0.5)
                    : const Color(0xFF0F2540),
              ),
            ),
            child: Text(
              name,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF69F0AE)
                    : const Color(0xFF4A6A8A),
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Shared UI helpers ────────────────────────────────────────────────────
  Widget _rowLabel(
      String label, VoidCallback onRefresh, String btnLabel, Color color) {
    return Row(children: [
      Text(label,
          style: const TextStyle(
              color: Color(0xFF6A8AAA), fontSize: 11, letterSpacing: 0.4)),
      const Spacer(),
      GestureDetector(
        onTap: onRefresh,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh_rounded, color: color, size: 11),
            const SizedBox(width: 4),
            Text(btnLabel,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }

  Widget _successBanner(String msg, String payload) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF00E676).withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded,
            color: Color(0xFF00E676), size: 15),
        const SizedBox(width: 8),
        Expanded(
            child: Text(msg,
                style:
                    const TextStyle(color: Color(0xFF00E676), fontSize: 11))),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: payload));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copied'), duration: Duration(seconds: 1)));
          },
          child: const Icon(Icons.copy_rounded,
              color: Color(0xFF00E676), size: 14),
        ),
      ]),
    );
  }

  Widget _warnBanner(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB74D).withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFFFB74D), size: 14),
        const SizedBox(width: 8),
        Expanded(
            child: Text(msg,
                style:
                    const TextStyle(color: Color(0xFFFFB74D), fontSize: 11))),
      ]),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF6A8AAA), fontSize: 11, letterSpacing: 0.4)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(color: Color(0xFFCCE4FF), fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF1E3A5F)),
            filled: true,
            fillColor: const Color(0xFF0A1828),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF0F2540))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF0F2540))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF0066FF), width: 1.5)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step Shell
// ─────────────────────────────────────────────────────────────────────────────
class _StepShell extends StatelessWidget {
  final String number, title, subtitle;
  final Color accent;
  final bool done;
  final Widget child;

  const _StepShell({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.done,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: done ? accent.withOpacity(0.4) : const Color(0xFF0F2540)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.04),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            border: Border(bottom: BorderSide(color: accent.withOpacity(0.1))),
          ),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withOpacity(0.4)),
              ),
              child: Center(
                child: Text(number,
                    style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: Color(0xFFD0E8FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: TextStyle(
                          color: accent.withOpacity(0.5), fontSize: 10)),
                ])),
            if (done)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_rounded, color: accent, size: 11),
                  const SizedBox(width: 3),
                  Text('DONE',
                      style: TextStyle(
                          color: accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Button
// ─────────────────────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              enabled ? color.withOpacity(0.12) : const Color(0xFF0F2540),
          disabledBackgroundColor: const Color(0xFF0F2540),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color:
                    enabled ? color.withOpacity(0.4) : const Color(0xFF1A3050)),
          ),
          elevation: 0,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (loading)
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
          else
            Icon(icon,
                size: 15, color: enabled ? color : const Color(0xFF2A4060)),
          const SizedBox(width: 8),
          Text(
            loading ? 'PROCESSING...' : label,
            style: TextStyle(
              color: enabled ? color : const Color(0xFF2A4060),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ]),
      ),
    );
  }
}
