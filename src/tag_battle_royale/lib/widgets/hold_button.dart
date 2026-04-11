import 'package:flutter/material.dart';

/// A button that must be held down for [holdDuration] to trigger [onComplete].
/// Shows a circular progress indicator that fills.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.onComplete,
    required this.color,
    required this.backgroundColor,
    required this.textColor,
    this.enabled = true,
    this.holdDuration = const Duration(seconds: 4),
    this.padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  });

  final String label;
  final VoidCallback onComplete;
  final Color color;
  final Color backgroundColor;
  final Color textColor;
  final bool enabled;
  final Duration holdDuration;
  final EdgeInsets padding;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_triggered) {
        _triggered = true;
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent _) {
    if (!widget.enabled) return;
    _controller.forward(from: 0);
  }

  void _onUp(PointerEvent _) {
    if (!_triggered) {
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: widget.enabled ? 1.0 : 0.4,
            child: Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _controller.value,
                      strokeWidth: 3,
                      color: widget.color,
                      backgroundColor: widget.color.withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: widget.textColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}