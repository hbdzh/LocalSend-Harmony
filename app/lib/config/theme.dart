import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/dynamic_colors.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:yaru/yaru.dart' as yaru;

final _borderRadius = BorderRadius.circular(5);

ThemeData getTheme(ColorMode colorMode, Color customColor, Brightness brightness, DynamicColors? dynamicColors) {
  if (colorMode == ColorMode.yaru) {
    final theme = _getYaruTheme(brightness);
    return isHarmonyOS ? harmonyTheme(theme) : theme;
  }

  final colorScheme = _determineColorScheme(colorMode, customColor, brightness, dynamicColors);

  final lightInputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: colorScheme.secondaryContainer),
    borderRadius: _borderRadius,
  );

  final darkInputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: colorScheme.secondaryContainer),
    borderRadius: _borderRadius,
  );

  // https://github.com/localsend/localsend/issues/52
  final String? fontFamily;
  if (checkPlatform([TargetPlatform.windows])) {
    fontFamily = switch (LocaleSettings.currentLocale) {
      AppLocale.ja => 'Yu Gothic UI',
      AppLocale.ko => 'Malgun Gothic',
      AppLocale.zhCn => 'Microsoft YaHei UI',
      AppLocale.zhHk || AppLocale.zhTw => 'Microsoft JhengHei UI',
      _ => 'Segoe UI Variable Display',
    };
  } else if (checkPlatform([TargetPlatform.linux])) {
    fontFamily = switch (LocaleSettings.currentLocale) {
      AppLocale.ja => 'Noto Sans CJK JP',
      AppLocale.ko => 'Noto Sans CJK KR',
      AppLocale.zhCn => 'Noto Sans CJK SC',
      AppLocale.zhHk || AppLocale.zhTw => 'Noto Sans CJK TC',
      _ => 'Noto Sans',
    };
  } else {
    fontFamily = null;
  }

  final theme = ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    // same density on all platforms so desktop matches mobile (defaults to compact on desktop)
    visualDensity: VisualDensity.standard,
    navigationBarTheme: colorScheme.brightness == Brightness.dark
        ? NavigationBarThemeData(
            iconTheme: WidgetStateProperty.all(const IconThemeData(color: Colors.white)),
          )
        : null,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.secondaryContainer,
      border: colorScheme.brightness == Brightness.light ? lightInputBorder : darkInputBorder,
      focusedBorder: colorScheme.brightness == Brightness.light ? lightInputBorder : darkInputBorder,
      enabledBorder: colorScheme.brightness == Brightness.light ? lightInputBorder : darkInputBorder,
      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: colorScheme.brightness == Brightness.dark ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    fontFamily: fontFamily,
  );
  return isHarmonyOS ? harmonyTheme(theme) : theme;
}

/// Harmony-inspired surfaces, applied only on the OHOS build.
ThemeData harmonyTheme(ThemeData base) {
  final colors = base.colorScheme;
  final dark = colors.brightness == Brightness.dark;
  final background = dark ? (colors.surface == Colors.black ? Colors.black : const Color(0xFF101114)) : const Color(0xFFF2F4F7);
  final surface = dark ? const Color(0xFF23252A) : Colors.white;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
  final hover = colors.onSurface.withValues(alpha: dark ? 0.10 : 0.06);
  final muted = colors.onSurface.withValues(alpha: dark ? 0.26 : 0.20);
  final panel = dark ? const Color(0xFF303238) : const Color(0xFFF0F2F5);
  final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return colors.primary.withValues(alpha: 0.14);
    if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return hover;
    return null;
  });
  return base.copyWith(
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(color: surface, elevation: 0, shape: shape, clipBehavior: Clip.antiAlias),
    appBarTheme: AppBarTheme(backgroundColor: background, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 480),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: shape,
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      textStyle: base.textTheme.bodyLarge?.copyWith(color: colors.onSurface),
      position: PopupMenuPosition.under,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(shape),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: muted,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      selectedColor: colors.primary,
      selectedTileColor: colors.primary.withValues(alpha: dark ? 0.18 : 0.09),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minTileHeight: 48,
    ),
    dividerTheme: DividerThemeData(color: colors.onSurface.withValues(alpha: dark ? 0.12 : 0.08), thickness: 1, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? colors.onSurface.withValues(alpha: 0.38) : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return muted;
        return states.contains(WidgetState.selected) ? colors.primary : muted;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
      overlayColor: overlay,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return muted;
        return states.contains(WidgetState.selected) ? colors.primary : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(colors.onPrimary),
      overlayColor: overlay,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return muted;
        return states.contains(WidgetState.selected) ? colors.primary : colors.onSurfaceVariant;
      }),
      overlayColor: overlay,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: colors.primary,
      inactiveTrackColor: muted,
      thumbColor: colors.primary,
      overlayColor: colors.primary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? const Color(0xFFE5E5E9) : const Color(0xFF303238), borderRadius: BorderRadius.circular(12)),
      textStyle: TextStyle(color: dark ? Colors.black : Colors.white, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      waitDuration: const Duration(milliseconds: 500),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ).copyWith(overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        side: BorderSide(color: colors.primary.withValues(alpha: 0.36)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ).copyWith(overlayColor: overlay),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: colors.primary.withValues(alpha: dark ? 0.24 : 0.13),
      height: 72,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: colors.primary.withValues(alpha: dark ? 0.24 : 0.13),
      useIndicator: true,
      selectedIconTheme: IconThemeData(color: colors.primary),
      selectedLabelTextStyle: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: panel,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ).copyWith(overlayColor: overlay),
    ),
  );
}

