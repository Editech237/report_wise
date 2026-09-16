import 'package:flutter/material.dart';

/// A shimmer placeholder used for loading states across the app
/// (replaces bare CircularProgressIndicators).
///
/// Colours are chosen to be clearly visible on the near-white app background:
/// the resting tone is a distinct gray-lavender and the highlight sweeps
/// lighter, so the motion reads clearly.
class ShimmerBlock extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final Color base;
  final Color highlight;

  const ShimmerBlock({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.base = const Color(0xFFD6D6E2),
    this.highlight = const Color(0xFFEFEFF6),
  });

  @override
  State<ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: [widget.base, widget.highlight, widget.base],
              stops: const [0.3, 0.5, 0.7],
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(1 + 2 * t, 0),
            ),
          ),
        );
      },
    );
  }
}

/// A loading skeleton for list screens.
class ShimmerList extends StatelessWidget {
  final int rows;
  final double itemHeight;

  const ShimmerList({super.key, this.rows = 6, this.itemHeight = 64});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ShimmerBlock(height: itemHeight, radius: 12),
          ),
      ],
    );
  }
}

/// A centered shimmer panel (used where the old spinner was centered).
class ShimmerPanel extends StatelessWidget {
  final int rows;
  const ShimmerPanel({super.key, this.rows = 5});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ShimmerList(rows: rows),
      ),
    );
  }
}