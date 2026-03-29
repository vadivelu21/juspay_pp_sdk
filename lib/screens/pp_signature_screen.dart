import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' as pc;
import '../models/log_entry.dart';
import '../widgets/json_input_field.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RSA-SHA256 signing — uses pointycastle only, no asn1lib
// Supports PKCS#1 (-----BEGIN RSA PRIVATE KEY-----) and
//          PKCS#8 (-----BEGIN PRIVATE KEY-----)
// ─────────────────────────────────────────────────────────────────────────────

// ── DER/ASN.1 helpers ────────────────────────────────────────────────────────

class _DerReader {
  final Uint8List _buf;
  int _pos = 0;
  _DerReader(this._buf);

  int _readTag() => _buf[_pos++];

  int _readLen() {
    int first = _buf[_pos++];
    if (first & 0x80 == 0) return first;
    int numBytes = first & 0x7f;
    int len = 0;
    for (int i = 0; i < numBytes; i++) len = (len << 8) | _buf[_pos++];
    return len;
  }

  // Read a TLV and return the value bytes, advancing pos past the whole TLV
  Uint8List _readValue(int expectedTag) {
    int tag = _readTag();
    if (tag != expectedTag) {
      throw Exception(
          'Expected tag 0x${expectedTag.toRadixString(16)} got 0x${tag.toRadixString(16)} at pos ${_pos - 1}');
    }
    int len = _readLen();
    final value = _buf.sublist(_pos, _pos + len);
    _pos += len;
    return value;
  }

  // Skip a TLV entirely
  void _skip() {
    _readTag();
    int len = _readLen();
    _pos += len;
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (final b in bytes) result = (result << 8) | BigInt.from(b);
    return result;
  }

  BigInt readInteger() {
    final raw = _readValue(0x02); // INTEGER
    // Strip leading 0x00 sign padding
    int start = (raw.isNotEmpty && raw[0] == 0x00) ? 1 : 0;
    return _bytesToBigInt(raw.sublist(start));
  }

  void enterSequence() {
    int tag = _readTag();
    if (tag != 0x30)
      throw Exception(
          'Expected SEQUENCE (0x30) got 0x${tag.toRadixString(16)}');
    _readLen(); // consume length, we don't need it
  }

  Uint8List readOctetString() => _readValue(0x04);

  void skipSequence() => _skip();
  void skipOid() {
    _readTag();
    int l = _readLen();
    _pos += l;
  }

  void skipNull() {
    _readTag();
    _readTag();
  } // tag + 0x00 length
}

