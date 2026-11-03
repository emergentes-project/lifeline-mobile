import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum SystemStatusMode { offline, connected }

class SystemStatusBar extends StatelessWidget implements PreferredSizeWidget {
  const SystemStatusBar({
    super.key,
    this.mode = SystemStatusMode.offline,
    this.customText,
  });

  final SystemStatusMode mode;
  final String? customText;

  @override
  Size get preferredSize => const Size.fromHeight(28);

  @override
  Widget build(BuildContext context) {
    final isOffline = mode == SystemStatusMode.offline;
    final dotColor = isOffline ? AppTheme.amber : AppTheme.cyan;
    final text = customText ??
        (isOffline
            ? 'Modo Offline · IA local activa'
            : 'Conectado · Sincronizando con la nube');

    return Container(
      width: double.infinity,
      color: AppTheme.teal.withValues(alpha: 0.94),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: AppTheme.fontHeading,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
