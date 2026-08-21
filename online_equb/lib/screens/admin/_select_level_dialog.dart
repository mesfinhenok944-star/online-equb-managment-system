import 'package:flutter/material.dart';

class SelectLevelDialog extends StatelessWidget {
  const SelectLevelDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Select EQUB Level'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'low'),
          child: const Text('Low Level'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'medium'),
          child: const Text('Medium Level'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'high'),
          child: const Text('High Level'),
        ),
      ],
    );
  }
}
