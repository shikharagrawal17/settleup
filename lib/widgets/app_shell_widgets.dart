import 'package:flutter/material.dart';

// ─── Palette constants (Paytm inspired) ─────────────────────────────────
const kPrimaryBlue = Color(0xFF00B9F1);
const kDarkBlue = Color(0xFF002E6E);
const kBackground = Color(0xFFF5F7FA);
const kSurface = Colors.white;
const kSurfaceBorder = Color(0x1A000000); // black 10%

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: kBackground,
      ),
      child: Stack(
        children: [
          // Subtle blue mist for depth
          const Positioned(
            top: -150,
            right: -100,
            child: _GlowOrb(
              size: 400,
              color: Color(0x0A00B9F1),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MetricPill extends StatelessWidget {
  const MetricPill({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? kPrimaryBlue : kDarkBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.black45,
                  letterSpacing: 0.2,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black45,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 16),
          trailing!,
        ],
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
