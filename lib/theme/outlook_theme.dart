import 'package:flutter/material.dart';

/// Outlook 2013-inspired theme for Look In.
///
/// Outlook 2013 used a flat, Metro-influenced design with a blue accent,
/// white ribbon area, light gray navigation pane, and clean typography.
class OutlookTheme {
  OutlookTheme._();

  // ─── Brand Colors ──────────────────────────────────────────────────
  static const Color primaryBlue = Color(0xFF2B579A);
  static const Color darkBlue = Color(0xFF1E3F73);
  static const Color lightBlue = Color(0xFF0072C6);
  static const Color accentBlue = Color(0xFF2A8DD4);

  // ─── Surface Colors ────────────────────────────────────────────────
  static const Color ribbonBackground = Color(0xFFF3F3F3);
  static const Color ribbonTabActive = Colors.white;
  static const Color ribbonTabInactive = Color(0xFFE8E8E8);
  static const Color folderPaneBackground = Color(0xFFF6F6F6);
  static const Color messageListBackground = Colors.white;
  static const Color readingPaneBackground = Colors.white;
  static const Color statusBarBackground = Color(0xFF2B579A);
  static const Color dividerColor = Color(0xFFD4D4D4);
  static const Color hoverColor = Color(0xFFE5F1FB);

  // ─── Selection Colors ──────────────────────────────────────────────
  static const Color selectedItemBackground = Color(0xFFCDE1F9);
  static const Color selectedItemBorder = Color(0xFF7ABAED);
  static const Color unreadIndicator = Color(0xFF2B579A);

  // ─── Text Colors ───────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF333333);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textMuted = Color(0xFF999999);
  static const Color textOnPrimary = Colors.white;
  static const Color textLink = Color(0xFF0072C6);

  // ─── Navigation Bar Colors ─────────────────────────────────────────
  static const Color navBarBackground = Color(0xFFEDEDED);
  static const Color navBarActiveBackground = Color(0xFF2B579A);
  static const Color navBarActiveText = Colors.white;
  static const Color navBarInactiveText = Color(0xFF444444);

  // ─── Message Colors ────────────────────────────────────────────────
  static const Color unreadMessageBackground = Colors.white;
  static const Color readMessageBackground = Color(0xFFF9F9F9);
  static const Color flaggedColor = Color(0xFFE81123);
  static const Color draftColor = Color(0xFFD83B01);

  // ─── Calendar Colors ───────────────────────────────────────────────
  static const Color calendarToday = Color(0xFF2B579A);
  static const Color calendarSelected = Color(0xFFCDE1F9);
  static const Color calendarEventDefault = Color(0xFF2B579A);
  static const Color calendarEventGreen = Color(0xFF107C10);
  static const Color calendarEventRed = Color(0xFFE81123);
  static const Color calendarEventOrange = Color(0xFFD83B01);
  static const Color calendarEventPurple = Color(0xFF5C2D91);

  // ─── Sizes ─────────────────────────────────────────────────────────
  static const double ribbonHeight = 110.0;
  static const double ribbonTabHeight = 28.0;
  static const double statusBarHeight = 24.0;
  static const double folderPaneWidth = 220.0;
  static const double messageListWidth = 320.0;
  static const double navigationBarHeight = 36.0;
  static const double sidebarIconSize = 18.0;

  // ─── Text Styles ───────────────────────────────────────────────────
  static const String fontFamily = 'Segoe UI';
  // Fallback fonts for Linux where Segoe UI isn't available
  static const List<String> fontFamilyFallback = [
    'Noto Sans',
    'Ubuntu',
    'Cantarell',
    'Liberation Sans',
    'Arial',
    'sans-serif',
  ];

  static const TextStyle titleBarStyle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textOnPrimary,
    letterSpacing: 0.5,
  );

  static const TextStyle ribbonTabStyle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle ribbonTabActiveStyle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: primaryBlue,
  );

  static const TextStyle ribbonButtonLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle ribbonGroupLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  static const TextStyle folderLabelStyle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle folderLabelBoldStyle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle messageSubjectUnread = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle messageSubjectRead = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle messageSenderUnread = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle messageSenderRead = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle messagePreview = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  static const TextStyle messageDate = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  static const TextStyle readingPaneSubject = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20,
    fontWeight: FontWeight.w300,
    color: textPrimary,
  );

  static const TextStyle readingPaneSender = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle readingPaneRecipient = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle statusBarStyle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textOnPrimary,
  );

  // ─── Flutter ThemeData ─────────────────────────────────────────────
  static ThemeData get themeData => ThemeData(
        useMaterial3: false,
        fontFamily: fontFamily,
        primaryColor: primaryBlue,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: primaryBlue,
          secondary: lightBlue,
          surface: Colors.white,
          onPrimary: textOnPrimary,
          onSecondary: textOnPrimary,
          onSurface: textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryBlue,
          foregroundColor: textOnPrimary,
          elevation: 0,
          titleTextStyle: titleBarStyle,
        ),
        dividerTheme: const DividerThemeData(
          color: dividerColor,
          thickness: 1,
          space: 1,
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            const Color(0xFFBBBBBB),
          ),
          thickness: WidgetStateProperty.all(6.0),
          radius: const Radius.circular(3),
        ),
        tooltipTheme: const TooltipThemeData(
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            fontSize: 12,
            color: textPrimary,
          ),
          decoration: BoxDecoration(
            color: Color(0xFFF1F1F1),
            border: Border.fromBorderSide(
              BorderSide(color: dividerColor),
            ),
          ),
          waitDuration: Duration(milliseconds: 500),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: textOnPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
            textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: textPrimary,
            side: const BorderSide(color: dividerColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
            textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: dividerColor),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: lightBlue, width: 2),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
        dialogTheme: const DialogTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
      );

  // ─── Decoration Helpers ────────────────────────────────────────────
  static BoxDecoration get ribbonDecoration => const BoxDecoration(
        color: ribbonBackground,
        border: Border(
          bottom: BorderSide(color: dividerColor),
        ),
      );

  static BoxDecoration get folderPaneDecoration => const BoxDecoration(
        color: folderPaneBackground,
        border: Border(
          right: BorderSide(color: dividerColor),
        ),
      );

  static BoxDecoration get messageListDecoration => const BoxDecoration(
        color: messageListBackground,
        border: Border(
          right: BorderSide(color: dividerColor),
        ),
      );

  static BoxDecoration selectedItemDecoration({bool hasBorder = true}) =>
      BoxDecoration(
        color: selectedItemBackground,
        border: hasBorder
            ? Border.all(color: selectedItemBorder, width: 1)
            : null,
      );

  static BoxDecoration get statusBarDecoration => const BoxDecoration(
        color: statusBarBackground,
      );
}
