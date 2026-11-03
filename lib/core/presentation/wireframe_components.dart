import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The logo container as seen in Wireframe A-01
class LifelineLogoBadge extends StatelessWidget {
  const LifelineLogoBadge({super.key, this.size = 80});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.teal, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.teal.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.health_and_safety_rounded,
                size: size * 0.45,
                color: AppTheme.teal,
              ),
              const SizedBox(height: 2),
              Text(
                'LOGO',
                style: TextStyle(
                  fontFamily: AppTheme.fontHeading,
                  fontSize: size * 0.13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.teal,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Priority Pill Chip as seen in Wireframe C-04, M-01, M-02
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.label, this.priorityLevel});

  final String label;
  final String? priorityLevel; // 'HIGH', 'MEDIUM', 'LOW'

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    final normalized = (priorityLevel ?? label).toUpperCase();
    if (normalized.contains('HIGH') || normalized.contains('ALTA')) {
      bg = AppTheme.redSoft;
      fg = AppTheme.redDark;
      border = const Color(0xFFFECACA);
    } else if (normalized.contains('MEDIUM') || normalized.contains('MEDIA')) {
      bg = AppTheme.amberSoft;
      fg = AppTheme.amberDark;
      border = const Color(0xFFFDE68A);
    } else {
      bg = AppTheme.cyanSoft;
      fg = AppTheme.cyanDark;
      border = const Color(0xFFBAE6FD);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontHeading,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Status Pill Badge for cases, outbox, and urgent markers
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.isUrgent = false,
    this.isOutlined = false,
    this.customBg,
    this.customFg,
  });

  final String label;
  final bool isUrgent;
  final bool isOutlined;
  final Color? customBg;
  final Color? customFg;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    if (customBg != null && customFg != null) {
      bg = customBg!;
      fg = customFg!;
      border = customFg!.withValues(alpha: 0.3);
    } else if (isUrgent ||
        label.contains('Apoyo urgente') ||
        label.contains('Apoyo solicitado') ||
        label.contains('urgente')) {
      bg = AppTheme.redSoft;
      fg = AppTheme.emergency;
      border = const Color(0xFFFECACA);
    } else if (label.contains('Disponible')) {
      bg = AppTheme.cyanSoft;
      fg = AppTheme.cyanDark;
      border = const Color(0xFFBAE6FD);
    } else if (label.contains('Asignado') ||
        label.contains('Por sincronizar') ||
        label.contains('Enviando')) {
      bg = AppTheme.amberSoft;
      fg = AppTheme.amberDark;
      border = const Color(0xFFFDE68A);
    } else if (label.contains('En atención') ||
        label.contains('En progreso') ||
        label.contains('atención')) {
      bg = AppTheme.tealSoft;
      fg = AppTheme.tealDark;
      border = const Color(0xFF99F6E4);
    } else if (label.contains('Cerrado') || label.contains('Cerrada')) {
      bg = AppTheme.surfaceMuted;
      fg = AppTheme.slateMuted;
      border = AppTheme.border;
    } else if (label.contains('Enviado') || label.contains('confirmado')) {
      bg = AppTheme.cyanSoft;
      fg = AppTheme.cyanDark;
      border = const Color(0xFFBAE6FD);
    } else {
      bg = AppTheme.surfaceMuted;
      fg = AppTheme.slate;
      border = AppTheme.border;
    }

    if (isOutlined) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontHeading,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontHeading,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Sequential Numbered Step Card as seen in Wireframe C-04
class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.number,
    required this.title,
    required this.description,
  });

  final int number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderLight, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppTheme.teal,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  fontFamily: AppTheme.fontHeading,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontHeading,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13.5,
                      color: AppTheme.slateMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual Map Grid Placeholder as seen in Wireframe C-02 and M-02
class MapPreviewCard extends StatelessWidget {
  const MapPreviewCard({
    super.key,
    this.height = 140,
    this.coordinatesText = 'Coordenadas capturadas por GPS',
    this.onTap,
  });

  final double height;
  final String coordinatesText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border, width: 1.2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  // Grid pattern simulation
                  CustomPaint(
                    size: Size(double.infinity, height),
                    painter: _GridPainter(),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        size: 32,
                        color: AppTheme.emergency,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            coordinatesText,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.slateMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dashed outline button for "Consulta de emergencia sin cuenta" in Wireframe A-01
class DashedOutlineButton extends StatelessWidget {
  const DashedOutlineButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(
            color: Color(0xFF94A3B8),
            width: 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          foregroundColor: AppTheme.slateMuted,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppTheme.slateMuted),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontHeading,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