pc.RSAPrivateKey _parsePem(String pem) {
  final cleaned = pem
      .replaceAll(RegExp(r'-----[^-]+-----'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
  Uint8List der = base64Decode(cleaned);

  final isPkcs8 = pem.contains('BEGIN PRIVATE KEY');

  if (isPkcs8) {
    // PKCS#8 wrapper: SEQUENCE { INTEGER(version), SEQUENCE(algId), OCTET STRING(pkcs1) }
    final r = _DerReader(der);
    r.enterSequence();
    r.readInteger(); // version
    r.skipSequence(); // AlgorithmIdentifier
    der = r.readOctetString(); // embedded PKCS#1 DER
  }

  // PKCS#1: SEQUENCE { version, n, e, d, p, q, dp, dq, qInv }
  final r = _DerReader(der);
  r.enterSequence();
  r.readInteger(); // version (0)
  final n = r.readInteger();
  r.readInteger(); // e (public exponent)
  final d = r.readInteger();
  final p = r.readInteger();
  final q = r.readInteger();
  return pc.RSAPrivateKey(n, d, p, q);
}

String _rsaSign(String payload, String pemKey) {
  final privateKey = _parsePem(pemKey.trim());
  final messageBytes = Uint8List.fromList(utf8.encode(payload));
  final signer = pc.RSASigner(pc.SHA256Digest(), '0609608648016503040201');
  signer.init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(privateKey));
  final sig = signer.generateSignature(messageBytes) as pc.RSASignature;
  return base64Encode(sig.bytes);
}

// ─────────────────────────────────────────────────────────────────────────────

class PpSignatureScreen extends StatefulWidget {
  final bool isInitiated;
  final void Function(LogEntry) onLog;
  final Future<void> Function(Map<String, dynamic>, void Function(MethodCall))
      onProcess;

  const PpSignatureScreen({
    super.key,
    required this.isInitiated,
    required this.onLog,
    required this.onProcess,
  });

  @override
  State<PpSignatureScreen> createState() => _PpSignatureScreenState();
}

class _PpSignatureScreenState extends State<PpSignatureScreen> {
  // ── Required fields ───────────────────────────────────────────────────────
  final _clientIdCtrl = TextEditingController(text: 'msprod');
  final _merchantIdCtrl = TextEditingController(text: 'Testvadivel');
  final _orderIdCtrl =
      TextEditingController(text: 't${DateTime.now().millisecondsSinceEpoch}');
  final _amountCtrl = TextEditingController(text: '10.00');
  final _customerIdCtrl = TextEditingController(text: 'customer_001');
  final _customerEmailCtrl = TextEditingController(text: 'test@example.com');
  final _customerPhoneCtrl = TextEditingController(text: '9999999999');
  final _returnUrlCtrl =
      TextEditingController(text: 'https://your-app.com/payment/callback');
  final _environmentCtrl = TextEditingController(text: 'sandbox');

  // ── Optional fields (toggled) ─────────────────────────────────────────────
  final _descriptionCtrl = TextEditingController(text: 'Test Order');
  final _currencyCtrl = TextEditingController(text: 'INR');
  final _firstNameCtrl = TextEditingController(text: 'Test');
  final _lastNameCtrl = TextEditingController(text: 'User');
  final _udf1Ctrl = TextEditingController(text: '');
  final _udf2Ctrl = TextEditingController(text: '');

  // ── Optional toggleable fields ─────────────────────────────────────────────
  final _languageCtrl = TextEditingController(text: 'english');
  final _displayNoteCtrl = TextEditingController(text: '');
  final _payeeNameCtrl = TextEditingController(text: '');
  final _orderTypeCtrl = TextEditingController(text: 'TPV_PAYMENT');
  final _createMandateCtrl = TextEditingController(text: 'REQUIRED');
  final _mandateMaxAmountCtrl = TextEditingController(text: '');
  bool _paymentAttemptEnabled = false;
  bool _resumePaymentApprove = true; // true = approve, false = abort
  String? _pendingTxnReference; // filled when paymentAttempt event arrives
  // Mandate extras
  final _mandateStartDateCtrl = TextEditingController(text: '');
  final _mandateEndDateCtrl = TextEditingController(text: '');
  final _mandateFrequencyCtrl = TextEditingController(text: 'ASPRESENTED');
  bool _mandateRevokable = false;
  bool _mandateBlockFunds = false;
  // Metadata
  final _gatewayRefIdCtrl = TextEditingController(text: '');
  // Bank account details
  final _bankAccNumberCtrl = TextEditingController(text: '');
  final _bankIfscCtrl = TextEditingController(text: '');
  final _bankCodeCtrl = TextEditingController(text: '');
  final _bankBeneficiaryCtrl = TextEditingController(text: '');
  final _bankAccIdCtrl = TextEditingController(text: '');
  final _bankAccTypeCtrl = TextEditingController(text: 'SAVINGS');
  bool _bankAccountEnabled = false;
  // Mutual fund
  final _mfMemberIdCtrl = TextEditingController(text: '');
  final _mfUserIdCtrl = TextEditingController(text: '');
  final _mfPartnerCtrl = TextEditingController(text: '');
  final _mfOrderNumberCtrl = TextEditingController(text: '');
  final _mfAmountCtrl = TextEditingController(text: '');
  final _mfInvestmentTypeCtrl = TextEditingController(text: 'LUMPSUM');
  final _mfSchemeCodeCtrl = TextEditingController(text: '');
  final _mfFolioCtrl = TextEditingController(text: '');
  final _mfPanCtrl = TextEditingController(text: '');
  final _mfAmcCodeCtrl = TextEditingController(text: '');
  final _mfIhNumberCtrl = TextEditingController(text: '');
  bool _mutualFundEnabled = false;
  // Show expiry
  bool _showExpiryEnabled = false;
  final _expiryActiveTimeCtrl = TextEditingController(text: '300000');
  // Basket
  bool _basketEnabled = false;
  final _basketProductNameCtrl = TextEditingController(text: '');
  final _basketProductIdCtrl = TextEditingController(text: '');
  final _basketQuantityCtrl = TextEditingController(text: '1');
  final _basketUnitPriceCtrl = TextEditingController(text: '');
  // amount_info
  bool _amountInfoEnabled = false;
  final _amountInfoBaseCtrl = TextEditingController(text: '');
  final _amountInfoAddonsCtrl = TextEditingController(text: '');
  // UDFs 3-10
  final _udf3Ctrl = TextEditingController(text: '');
  final _udf4Ctrl = TextEditingController(text: '');
  final _udf5Ctrl = TextEditingController(text: '');
  final _udf6Ctrl = TextEditingController(text: '');
  final _udf7Ctrl = TextEditingController(text: '');
  final _udf8Ctrl = TextEditingController(text: '');
  final _udf9Ctrl = TextEditingController(text: '');
  final _udf10Ctrl = TextEditingController(text: '');

  final Map<String, bool> _optionalEnabled = {
    'description': true,
    'currency': true,
    'firstName': false,
    'lastName': false,
    'language': false,
    'displayNote': false,
    'payeeName': false,
    'order_type': false,
    'options.create_mandate': false,
    'mandate.max_amount': false,
    'mandate.start_date': false,
    'mandate.end_date': false,
    'mandate.frequency': false,
    'metadata.gateway_ref_id': false,
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

  // ── Signature ─────────────────────────────────────────────────────────────
  final _merchantKeyIdCtrl = TextEditingController(text: '');
  final _privateKeyCtrl = TextEditingController(
      text: '-----BEGIN RSA PRIVATE KEY-----\n'
          'PASTE YOUR PRIVATE KEY HERE\n'
          '-----END RSA PRIVATE KEY-----');

  // ── Output ────────────────────────────────────────────────────────────────
  String? _generatedSignature;
  Map<String, dynamic>? _constructedOrderDetails;
  Map<String, dynamic>? _constructedProcessPayload;
  final _processPayloadCtrl = TextEditingController();

  bool _signing = false;
  bool _processing = false;

  // ── Process payment directly ─────────────────────────────────────────────
  Future<void> _processPayment() async {
    if (_constructedProcessPayload == null) return;
    setState(() => _processing = true);
    widget.onLog(LogEntry(
      title: '[PP-SIG] ▲ Process — Payload',
      body: const JsonEncoder.withIndent('  ')
          .convert(_constructedProcessPayload),
      type: LogType.request,
    ));
    try {
      widget.onProcess(_constructedProcessPayload!, _processCallback);
      widget.onLog(LogEntry(
        title: '[PP-SIG] Process — Called',
        body: 'hyperSDK.process() invoked. Awaiting callback...',
        type: LogType.info,
      ));
    } catch (e) {
      widget.onLog(LogEntry(
        title: '[PP-SIG] Process — Exception',
        body: e.toString(),
        type: LogType.error,
      ));
    } finally {
      setState(() => _processing = false);
    }
  }

  // ── Decode raw MethodCall arguments into a Map ──────────────────────────
  Map<String, dynamic> _decodeArgs(dynamic raw) {
    if (raw == null) return {};
    try {
      if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return {};
  }

  // ── Handle paymentAttempt — works regardless of which method it arrives on ─
  bool _handlePaymentAttempt(Map<String, dynamic> args) {
    final event = args['event'] ?? args['method'] ?? '';
    if (event != 'paymentAttempt') return false;

    // txnReference is inside args['payload']
    final payloadMap = (args['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final txnRef =
        (payloadMap['txnReference'] ?? args['txnReference'] ?? '').toString();

    widget.onLog(LogEntry(
      title: '[PP-SIG] ● paymentAttempt Received',
      body: const JsonEncoder.withIndent('  ').convert(args),
      type: LogType.info,
    ));

    if (txnRef.isEmpty) {
      widget.onLog(LogEntry(
        title: '[PP-SIG] ✕ paymentAttempt — txnReference missing',
        body: 'Could not extract txnReference from event payload.',
        type: LogType.error,
      ));
      return true;
    }

    Future.microtask(() {
      if (!mounted) return;
      setState(() => _pendingTxnReference = txnRef);
      widget.onLog(LogEntry(
        title:
            '[PP-SIG] → resumePayment: ${_resumePaymentApprove ? "APPROVE (true)" : "ABORT (false)"}',
        body: 'txnReference: $txnRef',
        type: _resumePaymentApprove ? LogType.info : LogType.error,
      ));
      Future.microtask(() => _sendResumePayment(txnRef));
    });
    return true;
  }

  void _processCallback(MethodCall methodCall) {
    // Log every raw callback for debugging
    widget.onLog(LogEntry(
      title: '[PP-SIG] ← SDK callback: ${methodCall.method}',
      body: methodCall.arguments?.toString() ?? '',
      type: LogType.info,
    ));

    final args = _decodeArgs(methodCall.arguments);

    // Check for paymentAttempt on ANY method — SDK may use different method names
    if (_handlePaymentAttempt(args)) return;

    switch (methodCall.method) {
      case 'hide_loader':
        break; // already logged above

      case 'process_result':
        final error = args['error'] ?? false;
        final inner = (args['payload'] as Map?)?.cast<String, dynamic>() ?? {};
        final status = inner['status'] ?? '';
        final errorCode = args['errorCode'] ?? '';

        widget.onLog(LogEntry(
          title:
              '[PP-SIG] ▼ Process Result — "$status"${errorCode.isNotEmpty ? " | $errorCode" : ""}',
          body: const JsonEncoder.withIndent('  ').convert(args),
          type: status == 'charged'
              ? LogType.success
              : (error ? LogType.error : LogType.response),
        ));
        if (status == 'charged') {
          widget.onLog(LogEntry(
              title: '[PP-SIG] ✓ Payment Successful!',
              body: 'Verify via S2S order status API.',
              type: LogType.success));
        }
        break;

      default:
        break; // already logged above
    }
  }

  // ── Send resumePayment process call ──────────────────────────────────────
  void _sendResumePayment(String txnReference) {
    if (_constructedProcessPayload == null) return;

    final resumePayload = {
      'requestId': _generateUuidV4(),
      'service': 'in.juspay.hyperpay',
      'payload': {
        'action': 'resumePayment',
        'txnReference': txnReference,
        'status': _resumePaymentApprove,
        'orderDetails': (_constructedProcessPayload!['payload']
            as Map<String, dynamic>)['orderDetails'],
        'signature': (_constructedProcessPayload!['payload']
            as Map<String, dynamic>)['signature'],
      },
    };

    widget.onLog(LogEntry(
      title: '[PP-SIG] ▲ resumePayment — Process Call',
      body: const JsonEncoder.withIndent('  ').convert(resumePayload),
      type: LogType.request,
    ));

    try {
      widget.onProcess(resumePayload, _processCallback);
      widget.onLog(LogEntry(
        title: '[PP-SIG] resumePayment — Called',
        body: 'Awaiting result...',
        type: LogType.info,
      ));
    } catch (e) {
      widget.onLog(LogEntry(
        title: '[PP-SIG] resumePayment — Exception',
        body: e.toString(),
        type: LogType.error,
      ));
    }
  }

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    _merchantIdCtrl.dispose();
    _orderIdCtrl.dispose();
    _amountCtrl.dispose();
    _customerIdCtrl.dispose();
    _customerEmailCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _returnUrlCtrl.dispose();
    _environmentCtrl.dispose();
    _descriptionCtrl.dispose();
    _currencyCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _udf1Ctrl.dispose();
    _udf2Ctrl.dispose();
    _merchantKeyIdCtrl.dispose();
    _privateKeyCtrl.dispose();
    _languageCtrl.dispose();
    _displayNoteCtrl.dispose();
    _payeeNameCtrl.dispose();
    _orderTypeCtrl.dispose();
    _createMandateCtrl.dispose();
    _mandateMaxAmountCtrl.dispose();
    _mandateStartDateCtrl.dispose();
    _mandateEndDateCtrl.dispose();
    _mandateFrequencyCtrl.dispose();
    _gatewayRefIdCtrl.dispose();
    _bankAccNumberCtrl.dispose();
    _bankIfscCtrl.dispose();
    _bankCodeCtrl.dispose();
    _bankBeneficiaryCtrl.dispose();
    _bankAccIdCtrl.dispose();
    _bankAccTypeCtrl.dispose();
    _mfMemberIdCtrl.dispose();
    _mfUserIdCtrl.dispose();
    _mfPartnerCtrl.dispose();
    _mfOrderNumberCtrl.dispose();
    _mfAmountCtrl.dispose();
    _mfInvestmentTypeCtrl.dispose();
    _mfSchemeCodeCtrl.dispose();
    _mfFolioCtrl.dispose();
    _mfPanCtrl.dispose();
    _mfAmcCodeCtrl.dispose();
    _mfIhNumberCtrl.dispose();
    _expiryActiveTimeCtrl.dispose();
    _basketProductNameCtrl.dispose();
    _basketProductIdCtrl.dispose();
    _basketQuantityCtrl.dispose();
    _basketUnitPriceCtrl.dispose();
    _amountInfoBaseCtrl.dispose();
    _amountInfoAddonsCtrl.dispose();
    _udf3Ctrl.dispose();
    _udf4Ctrl.dispose();
    _udf5Ctrl.dispose();
    _udf6Ctrl.dispose();
    _udf7Ctrl.dispose();
    _udf8Ctrl.dispose();
    _udf9Ctrl.dispose();
    _udf10Ctrl.dispose();
    _processPayloadCtrl.dispose();
    super.dispose();
  }

  // ── Build orderDetails map — mandatory + all toggled optional fields ───────
  // This is what gets stringified and signed (RSA-SHA256).
  Map<String, dynamic> _buildOrderDetails() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // ── Mandatory fields ────────────────────────────────────────────────────
    final map = <String, dynamic>{
      'clientId': _clientIdCtrl.text.trim(),
      'merchant_id': _merchantIdCtrl.text.trim(),
      'order_id': _orderIdCtrl.text.trim(),
      'amount': _amountCtrl.text.trim(),
      'customer_id': _customerIdCtrl.text.trim(),
      'customer_email': _customerEmailCtrl.text.trim(),
      'customer_phone': _customerPhoneCtrl.text.trim(),
      'return_url': _returnUrlCtrl.text.trim(),
      'environment': _environmentCtrl.text.trim(),
      'timestamp': timestamp,
    };

    bool opt(String k) => _optionalEnabled[k] == true;
    bool notEmpty(String v) => v.isNotEmpty;

    // ── Optional toggleable fields ──────────────────────────────────────────
    if (opt('description') && notEmpty(_descriptionCtrl.text))
      map['description'] = _descriptionCtrl.text.trim();
    if (opt('currency') && notEmpty(_currencyCtrl.text))
      map['currency'] = _currencyCtrl.text.trim();
    if (opt('firstName') && notEmpty(_firstNameCtrl.text))
      map['firstName'] = _firstNameCtrl.text.trim();
    if (opt('lastName') && notEmpty(_lastNameCtrl.text))
      map['lastName'] = _lastNameCtrl.text.trim();
    if (opt('language') && notEmpty(_languageCtrl.text))
      map['language'] = _languageCtrl.text.trim();
    if (opt('displayNote') && notEmpty(_displayNoteCtrl.text))
      map['displayNote'] = _displayNoteCtrl.text.trim();
    if (opt('payeeName') && notEmpty(_payeeNameCtrl.text))
      map['payeeName'] = _payeeNameCtrl.text.trim();
    if (opt('order_type') && notEmpty(_orderTypeCtrl.text))
      map['order_type'] = _orderTypeCtrl.text.trim();
    if (opt('options.create_mandate') && notEmpty(_createMandateCtrl.text))
      map['options.create_mandate'] = _createMandateCtrl.text.trim();
    if (opt('mandate.max_amount') && notEmpty(_mandateMaxAmountCtrl.text))
      map['mandate.max_amount'] = _mandateMaxAmountCtrl.text.trim();
    if (opt('mandate.start_date') && notEmpty(_mandateStartDateCtrl.text))
      map['mandate.start_date'] = _mandateStartDateCtrl.text.trim();
    if (opt('mandate.end_date') && notEmpty(_mandateEndDateCtrl.text))
      map['mandate.end_date'] = _mandateEndDateCtrl.text.trim();
    if (opt('mandate.frequency'))
      map['mandate.frequency'] = _mandateFrequencyCtrl.text.trim();
    if (_mandateRevokable) map['mandate.revokable_by_customer'] = 'true';
    if (_mandateBlockFunds) map['mandate.block_funds'] = 'true';
    if (opt('metadata.gateway_ref_id') && notEmpty(_gatewayRefIdCtrl.text))
      map['metadata.JUSPAY:gateway_reference_id'] =
          _gatewayRefIdCtrl.text.trim();
    if (_bankAccountEnabled && notEmpty(_bankAccNumberCtrl.text)) {
      final b = <String, String>{
        'bank_account_number': _bankAccNumberCtrl.text.trim()
      };
      if (notEmpty(_bankIfscCtrl.text))
        b['bank_ifsc'] = _bankIfscCtrl.text.trim();
      if (notEmpty(_bankCodeCtrl.text))
        b['juspay_bank_code'] = _bankCodeCtrl.text.trim();
      if (notEmpty(_bankBeneficiaryCtrl.text))
        b['bank_beneficiary_name'] = _bankBeneficiaryCtrl.text.trim();
      if (notEmpty(_bankAccIdCtrl.text))
        b['bank_account_id'] = _bankAccIdCtrl.text.trim();
      if (notEmpty(_bankAccTypeCtrl.text))
        b['bank_account_type'] = _bankAccTypeCtrl.text.trim();
      map['metadata.bank_account_details'] = [b];
    }
    if (_mutualFundEnabled && notEmpty(_mfMemberIdCtrl.text)) {
      final mf = <String, String>{
        'memberId': _mfMemberIdCtrl.text.trim(),
        'userId': _mfUserIdCtrl.text.trim(),
        'mfPartner': _mfPartnerCtrl.text.trim(),
        'orderNumber': _mfOrderNumberCtrl.text.trim(),
        'amount': _mfAmountCtrl.text.trim(),
        'investmentType': _mfInvestmentTypeCtrl.text.trim(),
      };
      if (notEmpty(_mfSchemeCodeCtrl.text))
        mf['schemeCode'] = _mfSchemeCodeCtrl.text.trim();
      if (notEmpty(_mfFolioCtrl.text))
        mf['folioNumber'] = _mfFolioCtrl.text.trim();
      if (notEmpty(_mfPanCtrl.text)) mf['panNumber'] = _mfPanCtrl.text.trim();
      if (notEmpty(_mfAmcCodeCtrl.text))
        mf['amcCode'] = _mfAmcCodeCtrl.text.trim();
      if (notEmpty(_mfIhNumberCtrl.text))
        mf['ihNumber'] = _mfIhNumberCtrl.text.trim();
      map['mutual_fund_details'] = jsonEncode([mf]);
    }
    if (_showExpiryEnabled && notEmpty(_expiryActiveTimeCtrl.text))
      map['showExpiry'] = {
        'isEnable': true,
        'activeTimeInMs': _expiryActiveTimeCtrl.text.trim()
      };
    if (_basketEnabled && notEmpty(_basketProductNameCtrl.text)) {
      final basket = <String, String>{
        'productName': _basketProductNameCtrl.text.trim(),
      };
      if (notEmpty(_basketProductIdCtrl.text))
        basket['id'] = _basketProductIdCtrl.text.trim();
      if (notEmpty(_basketQuantityCtrl.text))
        basket['quantity'] = _basketQuantityCtrl.text.trim();
      if (notEmpty(_basketUnitPriceCtrl.text))
        basket['unitPrice'] = _basketUnitPriceCtrl.text.trim();
      map['basket'] = jsonEncode([basket]);
    }
    if (_amountInfoEnabled && notEmpty(_amountInfoBaseCtrl.text)) {
      final addons = <Map<String, String>>[];
      if (notEmpty(_amountInfoAddonsCtrl.text)) {
        try {
          final decoded = jsonDecode(_amountInfoAddonsCtrl.text) as List;
          addons.addAll(decoded.map((e) => Map<String, String>.from(e)));
        } catch (_) {}
      }
      map['amount_info'] = jsonEncode({
        'base_amount': _amountInfoBaseCtrl.text.trim(),
        'add_on_amounts': addons,
      });
    }
    // UDF 1-10
    final udfKeys = [
      'udf1',
      'udf2',
      'udf3',
      'udf4',
      'udf5',
      'udf6',
      'udf7',
      'udf8',
      'udf9',
      'udf10'
    ];
    final udfCtrls = [
      _udf1Ctrl,
      _udf2Ctrl,
      _udf3Ctrl,
      _udf4Ctrl,
      _udf5Ctrl,
      _udf6Ctrl,
      _udf7Ctrl,
      _udf8Ctrl,
      _udf9Ctrl,
      _udf10Ctrl
    ];
    for (int i = 0; i < udfKeys.length; i++) {
      if ((opt(udfKeys[i])) && notEmpty(udfCtrls[i].text))
        map[udfKeys[i]] = udfCtrls[i].text.trim();
    }

    // features — signed inside orderDetails
    if (_paymentAttemptEnabled)
      map['features'] = {
        'paymentAttempt': {'enable': true}
      };

    return map;
  }

  // ── Sign and construct ────────────────────────────────────────────────────
  Future<void> _signAndConstruct() async {
    setState(() => _signing = true);

    final orderDetails = _buildOrderDetails();
    final orderDetailsJson = const JsonEncoder().convert(orderDetails);
    final prettyOrderDetails =
        const JsonEncoder.withIndent('  ').convert(orderDetails);

    widget.onLog(LogEntry(
      title: '▲ PP-Signature — orderDetails Payload',
      body: prettyOrderDetails,
      type: LogType.request,
    ));

    try {
      final privateKey = _privateKeyCtrl.text.trim();
      if (privateKey.contains('PASTE YOUR PRIVATE KEY')) {
        throw Exception('Please paste your RSA private key.');
      }

      // Sign the JSON string of orderDetails
      final signature = _rsaSign(orderDetailsJson, privateKey);
      widget.onLog(LogEntry(
        title: '✓ Signature Generated (RSA-SHA256 + Base64)',
        body: signature,
        type: LogType.success,
      ));

      // Process payload: required top-level fields + orderDetails (signed) + signature.
      // All toggled optional fields are already baked into orderDetails by _buildOrderDetails().
      final payload = <String, dynamic>{
        'action': 'paymentPage',
        'merchantId': orderDetails['merchant_id'],
        'clientId': orderDetails['clientId'],
        'orderId': orderDetails['order_id'],
        'amount': orderDetails['amount'],
        'customerId': orderDetails['customer_id'],
        'customerEmail': orderDetails['customer_email'],
        'customerMobile': orderDetails['customer_phone'],
        'orderDetails': orderDetailsJson,
        'signature': signature,
        'merchantKeyId': _merchantKeyIdCtrl.text.trim(),
      };
      final processPayload = {
        'requestId': _generateUuidV4(),
        'service': 'in.juspay.hyperpay',
        'payload': payload,
      };

      setState(() {
        _generatedSignature = signature;
        _constructedOrderDetails = orderDetails;
        _constructedProcessPayload = processPayload;
        _processPayloadCtrl.text =
            const JsonEncoder.withIndent('  ').convert(processPayload);
      });

      widget.onLog(LogEntry(
        title: '✓ Process Payload Constructed',
        body: const JsonEncoder.withIndent('  ').convert(processPayload),
        type: LogType.info,
      ));
    } catch (e) {
      widget.onLog(LogEntry(
        title: '✕ Signing Failed',
        body: e.toString(),
        type: LogType.error,
      ));
      setState(() {
        _generatedSignature = null;
      });
    } finally {
      setState(() => _signing = false);
    }
  }

  void _refreshOrderId() {
    setState(() {
      _orderIdCtrl.text = 't${DateTime.now().millisecondsSinceEpoch}';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isInitiated) {
      return _buildLockedState();
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildOrderDetailsCard(),
        const SizedBox(height: 14),
        _buildSignatureCard(),
        const SizedBox(height: 14),
        if (_constructedProcessPayload != null) _buildOutputCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Locked state ──────────────────────────────────────────────────────────
  Widget _buildLockedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF37474F).withOpacity(0.1),
              shape: BoxShape.circle,
              border:
                  Border.all(color: const Color(0xFF37474F).withOpacity(0.3)),
            ),
            child: const Icon(Icons.lock_outline_rounded,
                color: Color(0xFF37474F), size: 28),
          ),
          const SizedBox(height: 16),
          const Text('PP — Signature Locked',
              style: TextStyle(
                  color: Color(0xFF8AA0B0),
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Complete Step 01 (Initiate SDK) in the\nIntegration tab to unlock.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF3A5070), fontSize: 13),
          ),
        ]),
      ),
    );
  }

  // ── Step 1: Order Details ─────────────────────────────────────────────────
  Widget _buildOrderDetailsCard() {
    return _SigShell(
      icon: Icons.receipt_long_rounded,
      title: 'Order Details',
      subtitle: 'Build & select payload fields',
      accent: const Color(0xFF4DA3FF),
      done: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Required fields header
        _sectionLabel('REQUIRED FIELDS'),
        const SizedBox(height: 8),
        _formField('clientId', _clientIdCtrl),
        _formField('merchantId', _merchantIdCtrl),
        Row(children: [
          Expanded(child: _formField('orderId', _orderIdCtrl)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _refreshOrderId,
            child: Container(
              margin: const EdgeInsets.only(top: 18),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4DA3FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: const Color(0xFF4DA3FF).withOpacity(0.3)),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF4DA3FF), size: 15),
            ),
          ),
        ]),
        _formField('amount', _amountCtrl, hint: '10.00'),
        _formField('customerId', _customerIdCtrl),
        _formField('customerEmail', _customerEmailCtrl),
        _formField('customerPhone', _customerPhoneCtrl),
        _formField('returnUrl', _returnUrlCtrl),
        _formField('environment', _environmentCtrl),
        const SizedBox(height: 14),
        // Optional fields
        _sectionLabel('OPTIONAL FIELDS'),
        const SizedBox(height: 8),
        _optionalField('description', 'description', _descriptionCtrl),
        _optionalField('currency', 'currency', _currencyCtrl),
        _optionalField('firstName', 'firstName', _firstNameCtrl),
        _optionalField('lastName', 'lastName', _lastNameCtrl),
        _optionalField('language', 'language', _languageCtrl),
        _optionalField('displayNote', 'displayNote', _displayNoteCtrl),
        _optionalField('payeeName', 'payeeName', _payeeNameCtrl),
        const SizedBox(height: 6),
        _sectionLabel('FEATURES & MANDATE'),
        const SizedBox(height: 8),
        _optionalFieldWithDropdown('order_type', 'order_type', _orderTypeCtrl,
            ['TPV_PAYMENT', 'MANDATE']),
        _optionalFieldWithDropdown(
            'options.create_mandate',
            'options.create_mandate',
            _createMandateCtrl,
            ['REQUIRED', 'OPTIONAL']),
        _optionalField(
            'mandate.max_amount', 'mandate.max_amount', _mandateMaxAmountCtrl),
        _toggleRow(
            'features.paymentAttempt.enabled',
            _paymentAttemptEnabled,
            (v) => setState(() => _paymentAttemptEnabled = v),
            'Receive event when user taps Proceed to Pay'),
        if (_paymentAttemptEnabled) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4DA3FF).withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: const Color(0xFF4DA3FF).withOpacity(0.2)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('resumePayment auto-response',
                  style: TextStyle(
                      color: Color(0xFF4DA3FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'When paymentAttempt event fires, SDK will auto-call resumePayment with the status below.',
                style: TextStyle(color: Color(0xFF3A5070), fontSize: 10),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Text('status:',
                    style: TextStyle(color: Color(0xFF6A8AAA), fontSize: 11)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => setState(() => _resumePaymentApprove = true),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _resumePaymentApprove
                          ? const Color(0xFF69F0AE).withOpacity(0.15)
                          : const Color(0xFF0F2540),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _resumePaymentApprove
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFF1A3050),
                      ),
                    ),
                    child: Text('true  ✓ APPROVE',
                        style: TextStyle(
                          color: _resumePaymentApprove
                              ? const Color(0xFF69F0AE)
                              : const Color(0xFF3A5070),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _resumePaymentApprove = false),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: !_resumePaymentApprove
                          ? const Color(0xFFFF6B6B).withOpacity(0.15)
                          : const Color(0xFF0F2540),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: !_resumePaymentApprove
                            ? const Color(0xFFFF6B6B)
                            : const Color(0xFF1A3050),
                      ),
                    ),
                    child: Text('false  ✕ ABORT',
                        style: TextStyle(
                          color: !_resumePaymentApprove
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF3A5070),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
              ]),
              if (_pendingTxnReference != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB74D).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: const Color(0xFFFFB74D).withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.pending_rounded,
                        color: Color(0xFFFFB74D), size: 12),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Last txnRef: $_pendingTxnReference',
                          style: const TextStyle(
                              color: Color(0xFFFFB74D),
                              fontSize: 10,
                              fontFamily: 'monospace')),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 6),
        _sectionLabel('MANDATE DETAILS'),
        const SizedBox(height: 8),
        _optionalField('mandate.start_date', 'mandate.start_date (UNIX epoch)',
            _mandateStartDateCtrl,
            hint: 'e.g. 1700000000000'),
        _optionalField('mandate.end_date', 'mandate.end_date (UNIX epoch)',
            _mandateEndDateCtrl,
            hint: 'e.g. 1800000000000'),
        _optionalFieldWithDropdown(
            'mandate.frequency', 'mandate.frequency', _mandateFrequencyCtrl, [
          'ASPRESENTED',
          'ONETIME',
          'DAILY',
          'WEEKLY',
          'FORTNIGHTLY',
          'MONTHLY',
          'BIMONTHLY',
          'QUARTERLY',
          'HALFYEARLY',
          'YEARLY'
        ]),
        _toggleRow(
            'mandate.revokable_by_customer',
            _mandateRevokable,
            (v) => setState(() => _mandateRevokable = v),
            'Customer can revoke this mandate'),
        _toggleRow(
            'mandate.block_funds',
            _mandateBlockFunds,
            (v) => setState(() => _mandateBlockFunds = v),
            'Block funds for mandate'),
        const SizedBox(height: 6),
        _sectionLabel('METADATA'),
        const SizedBox(height: 8),
        _optionalField('metadata.gateway_ref_id',
            'metadata.JUSPAY:gateway_reference_id', _gatewayRefIdCtrl),
        const SizedBox(height: 6),
        _sectionLabel('BANK ACCOUNT DETAILS (TPV)'),
        const SizedBox(height: 8),
        _toggleRow(
            'metadata.bank_account_details',
            _bankAccountEnabled,
            (v) => setState(() => _bankAccountEnabled = v),
            'Applicable for TPV Orders'),
        if (_bankAccountEnabled) ...[
          const SizedBox(height: 6),
          _formField('bank_account_number *', _bankAccNumberCtrl),
          _formField('bank_ifsc', _bankIfscCtrl),
          _formField('juspay_bank_code', _bankCodeCtrl, hint: 'e.g. JP_HDFC'),
          _formField('bank_beneficiary_name', _bankBeneficiaryCtrl),
          _formField('bank_account_id', _bankAccIdCtrl),
          _optionalFieldWithDropdown('bank_account_type', 'bank_account_type',
              _bankAccTypeCtrl, ['SAVINGS', 'CURRENT']),
        ],
        const SizedBox(height: 6),
        _sectionLabel('MUTUAL FUND DETAILS'),
        const SizedBox(height: 8),
        _toggleRow(
            'mutual_fund_details',
            _mutualFundEnabled,
            (v) => setState(() => _mutualFundEnabled = v),
            'Stringified MF details array'),
        if (_mutualFundEnabled) ...[
          const SizedBox(height: 6),
          _formField('memberId *', _mfMemberIdCtrl),
          _formField('userId *', _mfUserIdCtrl),
          _optionalFieldWithDropdown('mfPartner *', 'mfPartner', _mfPartnerCtrl,
              ['NSE', 'BSE', 'KFIN', 'CAMS']),
          _formField('orderNumber *', _mfOrderNumberCtrl),
          _formField('amount *', _mfAmountCtrl),
          _optionalFieldWithDropdown('investmentType *', 'investmentType',
              _mfInvestmentTypeCtrl, ['LUMPSUM', 'SIP']),
          _formField('schemeCode', _mfSchemeCodeCtrl),
          _formField('folioNumber', _mfFolioCtrl),
          _formField('panNumber (UPPERCASE)', _mfPanCtrl),
          _formField('amcCode', _mfAmcCodeCtrl),
          _formField('ihNumber', _mfIhNumberCtrl),
        ],
        const SizedBox(height: 6),
        _sectionLabel('BASKET (Cart Items)'),
        const SizedBox(height: 8),
        _toggleRow(
            'basket',
            _basketEnabled,
            (v) => setState(() => _basketEnabled = v),
            'Stringified product details (basket/cart)'),
        if (_basketEnabled) ...[
          const SizedBox(height: 6),
          _formField('productName', _basketProductNameCtrl),
          _formField('id (Product ID)', _basketProductIdCtrl),
          _formField('quantity', _basketQuantityCtrl),
          _formField('unitPrice', _basketUnitPriceCtrl),
        ],
        const SizedBox(height: 6),
        _sectionLabel('AMOUNT INFO (Surcharge / Fees)'),
        const SizedBox(height: 8),
        _toggleRow(
            'amount_info',
            _amountInfoEnabled,
            (v) => setState(() => _amountInfoEnabled = v),
            'Stringified amount breakup (surcharge, convenience fee, etc.)'),
        if (_amountInfoEnabled) ...[
          const SizedBox(height: 6),
          _formField('base_amount', _amountInfoBaseCtrl, hint: 'e.g. 100'),
          _formField('add_on_amounts (JSON array)', _amountInfoAddonsCtrl,
              hint: '[{"name":"SURCHARGE","amount":"2"}]'),
        ],
        const SizedBox(height: 6),
        _sectionLabel('SHOW EXPIRY TIMER'),
        const SizedBox(height: 8),
        _toggleRow(
            'showExpiry.isEnable',
            _showExpiryEnabled,
            (v) => setState(() => _showExpiryEnabled = v),
            'Show countdown timer on payment page'),
        if (_showExpiryEnabled) ...[
          const SizedBox(height: 6),
          _formField('activeTimeInMs *', _expiryActiveTimeCtrl,
              hint: 'e.g. 300000 (5 mins)'),
        ],
        const SizedBox(height: 6),
        _sectionLabel('UDF FIELDS'),
        const SizedBox(height: 8),
        _optionalField('udf1', 'udf1', _udf1Ctrl),
        _optionalField('udf2', 'udf2', _udf2Ctrl),
        _optionalField('udf3', 'udf3', _udf3Ctrl),
        _optionalField('udf4', 'udf4', _udf4Ctrl),
        _optionalField('udf5', 'udf5', _udf5Ctrl),
        _optionalField('udf6', 'udf6', _udf6Ctrl),
        _optionalField('udf7', 'udf7', _udf7Ctrl),
        _optionalField('udf8', 'udf8', _udf8Ctrl),
        _optionalField('udf9', 'udf9', _udf9Ctrl),
        _optionalField('udf10', 'udf10', _udf10Ctrl),
      ]),
    );
  }

  // ── Step 2: Signature ─────────────────────────────────────────────────────
  Widget _buildSignatureCard() {
    return _SigShell(
      icon: Icons.key_rounded,
      title: 'Sign & Construct Process Payload',
      subtitle: 'RSA-SHA256 signature → auto-build process payload',
      accent: const Color(0xFFCE93D8),
      done: _generatedSignature != null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('RSA PRIVATE KEY (PEM)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D).withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFFB74D), size: 13),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'For testing only. Never embed private keys in production apps.',
                style: TextStyle(color: Color(0xFFFFB74D), fontSize: 10),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        _formField('merchantKeyId', _merchantKeyIdCtrl,
            hint: 'Testvadivel - 154459'),
        const SizedBox(height: 8),
        TextField(
          controller: _privateKeyCtrl,
          maxLines: 6,
          style: const TextStyle(
              color: Color(0xFF8AB8D0), fontSize: 11, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText:
                '-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----',
            hintStyle: const TextStyle(color: Color(0xFF1E3A5F), fontSize: 11),
            filled: true,
            fillColor: const Color(0xFF071320),
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF0F2540))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF0F2540))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFFCE93D8), width: 1.5)),
          ),
        ),
        const SizedBox(height: 12),
        _SigActionButton(
          label: 'SIGN & BUILD PROCESS PAYLOAD',
          icon: Icons.draw_rounded,
          color: const Color(0xFFCE93D8),
          loading: _signing,
          onPressed: _signAndConstruct,
        ),
        if (_generatedSignature != null) ...[
          const SizedBox(height: 10),
          _signatureBanner(),
        ],
      ]),
    );
  }

  // ── Step 3: Output ────────────────────────────────────────────────────────
  Widget _buildOutputCard() {
    return _SigShell(
      icon: Icons.output_rounded,
      title: 'Generated Process Payload',
      subtitle: 'Copy this into the Process Payment step',
      accent: const Color(0xFF69F0AE),
      done: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Process Payload',
              style: TextStyle(
                  color: Color(0xFF6A8AAA), fontSize: 11, letterSpacing: 0.4)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _processPayloadCtrl.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Process payload copied'),
                  duration: Duration(seconds: 1)));
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.copy_rounded,
                  color: Color(0xFF69F0AE), size: 13),
              const SizedBox(width: 4),
              const Text('Copy',
                  style: TextStyle(
                      color: Color(0xFF69F0AE),
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        JsonInputField(controller: _processPayloadCtrl, label: ''),
        const SizedBox(height: 12),
        _SigActionButton(
          label: 'PROCESS PAYMENT',
          icon: Icons.send_rounded,
          color: const Color(0xFF69F0AE),
          loading: _processing,
          onPressed:
              _constructedProcessPayload != null ? _processPayment : null,
        ),
      ]),
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label) {
    return Row(children: [
      Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
              color: const Color(0xFF4DA3FF),
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(
              color: Color(0xFF4A6A8A),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2)),
    ]);
  }

  Widget _formField(String key, TextEditingController ctrl, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(key,
            style: const TextStyle(
                color: Color(0xFF6A8AAA), fontSize: 10, letterSpacing: 0.3)),
        const SizedBox(height: 3),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Color(0xFFCCE4FF), fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF1E3A5F)),
            filled: true,
            fillColor: const Color(0xFF0A1828),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: Color(0xFF0F2540))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: Color(0xFF0F2540))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide:
                    const BorderSide(color: Color(0xFF4DA3FF), width: 1.5)),
          ),
        ),
      ]),
    );
  }

  Widget _optionalField(
      String toggleKey, String label, TextEditingController ctrl,
      {String? hint}) {
    final enabled = _optionalEnabled[toggleKey] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => _optionalEnabled[toggleKey] = !enabled),
          child: Container(
            width: 36,
            height: 20,
            decoration: BoxDecoration(
              color: enabled
                  ? const Color(0xFF4DA3FF).withOpacity(0.2)
                  : const Color(0xFF0F2540),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: enabled
                      ? const Color(0xFF4DA3FF)
                      : const Color(0xFF1A3050)),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFF4DA3FF)
                      : const Color(0xFF2A4060),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 150),
            child: _formField(label, ctrl, hint: hint),
          ),
        ),
      ]),
    );
  }

  // ── Optional field with dropdown ─────────────────────────────────────────
  Widget _optionalFieldWithDropdown(String toggleKey, String label,
      TextEditingController ctrl, List<String> options) {
    final enabled = _optionalEnabled[toggleKey] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => _optionalEnabled[toggleKey] = !enabled),
          child: Container(
            width: 36,
            height: 20,
            decoration: BoxDecoration(
              color: enabled
                  ? const Color(0xFF4DA3FF).withOpacity(0.2)
                  : const Color(0xFF0F2540),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: enabled
                      ? const Color(0xFF4DA3FF)
                      : const Color(0xFF1A3050)),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFF4DA3FF)
                      : const Color(0xFF2A4060),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 150),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF6A8AAA),
                      fontSize: 10,
                      letterSpacing: 0.3)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1828),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF0F2540)),
                ),
                child: DropdownButton<String>(
                  value:
                      options.contains(ctrl.text) ? ctrl.text : options.first,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF0B1A2E),
                  underline: const SizedBox(),
                  style:
                      const TextStyle(color: Color(0xFFCCE4FF), fontSize: 12),
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
                  onChanged: enabled
                      ? (v) => setState(() => ctrl.text = v ?? ctrl.text)
                      : null,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Simple boolean toggle row ─────────────────────────────────────────────
  Widget _toggleRow(
      String label, bool value, void Function(bool) onChanged, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 36,
            height: 20,
            decoration: BoxDecoration(
              color: value
                  ? const Color(0xFF69F0AE).withOpacity(0.2)
                  : const Color(0xFF0F2540),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: value
                      ? const Color(0xFF69F0AE)
                      : const Color(0xFF1A3050)),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color:
                      value ? const Color(0xFF69F0AE) : const Color(0xFF2A4060),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF6A8AAA),
                    fontSize: 10,
                    letterSpacing: 0.3)),
            Text(hint,
                style: const TextStyle(color: Color(0xFF3A5070), fontSize: 9)),
          ]),
        ),
        if (value)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF69F0AE).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('ON',
                style: TextStyle(
                    color: Color(0xFF69F0AE),
                    fontSize: 9,
                    fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }

  Widget _signatureBanner() {
    final short = _generatedSignature!.length > 40
        ? '${_generatedSignature!.substring(0, 40)}...'
        : _generatedSignature!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFCE93D8).withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCE93D8).withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.verified_rounded, color: Color(0xFFCE93D8), size: 14),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Signature (RSA-SHA256 / Base64)',
                style: TextStyle(
                    color: Color(0xFFCE93D8),
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(short,
                style: const TextStyle(
                    color: Color(0xFF9A7AB0),
                    fontSize: 10,
                    fontFamily: 'monospace')),
          ]),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _generatedSignature!));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Signature copied'),
                duration: Duration(seconds: 1)));
          },
          child: const Icon(Icons.copy_rounded,
              color: Color(0xFFCE93D8), size: 14),
        ),
      ]),
    );
  }
}

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

// ── Shell widget ──────────────────────────────────────────────────────────────
class _SigShell extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color accent;
  final bool done;
  final Widget child;

  const _SigShell({
    required this.icon,
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
              child: Center(child: Icon(icon, color: accent, size: 14)),
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
                  ]),
            ),
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

// ── Action button ─────────────────────────────────────────────────────────────
class _SigActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;

  const _SigActionButton({
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
            loading ? 'SIGNING...' : label,
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
