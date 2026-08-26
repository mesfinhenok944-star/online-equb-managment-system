import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import '../../services/firestore_direct_service.dart';
import '../../widgets/smart_back_button.dart';
import '../../widgets/offline_banner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentScreen
//
// Full payment form for Ethiopian Equb members:
//  • Auto-fills user name + email + unique ID from logged-in profile
//  • Loads level-specific admin bank account info from Firestore
//    (equb_payment_accounts collection seeded per level)
//  • Shows correct account number for each bank/method selection
//  • Screenshot proof is mandatory
//  • On submit → saved to Firestore payments collection with equbLevel
//  • Admin sees payment in Payments tab → approve / reject with reason
// ─────────────────────────────────────────────────────────────────────────────

class PaymentScreen extends StatefulWidget {
  final String equbId;
  final String participantId;
  final double amount;
  final String initialLevel;

  const PaymentScreen({
    super.key,
    this.equbId       = '',
    this.participantId = '',
    this.amount       = 1000.0,
    this.initialLevel  = 'low',
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _firstNameController  = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController   = TextEditingController();
  final _emailController      = TextEditingController();
  final _uniqueIdController   = TextEditingController();
  final _referenceController  = TextEditingController();
  final _amountController     = TextEditingController();

  late String _selectedLevel;
  String  _selectedBank    = 'CBE';
  bool    _loading         = false;
  bool    _loadingAccounts = true;
  bool    _isAmharic       = false;
  XFile?  _proofImageFile;
  String? _proofImageBase64;

  // Loaded from Firestore equb_payment_accounts/{level}
  Map<String, dynamic> _levelAccountData = {};

  // Default fallback accounts (if Firestore not yet loaded)
  static const Map<String, Map<String, Map<String, String>>> _fallback = {
    'low': {
      'CBE':      {'accountNo': '1000456789012', 'accountTitle': 'ዝቅተኛ ደረጃ እቁብ PLC', 'type': 'Bank Deposit / CBE Mobile'},
      'Telebirr': {'accountNo': '+251911001122', 'accountTitle': 'Low Level Equb Official', 'type': 'Telebirr SuperApp'},
      'CBE Birr': {'accountNo': '*847# Merchant: LOW001', 'accountTitle': 'Low Level Equb', 'type': 'CBE Birr Mobile'},
      'Abyssinia':{'accountNo': '112233445566',  'accountTitle': 'ዝቅተኛ ደረጃ እቁብ PLC', 'type': 'BOA Mobile'},
      'Awash':    {'accountNo': '01323344556600','accountTitle': 'Low Level Equb PLC', 'type': 'Awash Pay'},
    },
    'medium': {
      'CBE':      {'accountNo': '1000567890123', 'accountTitle': 'መካከለኛ ደረጃ እቁብ PLC', 'type': 'Bank Deposit / CBE Mobile'},
      'Telebirr': {'accountNo': '+251911223355', 'accountTitle': 'Medium Level Equb Official', 'type': 'Telebirr SuperApp'},
      'CBE Birr': {'accountNo': '*847# Merchant: MED002', 'accountTitle': 'Medium Level Equb', 'type': 'CBE Birr Mobile'},
      'Abyssinia':{'accountNo': '223344556677',  'accountTitle': 'መካከለኛ ደረጃ እቁብ PLC', 'type': 'BOA Mobile'},
      'Awash':    {'accountNo': '01324455667700','accountTitle': 'Medium Level Equb PLC', 'type': 'Awash Pay'},
    },
    'high': {
      'CBE':      {'accountNo': '1000678901234', 'accountTitle': 'ከፍተኛ ደረጃ እቁብ PLC', 'type': 'Bank Deposit / CBE Mobile'},
      'Telebirr': {'accountNo': '+251911334466', 'accountTitle': 'High Level Equb VIP', 'type': 'Telebirr SuperApp'},
      'CBE Birr': {'accountNo': '*847# Merchant: HIGH003', 'accountTitle': 'High Level Equb VIP', 'type': 'CBE Birr Mobile'},
      'Abyssinia':{'accountNo': '334455667788',  'accountTitle': 'ከፍተኛ ደረጃ እቁብ PLC', 'type': 'BOA Mobile'},
      'Awash':    {'accountNo': '01325566778800','accountTitle': 'High Level Equb PLC', 'type': 'Awash Pay'},
      'Dashen':   {'accountNo': '5199876543210', 'accountTitle': 'High Level Equb VIP PLC', 'type': 'Amole / Dashen Pay'},
    },
  };

  // ── Available banks per level ─────────────────────────────────────────────
  List<String> get _availableBanks {
    final lvlFallback = _fallback[_selectedLevel] ?? _fallback['low']!;
    final firestoreBanks = _levelAccountData['banks'];
    if (firestoreBanks is Map && firestoreBanks.isNotEmpty) {
      return firestoreBanks.keys.cast<String>().toList();
    }
    return lvlFallback.keys.toList();
  }

  // ── Account info for selected bank + level ────────────────────────────────
  Map<String, String> get _currentBankInfo {
    final firestoreBanks = _levelAccountData['banks'];
    if (firestoreBanks is Map && firestoreBanks.containsKey(_selectedBank)) {
      final b = Map<String, dynamic>.from(firestoreBanks[_selectedBank] as Map);
      return {
        'accountNo':    (b['accountNo']    ?? '').toString(),
        'accountTitle': (b['accountTitle'] ?? '').toString(),
        'bankName':     (b['bankName']     ?? _selectedBank).toString(),
        'type':         (b['type']         ?? 'Bank Transfer').toString(),
      };
    }
    // Fallback
    final lvlFallback = _fallback[_selectedLevel] ?? _fallback['low']!;
    final info = lvlFallback[_selectedBank] ?? lvlFallback['CBE']!;
    return {
      'accountNo':    info['accountNo']    ?? '',
      'accountTitle': info['accountTitle'] ?? '',
      'bankName':     _selectedBank,
      'type':         info['type']         ?? '',
    };
  }

  Color get _levelColor {
    switch (_selectedLevel) {
      case 'medium': return AppColors.medium;
      case 'high':   return AppColors.high;
      default:       return AppColors.low;
    }
  }

  String get _levelLabel {
    if (_isAmharic) {
      switch (_selectedLevel) {
        case 'medium': return 'መካከለኛ ደረጃ';
        case 'high':   return 'ከፍተኛ ደረጃ';
        default:       return 'ዝቅተኛ ደረጃ';
      }
    }
    switch (_selectedLevel) {
      case 'medium': return 'Medium Level';
      case 'high':   return 'High Level';
      default:       return 'Low Level';
    }
  }

  String t(String en, String am) => _isAmharic ? am : en;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _selectedLevel = widget.initialLevel.toLowerCase().replaceAll('equb_', '').trim();
    if (_selectedLevel.isEmpty || !['low','medium','high'].contains(_selectedLevel)) {
      _selectedLevel = 'low';
    }
    _amountController.text = widget.amount > 0
        ? widget.amount.toStringAsFixed(0)
        : _defaultAmount();
    // Load user profile + account info after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoFillFromAuth();
      _loadLevelAccounts();
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _uniqueIdController.dispose();
    _referenceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _defaultAmount() {
    switch (_selectedLevel) {
      case 'high':   return '50000';
      case 'medium': return '10000';
      default:       return '1000';
    }
  }

  // ── Auto-fill user profile from AuthProvider ──────────────────────────────
  void _autoFillFromAuth() {
    try {
      final auth = context.read<AuthProvider>();
      final u = auth.user;
      if (u == null) return;

      // Full name — split from fullName or first/middle/last fields
      final fullName  = (u['fullName']  ?? '').toString().trim();
      final firstName = (u['firstName'] ?? u['first_name'] ?? '').toString().trim();
      final midName   = (u['middleName'] ?? u['fatherName'] ?? '').toString().trim();
      final lastName  = (u['lastName']  ?? u['last_name']  ?? '').toString().trim();

      if (firstName.isNotEmpty) {
        _firstNameController.text  = firstName;
        _middleNameController.text = midName;
        _lastNameController.text   = lastName;
      } else if (fullName.isNotEmpty) {
        final parts = fullName.split(' ');
        _firstNameController.text  = parts.isNotEmpty ? parts[0] : '';
        _middleNameController.text = parts.length > 1 ? parts[1] : '';
        _lastNameController.text   = parts.length > 2 ? parts.sublist(2).join(' ') : '';
      }

      // Email
      final email = (u['email'] ?? '').toString().trim();
      if (email.isNotEmpty && _emailController.text.isEmpty) {
        _emailController.text = email;
      }

      // Unique ID — from uniqueId / nationalId field
      final uid = (u['uniqueId'] ?? u['nationalId'] ?? u['participantId'] ?? '').toString().trim();
      if (uid.isNotEmpty && _uniqueIdController.text.isEmpty) {
        _uniqueIdController.text = uid;
      }

      // Level — use user's registered equb level
      final uLevel = (u['equbLevel'] ?? u['level'] ?? '').toString().toLowerCase().replaceAll('equb_', '').trim();
      if (['low','medium','high'].contains(uLevel) && uLevel != _selectedLevel) {
        setState(() {
          _selectedLevel = uLevel;
          _amountController.text = _defaultAmount();
        });
        _loadLevelAccounts();
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[PaymentScreen] _autoFillFromAuth: $e');
    }
  }

  // ── Load level-specific bank accounts from Firestore ─────────────────────
  Future<void> _loadLevelAccounts() async {
    setState(() => _loadingAccounts = true);
    try {
      // Use FirestoreDirectService to query equb_payment_accounts/{level}
      final token = await FirestoreDirectService.getAdminToken();
      if (token != null) {
        final url = 'https://firestore.googleapis.com/v1/projects/'
            'online-equb-managment-system/databases/(default)/documents/'
            'equb_payment_accounts/$_selectedLevel';
        final resp = await FirestoreDirectService.getDocument(url, token);
        if (resp != null && resp['fields'] != null) {
          setState(() {
            _levelAccountData = FirestoreDirectService.parseDocFields(
                Map<String, dynamic>.from(resp['fields'] as Map));
            _loadingAccounts = false;
          });
          // Reset bank selection if current bank not in available list
          if (!_availableBanks.contains(_selectedBank)) {
            setState(() => _selectedBank = _availableBanks.isNotEmpty
                ? _availableBanks.first : 'CBE');
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[PaymentScreen] _loadLevelAccounts: $e');
    }
    // Fallback — use hardcoded data
    if (mounted) setState(() => _loadingAccounts = false);
  }

  // ── Pick screenshot ───────────────────────────────────────────────────────
  Future<void> _pickProofScreenshot() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _proofImageFile   = image;
        _proofImageBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
      });
    }
  }

  // ── Submit payment ────────────────────────────────────────────────────────
  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;

    if (_proofImageBase64 == null || _proofImageBase64!.isEmpty) {
      _snack(t('📷 Please attach your bank receipt screenshot proof.',
               '📷 የባንክ ደረሰኝ ስክሪንሽት ያያይዙ።'),
             Colors.orange.shade800);
      return;
    }

    setState(() => _loading = true);

    try {
      final auth  = context.read<AuthProvider>();
      final user  = auth.user ?? {};
      final userId = (user['userId'] ?? user['id'] ?? user['uid'] ?? '').toString();

      final first  = _firstNameController.text.trim();
      final middle = _middleNameController.text.trim();
      final last   = _lastNameController.text.trim();
      final full   = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
      final amt    = double.tryParse(_amountController.text.trim()) ?? double.parse(_defaultAmount());
      final bankInfo = _currentBankInfo;

      final payload = <String, dynamic>{
        'userId':               userId,
        'firstName':            first,
        'middleName':           middle,
        'lastName':             last,
        'fullName':             full,
        'email':                _emailController.text.trim().toLowerCase(),
        'nationalId':           _uniqueIdController.text.trim(),
        'uniqueId':             _uniqueIdController.text.trim(),
        'equbLevel':            _selectedLevel,
        'level':                _selectedLevel,
        'bankName':             _selectedBank,
        'bankAccountNo':        bankInfo['accountNo'] ?? '',
        'bankAccountTitle':     bankInfo['accountTitle'] ?? '',
        'amount':               amt,
        'referenceNumber':      _referenceController.text.trim(),
        'proofScreenshotBase64': _proofImageBase64,
        'participantId':        widget.participantId.isNotEmpty ? widget.participantId : userId,
        'equbId':               widget.equbId,
        'status':               'pending_verification',
      };

      final res = await RoleManagementService.submitPayment(payload);

      if (!mounted) return;
      setState(() => _loading = false);

      if (res['success'] == true || res['paymentId'] != null) {
        _showSuccessDialog(ref: _referenceController.text.trim());
      } else {
        _snack(res['error'] ?? t('Submission failed. Try again.', 'ማስገባት አልተሳካም። ዳግም ሞክር።'), Colors.red);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Error: $e', Colors.red);
      }
    }
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: bg, duration: const Duration(seconds: 4)));
  }

  // ── Success dialog ────────────────────────────────────────────────────────
  void _showSuccessDialog({required String ref}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 30),
          const SizedBox(width: 10),
          Text(t('Payment Submitted!', 'ክፍያው ተልኳል!')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t(
            'Your payment proof has been sent to the $_levelLabel Admin for verification. '
            'You will be notified once approved.',
            'የክፍያ ደረሰኝዎ ለ$_levelLabel አስተዳዳሪ ተልኳል። ሲፀድቅ ይነገርዎታል።',
          ), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.shield_outlined, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                t('Reference: $ref', 'ማጣቀሻ: $ref'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
              )),
            ]),
          ),
        ]),
        actions: [
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.go('/home');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _levelColor),
            child: Text(t('OK — Go Back', 'እሺ — ተመለስ'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('Equb Payment', 'የእቁብ ክፍያ')),
        leading: const SmartBackButton(),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Text(_isAmharic ? 'EN' : 'አማ',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () => setState(() => _isAmharic = !_isAmharic),
          ),
        ],
      ),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── LEVEL HEADER ─────────────────────────────────────────────
              _buildLevelHeader(),
              const SizedBox(height: 16),

              // ── LEVEL SELECTOR ───────────────────────────────────────────
              _buildLevelSelector(),
              const SizedBox(height: 20),

              // ── ADMIN BANK ACCOUNT INFO ──────────────────────────────────
              _buildBankAccountSection(),
              const SizedBox(height: 20),

              // ── MEMBER IDENTITY ──────────────────────────────────────────
              _buildMemberSection(),
              const SizedBox(height: 20),

              // ── AMOUNT + REFERENCE ───────────────────────────────────────
              _buildAmountSection(),
              const SizedBox(height: 20),

              // ── PROOF SCREENSHOT ─────────────────────────────────────────
              _buildProofSection(),
              const SizedBox(height: 28),

              // ── SUBMIT BUTTON ────────────────────────────────────────────
              _buildSubmitButton(),
              const SizedBox(height: 30),
            ]),
          ),
        )),
      ]),
    );
  }

  // ── Level header ──────────────────────────────────────────────────────────
  Widget _buildLevelHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_levelColor, _levelColor.withOpacity(0.75)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: _levelColor.withOpacity(0.25), blurRadius: 10, offset: const Offset(0,4))],
      ),
      child: Row(children: [
        const Icon(Icons.payments_rounded, color: Colors.amber, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_levelLabel ${t("Equb — Payment Form", "እቁብ — ክፍያ ቅጽ")}',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(
            t('Pay to the admin account shown below. Attach receipt screenshot.',
              'ከታች ለሚታየው አስተዳዳሪ ሂሳብ ይክፈሉ። ደረሰኝ ስክሪንሽት ያያይዙ።'),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ])),
      ]),
    );
  }

  // ── Level selector ────────────────────────────────────────────────────────
  Widget _buildLevelSelector() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('Select Equb Level', 'የእቁብ ደረጃ ይምረጡ'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      Row(children: [
        _levelTab('low',    t('Low',    'ዝቅተኛ'),  AppColors.low),
        const SizedBox(width: 8),
        _levelTab('medium', t('Medium', 'መካከለኛ'), AppColors.medium),
        const SizedBox(width: 8),
        _levelTab('high',   t('High',   'ከፍተኛ'),  AppColors.high),
      ]),
    ]);
  }

  Widget _levelTab(String level, String label, Color color) {
    final sel = _selectedLevel == level;
    return Expanded(child: GestureDetector(
      onTap: () {
        setState(() {
          _selectedLevel = level;
          _amountController.text = _defaultAmount();
          if (!_availableBanks.contains(_selectedBank)) {
            _selectedBank = _availableBanks.isNotEmpty ? _availableBanks.first : 'CBE';
          }
        });
        _loadLevelAccounts();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: sel ? 0 : 1.5),
          boxShadow: sel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 6)] : [],
        ),
        child: Center(child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : color,
                fontWeight: FontWeight.bold,
                fontSize: 13))),
      ),
    ));
  }

  // ── Bank account section ──────────────────────────────────────────────────
  Widget _buildBankAccountSection() {
    final bankInfo = _currentBankInfo;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.account_balance_rounded, color: _levelColor, size: 20),
        const SizedBox(width: 8),
        Text(t('Admin Payment Account', 'የአስተዳዳሪ ሂሳብ ቁጥር'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        if (_loadingAccounts) ...[
          const SizedBox(width: 8),
          SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _levelColor)),
        ],
      ]),
      const SizedBox(height: 4),
      Text(t('Send your payment to this account and attach the receipt screenshot below.',
             'ወደ ዚህ ሂሳብ ክፍያ ፈፅሙ እና ደረሰኝ ስክሪንሽት ከዚህ በታች ያያይዙ።'),
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      const SizedBox(height: 12),

      // Bank selector
      DropdownButtonFormField<String>(
        value: _availableBanks.contains(_selectedBank) ? _selectedBank : _availableBanks.first,
        decoration: InputDecoration(
          labelText: t('Select Payment Bank / Method', 'የክፍያ ዘዴ ይምረጡ'),
          prefixIcon: Icon(Icons.account_balance, color: _levelColor),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true, fillColor: Colors.white,
        ),
        items: _availableBanks.map((b) => DropdownMenuItem(value: b, child: Text(_bankDisplayName(b)))).toList(),
        onChanged: (val) { if (val != null) setState(() => _selectedBank = val); },
      ),
      const SizedBox(height: 10),

      // Account details box
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _levelColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _levelColor.withOpacity(0.3)),
        ),
        child: Column(children: [
          _accountRow(Icons.account_balance,  t('Bank / Method', 'ባንክ / ዘዴ'),  bankInfo['bankName'] ?? _selectedBank),
          _accountRow(Icons.numbers,           t('Account Number',  'ሂሳብ ቁጥር'),  bankInfo['accountNo'] ?? ''),
          _accountRow(Icons.person_outline,    t('Account Name',    'ስም ባለቤት'),  bankInfo['accountTitle'] ?? ''),
          _accountRow(Icons.payment,           t('Transfer Type',   'ዓይነት'),     bankInfo['type'] ?? ''),
        ]),
      ),

      // Copy account number button
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: bankInfo['accountNo'] ?? ''));
          _snack(t('Account number copied!', 'ሂሳብ ቁጥሩ ተቀድቷል!'), Colors.green);
        },
        icon: const Icon(Icons.copy, size: 16),
        label: Text(t('Copy Account No.', 'ሂሳብ ቁጥሩን ቅዳ')),
        style: OutlinedButton.styleFrom(foregroundColor: _levelColor, side: BorderSide(color: _levelColor)),
      ),
    ]);
  }

  String _bankDisplayName(String bank) {
    const names = {
      'CBE':       'Commercial Bank of Ethiopia (CBE)',
      'Telebirr':  'Telebirr Mobile Money',
      'CBE Birr':  'CBE Birr Mobile',
      'Abyssinia': 'Bank of Abyssinia (BOA)',
      'Awash':     'Awash International Bank',
      'Dashen':    'Dashen Bank / Amole',
      'Other':     'Other Ethiopian Banks',
    };
    return names[bank] ?? bank;
  }

  Widget _accountRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: _levelColor),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── Member identity section ───────────────────────────────────────────────
  Widget _buildMemberSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0,2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified_user_rounded, color: _levelColor, size: 20),
          const SizedBox(width: 8),
          Text(t('Member Identity (must match admin records)', 'የአባል ማረጋገጫ (ከአስተዳዳሪ መዝገብ ጋር መመሳሰል አለበት)'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 14),

        // First Name
        _nameField(_firstNameController, t('First Name *', 'ስም *'), Icons.person),
        const SizedBox(height: 12),
        // Middle Name (Father)
        _nameField(_middleNameController, t('Father Name *', 'የአባት ስም *'), Icons.person_outline),
        const SizedBox(height: 12),
        // Last Name (Grandfather)
        _nameField(_lastNameController, t('Grandfather Name *', 'የአያት ስም *'), Icons.person_outline),
        const SizedBox(height: 12),

        // Email
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: t('Email Address *', 'ኢሜይል *'),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return t('Email required', 'ኢሜይል ያስፈልጋል');
            if (!RegExp(r'^[\w.\-]+@[\w\-]+\.[a-zA-Z]{2,}$').hasMatch(v.trim())) {
              return t('Enter valid email e.g. user@domain.com', 'ትክክለኛ ኢሜይል ያስፈልጋል');
            }
            return null;
          },
        ),
        const SizedBox(height: 12),

        // Unique Member ID
        TextFormField(
          controller: _uniqueIdController,
          decoration: InputDecoration(
            labelText: t('Member Unique ID *', 'የአባልነት መታወቂያ *'),
            prefixIcon: const Icon(Icons.badge_rounded),
            hintText: 'e.g. low01 or EQ-100234',
            helperText: t('Your registered equb member ID assigned by admin',
                          'አስተዳዳሪ የሰጠዎ የዕቁብ አባልነት መታወቂያ'),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return t('Member ID required', 'መታወቂያ ያስፈልጋል');
            if (v.trim().length < 2) return t('Too short', 'ቁጥሩ አጭር ነው');
            return null;
          },
        ),
      ]),
    );
  }

  Widget _nameField(TextEditingController ctrl, String label, IconData icon) {
    return TextFormField(
      controller: ctrl,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\u1200-\u137F ]'))],
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return t('Required', 'ያስፈልጋል');
        if (RegExp(r'[0-9]').hasMatch(v)) return t('No numbers in name', 'ቁጥር አይፈቀድም');
        if (v.trim().length < 2) return t('Min 2 characters', 'ቢያንስ 2 ቁምፊ');
        return null;
      },
    );
  }

  // ── Amount + reference section ────────────────────────────────────────────
  Widget _buildAmountSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Payment Amount & Reference', 'የክፍያ መጠን እና ማጣቀሻ'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 14),

        // Amount
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(
            labelText: 'Payment Amount (ETB) *',
            prefixIcon: Icon(Icons.payments_rounded),
            suffixText: 'ETB',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Amount required';
            final n = double.tryParse(v.trim());
            if (n == null || n <= 0) return 'Enter valid amount > 0';
            return null;
          },
        ),
        const SizedBox(height: 12),

        // Transaction reference
        TextFormField(
          controller: _referenceController,
          decoration: InputDecoration(
            labelText: t('Bank Transaction Reference # *', 'የደረሰኝ ቁጥር / FT Reference # *'),
            prefixIcon: const Icon(Icons.receipt_long),
            hintText: 'e.g. FT240987654321',
            helperText: t('Found on your bank receipt or transfer confirmation',
                          'ከባንክ ደረሰኝ ወይም ማረጋገጫ ቁጥር ላይ ይገኛል'),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return t('Reference # required', 'ማጣቀሻ ቁጥር ያስፈልጋል');
            if (v.trim().length < 6) return t('Min 6 characters', 'ቢያንስ 6 ቁምፊ');
            return null;
          },
        ),
      ]),
    );
  }

  // ── Screenshot proof section ──────────────────────────────────────────────
  Widget _buildProofSection() {
    final hasProof = _proofImageBase64 != null && _proofImageBase64!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: hasProof ? Colors.green : Colors.amber.shade700, width: 1.5),
      ),
      child: Column(children: [
        Row(children: [
          Icon(hasProof ? Icons.verified_rounded : Icons.add_a_photo_rounded,
              color: hasProof ? Colors.green : Colors.amber.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(
            t('Bank Receipt Screenshot (Required)', 'የባንክ ደረሰኝ ስክሪንሽት (አስፈላጊ)'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          )),
        ]),
        const SizedBox(height: 6),
        Text(
          t('Attach your authentic bank transfer / mobile payment screenshot. Admin will verify it.',
            'የባንክ ወይም የሞባይል ክፍያ ደረሰኝ ስክሪንሽት ያያይዙ። አስተዳዳሪው ያረጋግጣል።'),
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),

        if (hasProof) ...[
          // Preview row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green, width: 1.5),
            ),
            child: Row(children: [
              const Icon(Icons.image, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_proofImageFile?.name ?? 'screenshot.png',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                const Row(children: [
                  Icon(Icons.shield_rounded, color: Colors.green, size: 14),
                  SizedBox(width: 4),
                  Text('✅ Screenshot Ready for Submission',
                      style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                ]),
              ])),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                onPressed: () => setState(() { _proofImageFile = null; _proofImageBase64 = null; }),
                tooltip: t('Remove', 'አስወግድ'),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],

        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: _pickProofScreenshot,
          icon: const Icon(Icons.photo_library_rounded),
          label: Text(hasProof
              ? t('Change Screenshot', 'ስክሪንሽት ቀይር')
              : t('📎 Attach Receipt Screenshot', '📎 ደረሰኝ ስክሪንሽት ያያይዙ')),
          style: OutlinedButton.styleFrom(
            foregroundColor: hasProof ? Colors.green : _levelColor,
            side: BorderSide(color: hasProof ? Colors.green : _levelColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        )),
      ]),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    return SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _loading ? null : _submitPayment,
      icon: _loading
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : const Icon(Icons.send_rounded),
      label: Text(
        _loading
            ? t('Submitting…', 'በማስገባት ላይ…')
            : t('Submit Payment for Admin Verification',
               'ክፍያ ለአስተዳዳሪ ማረጋገጫ ያስገቡ'),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
      ),
    ));
  }
}