Future<void> updateSystemOverlayStyle(BuildContext context) async {
  final brightness = Theme.of(context).brightness;
  await updateSystemOverlayStyleWithBrightness(brightness);
}

Future<void> updateSystemOverlayStyleWithBrightness(Brightness brightness) async {
  if (isHarmonyOS) {
    final dark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: dark ? const Color(0xFF101114) : const Color(0xFFF2F4F7),
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
    );
  } else if (checkPlatform([TargetPlatform.android])) {
    // See https://github.com/flutter/flutter/issues/90098
    final darkMode = brightness == Brightness.dark;
    final androidSdkInt = RefenaScope.defaultRef.read(deviceInfoProvider).androidSdkInt ?? 0;
    final bool edgeToEdge = androidSdkInt >= 29;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // ignore: unawaited_futures

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.light ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: edgeToEdge ? Colors.transparent : (darkMode ? Colors.black : Colors.white),
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: darkMode ? Brightness.light : Brightness.dark,
      ),
    );
  } else {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarBrightness: brightness, // iOS
        statusBarColor: Colors.transparent, // Not relevant to this issue
      ),
    );
  }
}

extension ThemeDataExt on ThemeData {
  /// This is the actual [cardColor] being used.
  Color get cardColorWithElevation {
    return ElevationOverlay.applySurfaceTint(cardColor, colorScheme.surfaceTint, 1);
  }
}

extension ColorSchemeExt on ColorScheme {
  Color get warning {
    return Colors.orange;
  }

  Color? get secondaryContainerIfDark {
    return brightness == Brightness.dark ? secondaryContainer : null;
  }

  Color? get onSecondaryContainerIfDark {
    return brightness == Brightness.dark ? onSecondaryContainer : null;
  }
}

extension InputDecorationThemeExt on InputDecorationThemeData {
  BorderRadius get borderRadius => border is OutlineInputBorder ? (border! as OutlineInputBorder).borderRadius : _borderRadius;
}

ColorScheme _determineColorScheme(ColorMode mode, Color customColor, Brightness brightness, DynamicColors? dynamicColors) {
  final defaultColorScheme = ColorScheme.fromSeed(
    seedColor: isHarmonyOS ? const Color(0xFF0A59F7) : Colors.teal,
    brightness: brightness,
  );

  final colorScheme = switch (mode) {
    ColorMode.system => brightness == Brightness.light ? dynamicColors?.light : dynamicColors?.dark,
    ColorMode.localsend => null,
    ColorMode.oled => (dynamicColors?.dark ?? defaultColorScheme).copyWith(
      surface: Colors.black,
    ),
    ColorMode.yaru => throw 'Should reach here',
    ColorMode.custom => ColorScheme.fromSeed(
      seedColor: customColor,
      brightness: brightness,
    ),
  };

  return colorScheme ?? defaultColorScheme;
}

ThemeData _getYaruTheme(Brightness brightness) {
  final baseTheme = brightness == Brightness.light ? yaru.yaruLight : yaru.yaruDark;
  final colorScheme = baseTheme.colorScheme;

  final lightInputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: colorScheme.secondaryContainer),
    borderRadius: _borderRadius,
  );

  final darkInputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: colorScheme.secondaryContainer),
    borderRadius: _borderRadius,
  );

  InputDecorationThemeData;

  return baseTheme.copyWith(
    // same density on all platforms so desktop matches mobile (defaults to compact on desktop)
    visualDensity: VisualDensity.standard,
    navigationBarTheme: colorScheme.brightness == Brightness.dark
        ? NavigationBarThemeData(
            iconTheme: WidgetStateProperty.all(const IconThemeData(color: Colors.white)),
          )
        : null,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.secondaryContainer,
      border: colorScheme.brightness == Brightness.light ? lightInputBorder : darkInputBorder,
      focusedBorder: colorScheme.brightness == Brightness.light ? lightInputBorder : darkInputBorder,
      enabledBorder: colorScheme.brightness == Brightness.light ? lightInputBorder : darkInputBorder,
      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: colorScheme.brightness == Brightness.dark ? Colors.white : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
  );
}
