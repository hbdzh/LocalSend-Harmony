import 'package:flutter/material.dart';

/// Shared page heading for the HarmonyOS tabs.
class HarmonyPageHeading extends StatelessWidget {
  final String title;
  const HarmonyPageHeading({required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// Keeps the label readable even in narrow windows or with enlarged system text.
class HarmonySettingRow extends StatelessWidget {
  final String label;
  final String? description;
  final Widget child;
  const HarmonySettingRow({required this.label, required this.child, this.description, super.key});

  @override
  Widget build(BuildContext context) {
    final labelWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        if (description != null)
          Text(description!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 320 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelWidget,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: child),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 16),
              SizedBox(width: 150, child: child),
            ],
          );
        },
      ),
    );
  }
}

/// A section title and actions that can wrap independently in narrow windows.
class HarmonySectionToolbar extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const HarmonySectionToolbar({required this.title, required this.actions, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleWidget = Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600));
          final actionRow = Wrap(alignment: WrapAlignment.end, spacing: 0, children: actions);
          if (constraints.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget,
                Align(alignment: Alignment.centerRight, child: actionRow),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleWidget),
              actionRow,
            ],
          );
        },
      ),
    );
  }
}
