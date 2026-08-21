import 'package:flutter/material.dart';
import '../../widgets/smart_back_button.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/firestore_service.dart';

class CreateEqubScreen extends StatefulWidget {
  const CreateEqubScreen({super.key});

  @override
  State<CreateEqubScreen> createState() => _CreateEqubScreenState();
}

class _CreateEqubScreenState extends State<CreateEqubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _durationCtl = TextEditingController();
  final _maxCtl = TextEditingController();
  final _descCtl = TextEditingController();
  String _level = 'low';
  String _schedule = 'monthly';
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _priceCtl.dispose();
    _durationCtl.dispose();
    _maxCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final data = {
      'name': _nameCtl.text.trim(),
      'level': _level,
      'price': double.tryParse(_priceCtl.text) ?? 0,
      'durationMonths': int.tryParse(_durationCtl.text) ?? 1,
      'maxParticipants': int.tryParse(_maxCtl.text) ?? 100,
      'description': _descCtl.text.trim(),
      'paymentSchedule': _schedule,
      'status': 'pending',
    };

    try {
      final id = await FirestoreService.createEqub(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Equb created'), backgroundColor: AppColors.success));
      context.go('/equbs/${id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create equb'), backgroundColor: AppColors.error));
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Equb'),
        leading: const SmartBackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(
              controller: _nameCtl,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _level,
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => setState(() => _level = v ?? 'low'),
                  decoration: const InputDecoration(labelText: 'Level'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _schedule,
                  items: const [
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  ],
                  onChanged: (v) => setState(() => _schedule = v ?? 'monthly'),
                  decoration: const InputDecoration(labelText: 'Schedule'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtl,
              decoration: const InputDecoration(labelText: 'Entry Price (ETB)'),
              keyboardType: TextInputType.number,
              validator: (v) => (double.tryParse(v ?? '') == null) ? 'Enter a number' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _durationCtl,
                  decoration: const InputDecoration(labelText: 'Duration (months)'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter months' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _maxCtl,
                  decoration: const InputDecoration(labelText: 'Max participants'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a number' : null,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 4,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Create Equb'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
