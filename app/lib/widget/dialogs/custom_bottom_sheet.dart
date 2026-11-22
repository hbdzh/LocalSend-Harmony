import 'package:flutter/material.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:routerino/routerino.dart';

class CustomBottomSheet extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;
  const CustomBottomSheet({
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RouterinoBottomSheet(
      title: title,
      description: description,
      backgroundColor: isHarmonyOS
          ? (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface)
          : Theme.of(context).scaffoldBackgroundColor,
      borderRadius: isHarmonyOS ? 28 : 20,
      child: child,
    );
  }
}
