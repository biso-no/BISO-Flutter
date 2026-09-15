import 'package:flutter/material.dart';

class AppColors {
  // === BI BRAND COLORS (Foundation) ===
  static const Color biNavy = Color(0xFF001731); // Your brand dark navy
  static const Color biLightBlue = Color(0xFF3DA9E0); // Your brand light blue

  // === WONDEROUS-INSPIRED PREMIUM PALETTE ===
  // Deep Navy Spectrum (Wonderous dark theme inspired)
  static const Color deepNavy = Color(
    0xFF000B1A,
  ); // Deepest for immersive backgrounds
  static const Color richNavy = Color(0xFF001731); // Your brand navy
  static const Color midNavy = Color(0xFF002A4A); // Between navy and medium
  static const Color blueStone = Color(0xFF1B4B73); // Rich blue-gray
  static const Color steelBlue = Color(0xFF2B7DB8); // Bridge to light blue

  // Light Blue Spectrum (Premium tints)
  static const Color crystalBlue = Color(0xFF3DA9E0); // Your brand light blue
  static const Color skyBlue = Color(0xFF7BC8E8); // Lighter, more ethereal
  static const Color mistBlue = Color(0xFFB5DBF0); // Soft, cloud-like
  static const Color iceBlue = Color(0xFFE8F4FB); // Nearly white, premium touch

  // Sophisticated Gradients (Wonderous-style rich colors)
  static const Color deepAmber = Color(0xFF8B4513); // Rich brown-gold
  static const Color warmGold = Color(0xFFF7D64A); // Existing gold
  static const Color sunGold = Color(0xFFFFE98C); // Light gold

  // Premium Accent Colors (Campus theming)
  static const Color forestGreen = Color(0xFF1A5F3F); // Deep, rich green
  static const Color emeraldGreen = Color(0xFF2E8B57); // Sophisticated green
  static const Color royalPurple = Color(0xFF4B0082); // Deep, luxurious purple
  static const Color amethystPurple = Color(0xFF7B68EE); // Lighter purple
  static const Color burnishedOrange = Color(0xFFCC5500); // Rich, warm orange
  static const Color copperOrange = Color(0xFFFF7F50); // Lighter orange

  // Sophisticated Neutrals (Wonderous-inspired)
  static const Color charcoalBlack = Color(
    0xFF1A1A1A,
  ); // Rich black like Wonderous
  static const Color smokeGray = Color(0xFF2C2C2C); // Softer dark
  static const Color stoneGray = Color(0xFF4A5568); // Blue-tinted gray
  static const Color mist = Color(0xFF8A9BA8); // Light blue-gray
  static const Color cloud = Color(0xFFE2E8F0); // Premium light gray
  static const Color pearl = Color(0xFFF7FAFC); // Off-white with warmth

  // Legacy Colors (for compatibility)
  static const Color strongBlue = richNavy;
  static const Color defaultBlue = crystalBlue;
  static const Color accentBlue = skyBlue;
  static const Color subtleBlue = iceBlue;

  static const Color strongGold = deepAmber;
  static const Color defaultGold = warmGold;
  static const Color accentGold = sunGold;

  // Extended Blue Spectrum (Legacy - now premium aligned)
  static const Color blue1 = pearl;
  static const Color blue6 = steelBlue;
  static const Color blue8 = midNavy;
  static const Color blue9 = richNavy;

  // Green Spectrum (Premium forest tones)
  static const Color green1 = Color(0xFFFBFEFC);
  static const Color green6 = Color(0xFF95DEAA);
  static const Color green8 = Color(0xFF30B85B);
  static const Color green9 = emeraldGreen;

  // Purple Spectrum (Royal sophistication)
  static const Color purple9 = amethystPurple;

  // Orange Spectrum (Warm copper tones)
  static const Color orange9 = burnishedOrange;

  // Neutral Colors (Premium sophistication)
  static const Color white = Color(0xFFFFFFFF);
  static const Color gray50 = pearl;
  static const Color gray100 = cloud;
  static const Color gray200 = Color(0xFFE2E8F0);
  static const Color gray300 = mist;
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = stoneGray;
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = smokeGray;
  static const Color gray900 = charcoalBlack;
  static const Color black = Color(0xFF000000);

  // Semantic Colors
  static const Color success = green9;
  static const Color warning = orange9;
  static const Color error = Color(0xFFDC2626);
  static const Color info = accentBlue;

  // Background Colors (Wonderous-inspired theming)
  static const Color background = white;
  static const Color backgroundDark =
      charcoalBlack; // Deep immersive background
  static const Color surface = pearl;
  static const Color surfaceDark = smokeGray;
  static const Color surfaceVariant = cloud;
  static const Color surfaceVariantDark = stoneGray;

  // Text Colors (Premium readability)
  static const Color onBackground = charcoalBlack;
  static const Color onBackgroundDark = pearl;
  static const Color onSurface = smokeGray;
  static const Color onSurfaceDark = cloud;
  static const Color onSurfaceVariant = stoneGray;
  static const Color onSurfaceVariantDark = mist;

  // Border Colors (Subtle sophistication)
  static const Color outline = mist;
  static const Color outlineDark = stoneGray;
  static const Color outlineVariant = cloud;
  static const Color outlineVariantDark = smokeGray;

  // === WONDEROUS-INSPIRED GRADIENT COLLECTIONS ===
  // Campus Gradient Sets (for immersive backgrounds)
  static const List<Color> osloGradient = [
    deepNavy,
    richNavy,
    blueStone,
    crystalBlue,
  ];
  static const List<Color> bergenGradient = [
    forestGreen,
    emeraldGreen,
    Color(0xFF2E8B7F),
    Color(0xFF7FDBDA),
  ];
  static const List<Color> trondheimGradient = [
    royalPurple,
    amethystPurple,
    Color(0xFF9370DB),
    Color(0xFFE6E6FA),
  ];
  static const List<Color> stavangerGradient = [
    burnishedOrange,
    copperOrange,
    Color(0xFFFF8C69),
    Color(0xFFFFE4B5),
  ];

  // Story Card Gradients (for content cards)
  static const List<Color> eventGradient = [crystalBlue, skyBlue];
  static const List<Color> marketplaceGradient = [
    emeraldGreen,
    Color(0xFF48BB78),
  ];
  static const List<Color> jobsGradient = [amethystPurple, Color(0xFFB794F6)];
  static const List<Color> expenseGradient = [copperOrange, Color(0xFFFBB970)];

  // Premium Shadow Colors (for depth)
  static const Color shadowLight = Color(0x0F000000); // 6% opacity
  static const Color shadowMedium = Color(0x1A000000); // 10% opacity
  static const Color shadowHeavy = Color(0x33000000); // 20% opacity

  // Premium Overlay Colors (for sophisticated layering)
  static const Color overlayLight = Color(0x0A000000); // 4% black
  static const Color overlayMedium = Color(0x1F000000); // 12% black
  static const Color overlayHeavy = Color(0x66000000); // 40% black

  // Third-party brand colors
  static const Color vippsPurple = Color(0xFF6D3EFF);
}
