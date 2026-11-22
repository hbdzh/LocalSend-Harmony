import 'package:flutter/material.dart';

class SizingInformation {
  final bool isMobile;
  final bool isTabletOrDesktop;
  final bool isDesktop;

  /// Use bottom navigation in narrow or short windows, including PC split view.
  final bool useBottomNavigation;

  const SizingInformation(double width, [double height = double.infinity])
    : isMobile = width < 700,
      isTabletOrDesktop = width >= 700,
      isDesktop = width >= 800,
      useBottomNavigation = width < 700 || height < 400;
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(SizingInformation sizingInformation) builder;

  const ResponsiveBuilder({required this.builder});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return builder(SizingInformation(size.width, size.height));
  }
}
