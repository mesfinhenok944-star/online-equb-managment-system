import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SmartBackButton extends StatelessWidget {
  final Color? color;
  const SmartBackButton({Key? key, this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: color),
      onPressed: () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          // If no back available, navigate to home
          context.go('/home');
        }
      },
    );
  }
}
