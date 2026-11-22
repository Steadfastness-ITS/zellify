import 'package:flutter/material.dart';

/// Every colour used in Zellify lives here, so you change a colour in ONE place.
class AppColors {
  AppColors._(); // stops anyone from creating an AppColors object

  // Page and surfaces
  static const Color pageBg = Color(0xFFF4F6F3);
  static const Color white = Color(0xFFFFFFFF);

  // Text
  static const Color ink = Color(0xFF1B1F2E);
  static const Color textMuted = Color(0xFF9AA0AB);
  static const Color textLabel = Color(0xFF5B6270);

  // Brand greens
  static const Color green = Color(0xFF1F9E73);
  static const Color greenDark = Color(0xFF0F3D33);
  static const Color mint = Color(0xFFB9F0E0);
  static const Color mintLight = Color(0xFF7FE3C0);

  // Header gradient (top-left -> bottom-right)
  static const Color headerStart = Color(0xFF152623);
  static const Color headerMid = Color(0xFF173B33);
  static const Color headerEnd = Color(0xFF16624E);

  // See-through white layers used on the dark header
  static const Color glass = Color(0x1AFFFFFF); // 10% white
  static const Color glassSoft = Color(0x14FFFFFF); // 8% white
  static const Color glassBorder = Color(0x1FFFFFFF); // 12% white
  static const Color onDarkMuted = Color(0xB3FFFFFF); // 70% white

  // Quick-action and transaction tiles (background / icon colour)
  static const Color tileMint = Color(0xFFDAF3EA);
  static const Color iconMint = Color(0xFF2E9E7C);
  static const Color tileLavender = Color(0xFFE9E3F8);
  static const Color iconLavender = Color(0xFF7C62C4);
  static const Color tileAmber = Color(0xFFFCEBCB);
  static const Color iconAmber = Color(0xFFF29A1F);
  static const Color tileBlue = Color(0xFFDCEAFA);
  static const Color iconBlue = Color(0xFF4A86D6);
  static const Color tilePink = Color(0xFFFBDDE4);
  static const Color iconPink = Color(0xFFE0576F);
  static const Color tileGrey = Color(0xFFE8EAEA);
  static const Color iconGrey = Color(0xFF5C6364);

  // Promo banner
  static const Color promoBg = Color(0xFFE4DAF5);
  static const Color promoCircle = Color(0xFFD8C9F0);
  static const Color promoPurple = Color(0xFF6F52B8);
  static const Color promoSub = Color(0xFF8E86A6);

  // Small details
  static const Color divider = Color(0xFFF1F3F2);
  static const Color notificationDot = Color(0xFFF5A524);
  static const Color navInactive = Color(0xFFA0A6B1);
}
