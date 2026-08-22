import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/smart_back_button.dart';

class SuperAdminCreateEqubScreen extends StatefulWidget {
  const SuperAdminCreateEqubScreen({super.key});

  @override
  State<SuperAdminCreateEqubScreen> createState() =>
      _SuperAdminCreateEqubScreenState();
}

class _SuperAdminCreateEqubScreenState
    extends State<SuperAdminCreateEqubScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _levelController = TextEditingController();
  final _priceController = TextEditingController();
  final _netPrizeController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _cycleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _loading = false;
  final bool _isAmharic = AppConstants.currentLanguage == 'am';

  String t(String en, String am) => _isAmharic ? am : en;

  @override
  void initState() {
    super.initState();
    _cycleController.text = _isAmharic ? 'በየሳምንቱ' : 'Weekly (Every Sunday)';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _levelController.dispose();
    _priceController.dispose();
    _netPrizeController.dispose();
    _maxParticipantsController.dispose();
    _cycleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final payload = {
      'name': _nameController.text.trim(),
      'level': _levelController.text.trim().toLowerCase().replaceAll(' ', '_'),
      'price': double.tryParse(_priceController.text.trim()) ?? 5000.0,
      'netPrize': double.tryParse(_netPrizeController.text.trim()) ?? 450000.0,
      'maxParticipants':
          (int.tryParse(_maxParticipantsController.text.trim()) ?? 100)
              .clamp(100, 100000),
      'cycle': _cycleController.text.trim(),
      'description': _descriptionController.text.trim(),
    };

    final res = await ApiService.createEqubLevel(payload);

    if (!mounted) return;
    setState(() => _loading = false);

    if (res.containsKey('error')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error'] ??
              t('Error creating Equb level', 'እቁብ ደረጃ በመፍጠር ላይ ስህተት ተከሰተ')),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Equb level registered successfully!',
              'አዲስ የእቁብ ደረጃ በጥሩ ሁኔታ ተመዝግቧል!')),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('Register New Equb Level', 'አዲስ የእቁብ ደረጃ መመዝገቢያ')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: const SmartBackButton(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryDark, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_business,
                          color: Colors.white, size: 36),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('Create Equb Level Table',
                                  'አዲስ የእቁብ ደረጃ ሰንጠረዥ ይፍጠሩ'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                            Text(
                              t('Registered levels automatically display on home page',
                                  'የተመዘገቡ ደረጃዎች በሆም ገጽ ላይ ወዲያው ይታያሉ'),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Name
                Text(t('Equb Level Name', 'የእቁብ ደረጃ ስም'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: t('e.g. VIP Business Equb', 'ምሳሌ፡ ቪአይፒ የንግድ እቁብ'),
                    prefixIcon: const Icon(Icons.label),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? t('Enter Equb level name', 'እባክዎን የእቁብ ደረጃ ስም ያስገቡ')
                      : null,
                ),
                const SizedBox(height: 16),

                // Level Key
                Text(t('Level Code / Key', 'የደረጃ መለያ ኮድ'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _levelController,
                  decoration: InputDecoration(
                    hintText:
                        t('e.g. vip, platinum, custom', 'ምሳሌ፡ vip, platinum'),
                    prefixIcon: const Icon(Icons.code),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? t('Enter level code', 'እባክዎን የደረጃ ኮድ ያስገቡ')
                      : null,
                ),
                const SizedBox(height: 16),

                // Price & Prize Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Price (ETB)', 'የክፍያ መጠን'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '5000',
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                            validator: (v) {
                              final price = double.tryParse(v?.trim() ?? '');
                              return price == null || price <= 0
                                  ? t('Enter valid price', 'ትክክለኛ የክፍያ መጠን ያስገቡ')
                                  : null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Net Prize (ETB)', 'የአሸናፊ ክፍያ'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _netPrizeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '465000',
                              prefixIcon: Icon(Icons.emoji_events),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? t('Required', 'ያስፈልጋል')
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Max Participants & Cycle
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Max Members', 'ከፍተኛ የተሳታፊ ብዛት'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _maxParticipantsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '1000',
                              prefixIcon: Icon(Icons.group),
                            ),
                            validator: (v) {
                              final count = int.tryParse(v?.trim() ?? '');
                              return count == null || count < 10
                                  ? t('Enter at least 10 members', 'ቢያንስ 10 ተሳታፊዎች ያስገቡ')
                                  : null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Cycle Schedule', 'የክፍያ ዑደት'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _cycleController,
                            decoration: const InputDecoration(
                              hintText: 'Weekly',
                              prefixIcon: Icon(Icons.calendar_month),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Description
                Text(t('Description', 'ዝርዝር መግለጫ'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: t('Brief description of this Equb level rules',
                        'ስለዚህ የእቁብ ደረጃ አጭር መግለጫና ደንቦች'),
                    prefixIcon: const Icon(Icons.description),
                  ),
                ),
                const SizedBox(height: 28),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _loading
                          ? t('Registering...', 'በመመዝገብ ላይ...')
                          : t('Register Equb Level', 'የእቁብ ደረጃ መዝግብ'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
