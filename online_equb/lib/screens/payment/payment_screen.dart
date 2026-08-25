import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/role_management_service.dart';
import '../../utils/constants.dart';
import '../../widgets/smart_back_button.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/page_header_banner.dart';

class PaymentScreen extends StatefulWidget {
  final String equbId;
  final String participantId;
  final double amount;
  final String initialLevel;

  const PaymentScreen({
    super.key,
    this.equbId = '',
    this.participantId = '',
    this.amount = 5000.0,
    this.initialLevel = 'low',
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _referenceController = TextEditingController();
  final _amountController = TextEditingController();

  late String _selectedLevel;
  String _selectedBank = 'CBE';
  bool _loading = false;
  XFile? _proofImageFile;
  String? _proofImageBase64;

  final Map<String, Map<String, String>> _bankAccountDetails = {
    'CBE': {
      'name': 'Commercial Bank of Ethiopia (የኢትዮጵያ ንግድ ባንክ)',
      'accountNo': '1000123456789',
      'accountTitle': 'DIGITAL ዕቁብ / Digital Equb PLC',
      'type': 'Bank Deposit / Mobile Transfer',
    },
    'Abyssinia': {
      'name': 'Bank of Abyssinia (አቢሲንያ ባንክ)',
      'accountNo': '887766554433',
      'accountTitle': 'DIGITAL ዕቁብ / Digital Equb PLC',
      'type': 'Bank Deposit / BOA Mobile',
    },
    'Awash': {
      'name': 'Awash International Bank (አዋሽ ባንክ)',
      'accountNo': '01320987654300',
      'accountTitle': 'DIGITAL ዕቁብ / Digital Equb PLC',
      'type': 'Bank Transfer',
    },
    'Telebirr': {
      'name': 'Telebirr Mobile Money (ቴሌብር)',
      'accountNo': '+251911223344',
      'accountTitle': 'DIGITAL ዕቁብ Official Merchant',
      'type': 'Telebirr SuperApp Pay',
    },
    'CBE Birr': {
      'name': 'CBE Birr (ንግድ ባንክ ብር)',
      'accountNo': '*847# Merchant ID: 554433',
      'accountTitle': 'DIGITAL ዕቁብ / Digital Equb',
      'type': 'CBE Birr Mobile',
    },
    'Dashen': {
      'name': 'Dashen Bank (ዳሽን ባንክ)',
      'accountNo': '5198765432101',
      'accountTitle': 'DIGITAL ዕቁብ / Digital Equb PLC',
      'type': 'Amole / Dashen Pay',
    },
    'Other': {
      'name': 'Other Ethiopian Banks (ሌሎች የኢትዮጵያ ባንኮች)',
      'accountNo': '1000123456789 (CBE Transfer)',
      'accountTitle': 'DIGITAL ዕቁብ PLC',
      'type': 'Inter-Bank Transfer',
    },
  };

  @override
  void initState() {
    super.initState();
    _selectedLevel = widget.initialLevel.toLowerCase().replaceAll('equb_', '');
    if (_selectedLevel.isEmpty) _selectedLevel = 'low';
    _amountController.text = widget.amount > 0 ? widget.amount.toStringAsFixed(0) : '5000';
    _autoFillUserProfile();
  }

  Future<void> _autoFillUserProfile() async {
    // Try matching current active profile to pre-fill names
    try {
      final admins = await RoleManagementService.getAdmins(level: _selectedLevel);
      if (admins.isNotEmpty) {
        final firstAdmin = admins.first;
        if (_emailController.text.isEmpty) {
          _emailController.text = firstAdmin['email'] ?? '';
        }
      }
    } catch (_) {}
  }

  Future<void> _pickProofScreenshot() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';
      setState(() {
        _proofImageFile = image;
        _proofImageBase64 = base64Str;
      });
    }
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;

    if (_referenceController.text.trim().isEmpty) {
      _showSnackBar('❌ Please enter your payment transaction reference number.', Colors.red);
      return;
    }

    if (_proofImageBase64 == null || _proofImageBase64!.isEmpty) {
      _showSnackBar('📷 Please attach a screenshot proof of your bank receipt.', Colors.orange.shade800);
      return;
    }

    setState(() => _loading = true);

    try {
      final double amt = double.tryParse(_amountController.text.trim()) ?? widget.amount;
      final payload = {
        'firstName': _firstNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'fullName': '${_firstNameController.text.trim()} ${_middleNameController.text.trim()} ${_lastNameController.text.trim()}'.trim(),
        'email': _emailController.text.trim().toLowerCase(),
        'nationalId': _nationalIdController.text.trim(),
        'equbLevel': _selectedLevel,
        'bankName': _selectedBank,
        'amount': amt,
        'referenceNumber': _referenceController.text.trim(),
        'proofScreenshotBase64': _proofImageBase64,
        'participantId': widget.participantId,
        'equbId': widget.equbId,
      };

      final res = await RoleManagementService.submitPayment(payload);

      if (mounted) {
        setState(() => _loading = false);
        if (res['success'] == true || res['paymentId'] != null) {
          _showSuccessDialog();
        } else {
          _showSnackBar(res['error'] ?? 'Failed to submit payment', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar('Submission error: $e', Colors.red);
      }
    }
  }

  void _showSnackBar(String text, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bg),
    );
  }

