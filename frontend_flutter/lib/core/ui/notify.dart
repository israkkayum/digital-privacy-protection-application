import 'package:flutter/material.dart';

class Notify {
  static void success(BuildContext context, String msg) {
    _show(context, msg, const Color(0xFF16A34A), Icons.check_circle_rounded);
  }

  static void error(BuildContext context, String msg) {
    _show(context, msg, const Color(0xFFDC2626), Icons.error_rounded);
  }

  static void info(BuildContext context, String msg) {
    _show(context, msg, const Color(0xFF1D4ED8), Icons.info_rounded);
  }

  static void _show(
    BuildContext context,
    String msg,
    Color color,
    IconData icon,
  ) {
    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
