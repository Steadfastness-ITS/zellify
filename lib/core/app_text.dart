import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One place to build every text style in the app.
///
/// To try a different font later, change `plusJakartaSans` below
/// (for example to `manrope` or `outfit`) and the whole app updates.
class AppText {
  AppText._();

  static TextStyle style(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}
