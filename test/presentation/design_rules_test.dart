import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files already moved onto the BISO design system. Each migration task adds
/// its files here, and from then on the rules below hold for them.
const migratedFiles = <String>[
  'lib/core/theme/biso_page.dart',
  'lib/core/theme/biso_page_header.dart',
  'lib/presentation/widgets/biso/biso_bottom_bar.dart',
  'lib/presentation/widgets/biso/biso_form.dart',
  'lib/presentation/widgets/biso/biso_icon_tile.dart',
  'lib/presentation/widgets/biso/biso_list.dart',
  'lib/presentation/widgets/biso/biso_states.dart',
  'lib/presentation/screens/home/premium_home_screen.dart',
  'lib/presentation/widgets/dynamic_hero_carousel.dart',
  'lib/presentation/widgets/home/discovery_sections.dart',
  'lib/presentation/screens/explore/explore_screen.dart',
  'lib/presentation/screens/explore/events_screen.dart',
  'lib/presentation/screens/profile/profile_screen.dart',
  'lib/presentation/screens/explore/units_overview_screen.dart',
  'lib/presentation/screens/explore/unit_detail_screen.dart',
  'lib/presentation/screens/explore/jobs_screen.dart',
  'lib/presentation/screens/explore/departures_screen.dart',
  'lib/presentation/screens/explore/marketplace_screen.dart',
  'lib/presentation/screens/notifications/notifications_screen.dart',
  'lib/presentation/screens/notifications/announcement_detail_screen.dart',
  'lib/presentation/screens/explore/product_detail_screen.dart',
  'lib/presentation/screens/explore/campus_detail_screen.dart',
  'lib/presentation/screens/explore/campus_detail_components.dart',
  'lib/presentation/widgets/campus/campus_leadership_section.dart',
  'lib/presentation/screens/explore/webshop_product_detail_screen.dart',
  'lib/presentation/screens/shop/cart_screen.dart',
  'lib/presentation/screens/shop/checkout_screen.dart',
  'lib/presentation/screens/shop/orders_screen.dart',
  'lib/presentation/screens/shop/order_screen.dart',
  'lib/presentation/screens/explore/sell_product_screen.dart',
  'lib/presentation/screens/explore/expenses_screen.dart',
  'lib/presentation/screens/expense/create_expense_screen.dart',
  'lib/presentation/screens/profile/payment_information_screen.dart',
  'lib/presentation/screens/profile/edit_profile_screen.dart',
  'lib/presentation/screens/profile/settings_screen.dart',
  'lib/presentation/screens/profile/settings_screen_chat_tab.dart',
  'lib/presentation/widgets/premium/notification_tile.dart',
  'lib/presentation/screens/chat/chat_conversation_screen.dart',
  'lib/presentation/screens/chat/chat_info_screen.dart',
  'lib/presentation/screens/chat/user_picker_screen.dart',
  'lib/presentation/screens/ai_chat/ai_chat_screen.dart',
  'lib/presentation/widgets/ai_chat/ai_message_bubble.dart',
  'lib/presentation/widgets/ai_chat/chat_input_field.dart',
  'lib/presentation/widgets/ai_chat/typing_indicator.dart',
  'lib/presentation/widgets/ai_chat/user_message_bubble.dart',
  'lib/presentation/widgets/ai_chat/markdown_text.dart',
  'lib/presentation/screens/events/large_event_screen.dart',
  'lib/presentation/screens/auth/login_screen.dart',
  'lib/presentation/screens/auth/otp_verification_screen.dart',
  'lib/presentation/screens/auth/magic_link_verify_screen.dart',
  'lib/presentation/screens/onboarding/onboarding_screen.dart',
  'lib/presentation/screens/validator/controller_mode_screen.dart',
];

final _lineRules = <String, RegExp>{
  'Material Icons (use CupertinoIcons or add // biso:allow)': RegExp(
    r'(?<![A-Za-z])Icons\.',
  ),
  'off-brand AppColors (use BisoAccent or BisoPalette)': RegExp(
    r'AppColors\.(orange|green|purple|pink|red|yellow|emerald|forest|royal|amethyst|burnished|copper|warmGold|sunGold|deepAmber|strongGold|defaultGold|accentGold|success|warning|error|info)',
  ),
  'brightness color branch (use BisoPalette)': RegExp(r'isDark\s*\?'),
  'manual navigation clearance (BisoPage owns it)': RegExp(
    r'BisoNavigationInset\.',
  ),
};

/// Finds Museo styles (display*, headlineLarge, headlineMedium) given any
/// weight other than 300 inside their copyWith call.
List<String> museoWeightViolations(String source) {
  final start = RegExp(
    r'\b(displayLarge|displayMedium|displaySmall|headlineLarge|headlineMedium)\b\??\.copyWith\(',
  );
  final problems = <String>[];
  for (final match in start.allMatches(source)) {
    var depth = 1;
    var i = match.end;
    while (i < source.length && depth > 0) {
      final char = source[i];
      if (char == '(') depth++;
      if (char == ')') depth--;
      i++;
    }
    final args = source.substring(match.end, i - 1);
    final weight = RegExp(r'fontWeight:\s*FontWeight\.(\w+)').firstMatch(args);
    if (weight != null && weight.group(1) != 'w300') {
      problems.add('${match.group(1)} with FontWeight.${weight.group(1)}');
    }
  }
  return problems;
}

void main() {
  test('Museo weight scan catches bold large type only', () {
    expect(
      museoWeightViolations(
        't.headlineLarge?.copyWith(color: c.withValues(alpha: 0.5), fontWeight: FontWeight.bold)',
      ),
      isNotEmpty,
    );
    expect(
      museoWeightViolations(
        't.headlineLarge?.copyWith(fontWeight: FontWeight.w300)',
      ),
      isEmpty,
    );
    expect(
      museoWeightViolations(
        't.headlineSmall?.copyWith(fontWeight: FontWeight.bold)',
      ),
      isEmpty,
    );
  });

  for (final path in migratedFiles) {
    test('$path follows the BISO design rules', () {
      final lines = File(path).readAsLinesSync();
      final problems = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('biso:allow')) continue;
        for (final rule in _lineRules.entries) {
          // The page scaffold itself is what owns navigation clearance.
          if (rule.key.startsWith('manual navigation') &&
              path.startsWith('lib/core/')) {
            continue;
          }
          if (rule.value.hasMatch(lines[i])) {
            problems.add('${i + 1}: ${rule.key}: ${lines[i].trim()}');
          }
        }
      }
      problems.addAll(museoWeightViolations(lines.join('\n')));
      expect(problems, isEmpty);
    });
  }
}