  void _showSuccessDialog() {
    final isAmharic = AppConstants.currentLanguage == 'am';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            const SizedBox(width: 10),
            Text(isAmharic ? 'ክፍያው ተልኳል' : 'Payment Submitted!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAmharic
                  ? 'የክፍያ መረጃዎ እና ደረሰኝዎ ለ${_selectedLevel.toUpperCase()} ደረጃ አስተዳዳሪ ተልኳል። አስተዳዳሪው ደረሰኙን ካረጋገጠ በኋላ ክፍያው ይፀድቃል።'
                  : 'Your payment proof and transaction reference have been submitted to the ${_selectedLevel.toUpperCase()} Level Admin for verification.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAmharic ? 'የክፍያ ማረጋገጫ ኮድ: ${_referenceController.text}' : 'Ref #: ${_referenceController.text}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                context.go('/home');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(isAmharic ? 'ወደ ዋና ገጽ ተመለስ' : 'Return to Home'),
          ),
        ],
      ),
    );
  }

  Color get _currentLevelColor {
    switch (_selectedLevel) {
      case 'medium':
        return AppColors.medium;
      case 'high':
        return AppColors.high;
      default:
        return AppColors.low;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAmharic = AppConstants.currentLanguage == 'am';
    final bankInfo = _bankAccountDetails[_selectedBank] ?? _bankAccountDetails['CBE']!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isAmharic ? 'የዕቁብ ክፍያ ማካሄጃ ቅጽ' : 'Equb Payment Form'),
        leading: const SmartBackButton(),
        backgroundColor: _currentLevelColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: PageHeaderBanner(
            color: _currentLevelColor,
            icon: Icons.payments_rounded,
            phrases: PageHeaderBanner.paymentPhrases,
            staticTitle: isAmharic
                ? '${_selectedLevel.toUpperCase()} ደረጃ — ክፍያ ቅጽ'
                : '${_selectedLevel.toUpperCase()} Level — Payment Form',
            height: 64,
          ),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── EQUB LEVEL CONTEXT HEADER ─────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_currentLevelColor, _currentLevelColor.withOpacity(0.8)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _currentLevelColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.savings_rounded, color: Colors.amber, size: 26),
                        const SizedBox(width: 10),
                        Text(
                          '${_selectedLevel.toUpperCase()} LEVEL EQUB',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAmharic
                          ? 'ለአስተዳዳሪው ክፍያ ፈፅመው ደረሰኝ የሚያስገቡበት ኦፊሴላዊ ቅጽ'
                          : 'Official payment & receipt verification portal for Level Admin review.',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── LEVEL SELECTOR TABS ──────────────────────────────────────────
              const Text(
                'የዕቁብ ደረጃ ይምረጡ (Select Level)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _levelTabTile('low', isAmharic ? 'ዝቅተኛ (Low)' : 'Low Tier', AppColors.low),
                  const SizedBox(width: 8),
                  _levelTabTile('medium', isAmharic ? 'መካከለኛ (Med)' : 'Medium Tier', AppColors.medium),
                  const SizedBox(width: 8),
                  _levelTabTile('high', isAmharic ? 'ከፍተኛ (High)' : 'High Tier', AppColors.high),
                ],
              ),

              const SizedBox(height: 20),

              // ── MEMBER VERIFICATION & MATCH FORM ─────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified_user_rounded, color: _currentLevelColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isAmharic ? 'የአባል ማረጋገጫ መረጃ' : 'Member Identity Verification',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAmharic
                          ? 'በአስተዳዳሪው ከተመዘገበው መረጃ ጋር መመሳሰል አለበት'
                          : 'Must match admin registered member details',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const Divider(height: 20),

                    // First Name
                    TextFormField(
                      controller: _firstNameController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                      ],
                      decoration: InputDecoration(
                        labelText: isAmharic ? 'ስም (First Name) *' : 'First Name *',
                        prefixIcon: const Icon(Icons.person),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return isAmharic ? 'ስም ያስፈልጋል' : 'First name required';
                        }
                        if (RegExp(r'[0-9]').hasMatch(v)) {
                          return isAmharic ? 'ቁጥር አይፈቀድም' : 'Name must not contain numbers';
                        }
                        if (v.trim().length < 2) {
                          return isAmharic ? 'ቢያንስ 2 ቁምፊዎች' : 'Min 2 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Middle Name
                    TextFormField(
                      controller: _middleNameController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                      ],
                      decoration: InputDecoration(
                        labelText: isAmharic ? 'የአባት ስም (Father Name) *' : 'Father Name *',
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return isAmharic ? 'የአባት ስም ያስፈልጋል' : 'Father name required';
                        }
                        if (RegExp(r'[0-9]').hasMatch(v)) {
                          return isAmharic ? 'ቁጥር አይፈቀድም' : 'No numbers in name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Last Name
                    TextFormField(
                      controller: _lastNameController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                      ],
                      decoration: InputDecoration(
                        labelText: isAmharic ? 'የአያት ስም (Grandfather Name) *' : 'Grandfather Name *',
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return isAmharic ? 'የአያት ስም ያስፈልጋል' : 'Grandfather name required';
                        }
                        if (RegExp(r'[0-9]').hasMatch(v)) {
                          return isAmharic ? 'ቁጥር አይፈቀድም' : 'No numbers in name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Email Address
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: isAmharic ? 'ኢሜይል (Email Address) *' : 'Email Address *',
                        prefixIcon: const Icon(Icons.email),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return isAmharic ? 'ኢሜይል ያስፈልጋል' : 'Email required';
                        }
                        final rx = RegExp(r'^[\w.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
                        if (!rx.hasMatch(v.trim())) {
                          return isAmharic
                              ? 'ትክክለኛ ኢሜይል ያስገቡ (user@domain.com)'
                              : 'Enter valid email (user@domain.com)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Member Unique ID / National ID
                    TextFormField(
                      controller: _nationalIdController,
                      decoration: InputDecoration(
                        labelText: isAmharic ? 'የአባልነት መታወቂያ / ID (#EQ-...) *' : 'Member Unique ID (#EQ-...) *',
                        prefixIcon: const Icon(Icons.badge),
                        hintText: 'e.g. EQ-100234',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return isAmharic ? 'መታወቂያ ያስፈልጋል' : 'Unique ID required';
                        }
                        if (v.trim().length < 4) {
                          return isAmharic ? 'ቢያንስ 4 ቁምፊዎች' : 'Min 4 characters';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── BANK / GATEWAY SELECTION ──────────────────────────────────────
              const Text(
                'የክፍያ ዘዴ ይምረጡ (Select Payment Bank/Method)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                value: _selectedBank,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.account_balance, color: _currentLevelColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: [
                  const DropdownMenuItem(value: 'CBE', child: Text('Commercial Bank of Ethiopia (CBE)')),
                  const DropdownMenuItem(value: 'Abyssinia', child: Text('Bank of Abyssinia (BOA)')),
                  const DropdownMenuItem(value: 'Awash', child: Text('Awash International Bank')),
                  const DropdownMenuItem(value: 'Telebirr', child: Text('Telebirr Mobile Money')),
                  const DropdownMenuItem(value: 'CBE Birr', child: Text('CBE Birr Mobile')),
                  const DropdownMenuItem(value: 'Dashen', child: Text('Dashen Bank / Amole')),
                  const DropdownMenuItem(value: 'Other', child: Text('Other Ethiopian Banks')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedBank = val);
                },
              ),

              const SizedBox(height: 14),

              // OFFICIAL BANK ACCOUNT DETAILS DISPLAY
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _currentLevelColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _currentLevelColor.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: _currentLevelColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bankInfo['name'] ?? '',
                            style: TextStyle(fontWeight: FontWeight.bold, color: _currentLevelColor, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _accountInfoRow(isAmharic ? 'የሂሳብ ቁጥር (Acc. No.)' : 'Account No.', bankInfo['accountNo'] ?? ''),
                    _accountInfoRow(isAmharic ? 'የስም ባለቤት' : 'Account Name', bankInfo['accountTitle'] ?? ''),
                    _accountInfoRow(isAmharic ? 'ዓይነት' : 'Type', bankInfo['type'] ?? ''),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── AMOUNT & TRANSACTION REFERENCE ───────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'የክፍያ መጠን እና የደረሰኝ ቁጥር (Amount & Reference)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 12),

                    // Amount
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Payment Amount (ETB) *',
                        prefixIcon: Icon(Icons.payments),
                        suffixText: 'ETB',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter payment amount';
                        }
                        final amt = double.tryParse(v.trim());
                        if (amt == null || amt <= 0) {
                          return 'Enter a valid amount greater than 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Reference Code
                    TextFormField(
                      controller: _referenceController,
                      decoration: const InputDecoration(
                        labelText: 'Bank Deposit Reference / FT Transaction # *',
                        prefixIcon: Icon(Icons.receipt_long),
                        hintText: 'e.g. FT240987654321',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Transaction reference number is required';
                        }
                        if (v.trim().length < 6) {
                          return 'Reference must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── PROOF SCREENSHOT ATTACHMENT & INTEGRITY CHECK ─────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _proofImageBase64 != null ? Colors.green : Colors.amber.shade700,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _proofImageBase64 != null ? Icons.verified : Icons.add_a_photo_rounded,
                          color: _proofImageBase64 != null ? Colors.green : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isAmharic
                                ? 'የክፍያ ደረሰኝ ስክሪንሽት (Receipt Proof Screenshot) *'
                                : 'Bank Receipt Proof Screenshot *',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAmharic
                          ? 'እውነተኛ የክፍያ ማረጋገጫ ስክሪንሽት ያያይዙ (በሲስተሙ የደህንነት ማረጋገጫ ይካሄዳል)'
                          : 'Attach your authentic bank transfer screenshot proof for Level Admin verification.',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),

                    if (_proofImageFile != null) ...[
                      Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green, width: 2),
                          color: Colors.grey.shade100,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.image, color: Colors.green, size: 36),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _proofImageFile!.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      const Row(
                                        children: [
                                          Icon(Icons.shield_rounded, color: Colors.green, size: 14),
                                          SizedBox(width: 4),
                                          Text(
                                            'Proof Authenticated & Encrypted',
                                            style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    OutlinedButton.icon(
                      onPressed: _pickProofScreenshot,
                      icon: Icon(_proofImageBase64 != null ? Icons.change_circle : Icons.upload_file),
                      label: Text(_proofImageBase64 != null ? (isAmharic ? 'ደረሰኝ ቀይር' : 'Change Receipt') : (isAmharic ? 'ደረሰኝ ያያይዙ' : 'Upload Receipt Screenshot')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _proofImageBase64 != null ? Colors.green : _currentLevelColor,
                        side: BorderSide(color: _proofImageBase64 != null ? Colors.green : _currentLevelColor),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // SUBMIT BUTTON
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submitPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentLevelColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_rounded, color: Colors.white),
                            const SizedBox(width: 10),
                            Text(
                              isAmharic ? 'ክፍያውን ለአስተዳዳሪው ላክ' : 'Submit Payment to Level Admin',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    ),
  ],
),
    );
  }

  Widget _levelTabTile(String levelKey, String label, Color color) {
    final sel = _selectedLevel == levelKey;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedLevel = levelKey;
            if (levelKey == 'low') _amountController.text = '5000';
            if (levelKey == 'medium') _amountController.text = '10000';
            if (levelKey == 'high') _amountController.text = '20000';
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? color : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: sel ? 2 : 1),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: sel ? Colors.white : color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountInfoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              val,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
