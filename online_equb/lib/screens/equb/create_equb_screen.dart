import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/smart_back_button.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/firestore_service.dart';
import '../../widgets/page_header_banner.dart';
import '../../utils/constants.dart';

class CreateEqubScreen extends StatefulWidget {
  const CreateEqubScreen({super.key});
  @override
  State<CreateEqubScreen> createState() => _CreateEqubScreenState();
}

class _CreateEqubScreenState extends State<CreateEqubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _maxCtl = TextEditingController();
  final _descCtl = TextEditingController();
  String _level = 'low';
  String _schedule = 'weekly';
  bool _submitting = false;

  // Default amounts per level
  static const _defaultPrices = {'low': '5000', 'medium': '10000', 'high': '20000'};
  static const _defaultMax = {'low': '100', 'medium': '100', 'high': '100'};

  @override
  void initState() {
    super.initState();
    _applyLevelDefaults('low');
  }

  void _applyLevelDefaults(String lvl) {
    _priceCtl.text = _defaultPrices[lvl] ?? '5000';
    _maxCtl.text = _defaultMax[lvl] ?? '100';
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _priceCtl.dispose();
    _maxCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Color get _levelColor => switch (_level) {
        'medium' => AppColors.medium,
        'high' => AppColors.high,
        _ => AppColors.low,
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final price = double.tryParse(_priceCtl.text.trim()) ?? 0;
    final maxP = int.tryParse(_maxCtl.text.trim()) ?? 100;
    final adminFeeRate = _level == 'high' ? 0.10 : _level == 'medium' ? 0.07 : 0.05;
    final netPrize = price * maxP * (1 - adminFeeRate);
    final adminFee = price * maxP * adminFeeRate;

    final data = {
      'name': _nameCtl.text.trim(),
      'level': _level,
      'price': price,
      'netPrize': netPrize,
      'adminFee': adminFee,
      'maxParticipants': maxP,
      'currentParticipants': 0,
      'description': _descCtl.text.trim().isNotEmpty
          ? _descCtl.text.trim()
          : '${_level[0].toUpperCase()}${_level.substring(1)} Level Equb — $price ETB weekly contribution.',
      'paymentSchedule': _schedule,
      'drawTime': 'Every Sunday 12:00 PM',
      'riskLevel': _level == 'high' ? 'Premium' : _level == 'medium' ? 'Moderate' : 'Low',
      'targetAudience': _level == 'high'
          ? 'VIP Investors'
          : _level == 'medium'
              ? 'Business Owners'
              : 'General Public',
      'status': 'active',
    };

    try {
      final id = await FirestoreService.createEqub(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Equb created successfully!'),
        backgroundColor: AppColors.success,
      ));
      context.go('/equbs/$id');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to create equb: $e'),
        backgroundColor: AppColors.error,
      ));
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAmharic = AppConstants.currentLanguage == 'am';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: Text(isAmharic ? 'አዲስ እቁብ ፍጠር' : 'Create New Equb Level'),
        leading: const SmartBackButton(),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: PageHeaderBanner(
            color: _levelColor,
            icon: Icons.add_business_rounded,
            phrases: PageHeaderBanner.equbPhrases,
            staticTitle: isAmharic
                ? 'አዲስ $_level ደረጃ እቁብ'
                : 'New ${_level[0].toUpperCase()}${_level.substring(1)} Level Equb',
            height: 64,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Level selector ──────────────────────────────────────────
              _SCard(
                icon: Icons.savings_rounded,
                title: isAmharic ? 'የእቁብ ደረጃ ይምረጡ' : 'Select Equb Level',
                color: _levelColor,
                child: Row(children: [
                  _LvlTile('low', 'Low', AppColors.low, isAmharic ? 'ዝቅተኛ' : null),
                  const SizedBox(width: 8),
                  _LvlTile('medium', 'Medium', AppColors.medium, isAmharic ? 'መካከለኛ' : null),
                  const SizedBox(width: 8),
                  _LvlTile('high', 'High', AppColors.high, isAmharic ? 'ከፍተኛ' : null),
                ]),
              ),

              const SizedBox(height: 14),

              // ── Basic info ──────────────────────────────────────────────
              _SCard(
                icon: Icons.info_rounded,
                title: isAmharic ? 'መሠረታዊ መረጃ' : 'Basic Information',
                color: _levelColor,
                child: Column(children: [
                  _FField(
                    ctrl: _nameCtl,
                    label: isAmharic ? 'የእቁብ ስም *' : 'Equb Name *',
                    hint: isAmharic ? 'ለምሳሌ: ዝቅተኛ ደረጃ እቁብ' : 'e.g. Low Level Equb Group A',
                    icon: Icons.label_rounded,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return isAmharic ? 'ስም ያስፈልጋል' : 'Name is required';
                      }
                      if (v.trim().length < 4) {
                        return isAmharic ? 'ቢያንስ 4 ቁምፊዎች' : 'Min 4 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _FField(
                    ctrl: _descCtl,
                    label: isAmharic ? 'መግለጫ (አማራጭ)' : 'Description (optional)',
                    hint: isAmharic
                        ? 'ስለ ደረጃው አጭር መግለጫ'
                        : 'Brief description about this equb level',
                    icon: Icons.description_rounded,
                    maxLines: 3,
                  ),
                ]),
              ),

              const SizedBox(height: 14),

              // ── Financial ───────────────────────────────────────────────
              _SCard(
                icon: Icons.attach_money_rounded,
                title: isAmharic ? 'የፋይናንስ መቼቶች' : 'Financial Settings',
                color: _levelColor,
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: _FField(
                        ctrl: _priceCtl,
                        label: isAmharic ? 'ሳምንታዊ ክፍያ (ETB) *' : 'Weekly Entry Price (ETB) *',
                        hint: '5000',
                        icon: Icons.payments_rounded,
                        type: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return isAmharic ? 'ክፍያ ያስፈልጋል' : 'Price required';
                          }
                          final n = double.tryParse(v.trim());
                          if (n == null || n <= 0) {
                            return isAmharic ? 'ትክክለኛ ቁጥር ያስፈልጋል' : 'Enter valid amount > 0';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FField(
                        ctrl: _maxCtl,
                        label: isAmharic ? 'ከፍ. ተሳታፊዎች *' : 'Max Participants *',
                        hint: '100',
                        icon: Icons.group_rounded,
                        type: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return isAmharic ? 'ቁጥር ያስፈልጋል' : 'Required';
                          }
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 2) {
                            return isAmharic ? 'ቢያንስ 2 ተሳታፊዎች' : 'Min 2 participants';
                          }
                          if (n > 1000) {
                            return isAmharic ? 'ከፍ. 1000' : 'Max 1,000';
                          }
                          return null;
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Live prize preview
                  _PrizePreview(
                    priceText: _priceCtl.text,
                    maxText: _maxCtl.text,
                    level: _level,
                    levelColor: _levelColor,
                    isAmharic: isAmharic,
                  ),
                ]),
              ),

              const SizedBox(height: 14),

              // ── Schedule ────────────────────────────────────────────────
              _SCard(
                icon: Icons.calendar_month_rounded,
                title: isAmharic ? 'የዕጣ መርሐ ግብር' : 'Draw Schedule',
                color: _levelColor,
                child: DropdownButtonFormField<String>(
                  value: _schedule,
                  decoration: InputDecoration(
                    prefixIcon:
                        Icon(Icons.repeat_rounded, color: _levelColor),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text(isAmharic ? 'ሳምንታዊ (Weekly)' : 'Weekly — Every Sunday'),
                    ),
                    DropdownMenuItem(
                      value: 'bi-weekly',
                      child: Text(isAmharic ? 'ሁለት ሳምንት (Bi-Weekly)' : 'Bi-Weekly'),
                    ),
                    DropdownMenuItem(
                      value: 'monthly',
                      child: Text(isAmharic ? 'ወርሃዊ (Monthly)' : 'Monthly'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _schedule = v ?? 'weekly'),
                ),
              ),

              const SizedBox(height: 20),

              // ── Submit ──────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.add_circle_rounded,
                          color: Colors.white),
                  label: Text(
                    _submitting
                        ? (isAmharic ? 'እየተፈጠረ ነው…' : 'Creating…')
                        : (isAmharic ? 'እቁብ ፍጠር' : 'Create Equb Level'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _levelColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Level tile button
  Widget _LvlTile(String lvl, String label, Color c, String? amLabel) {
    final sel = _level == lvl;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _level = lvl;
            _applyLevelDefaults(lvl);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? c : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c, width: sel ? 2 : 1),
            boxShadow: sel
                ? [
                    BoxShadow(
                        color: c.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                amLabel ?? label,
                style: TextStyle(
                    color: sel ? Colors.white : c,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Prize preview widget ──────────────────────────────────────────────────────
class _PrizePreview extends StatelessWidget {
  final String priceText, maxText, level;
  final Color levelColor;
  final bool isAmharic;
  const _PrizePreview({
    required this.priceText,
    required this.maxText,
    required this.level,
    required this.levelColor,
    required this.isAmharic,
  });

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(priceText) ?? 0;
    final max = int.tryParse(maxText) ?? 0;
    final rate = level == 'high' ? 0.10 : level == 'medium' ? 0.07 : 0.05;
    final gross = price * max;
    final net = gross * (1 - rate);
    final fee = gross * rate;

    String fmt(double v) {
      if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M ETB';
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K ETB';
      return '${v.toStringAsFixed(0)} ETB';
    }

    if (price <= 0 || max <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: levelColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: levelColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isAmharic ? 'ጠቅ. ድምር:' : 'Total Pool:',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(fmt(gross),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isAmharic ? 'ጠቅ. ድል አበል:' : 'Net Prize:',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(fmt(net),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: levelColor)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  isAmharic
                      ? 'የአስተዳዳሪ ክፍያ (${(rate * 100).toInt()}%):'
                      : 'Admin Fee (${(rate * 100).toInt()}%):',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(fmt(fee),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared form helpers ───────────────────────────────────────────────────────
class _SCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Widget child;
  const _SCard(
      {required this.icon,
      required this.title,
      required this.color,
      required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _FField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final TextInputType? type;
  final List<TextInputFormatter>? formatters;
  final int maxLines;
  final String? Function(String?)? validator;

  const _FField({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.type,
    this.formatters,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 5),
          TextFormField(
            controller: ctrl,
            keyboardType: type,
            inputFormatters: formatters,
            maxLines: maxLines,
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 12),
            ),
          ),
        ],
      );
}
