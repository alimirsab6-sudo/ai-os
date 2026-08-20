import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({
    super.key,
    required this.controller,
    this.progress = 0.68,
    this.status = 'Scanning your face...',
    this.onUnlock,
  });

  final CameraController controller;
  final double progress;
  final String status;
  final VoidCallback? onUnlock;

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(42, 24, 42, 22),
          child: Column(
            children: [
              // ---------------------------------------------------------------
              // TOP BRAND
              // ---------------------------------------------------------------
              const Text(
                'CRONYX',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 10,
                  height: 1,
                ),
              ),

              const SizedBox(height: 7),

              Container(
                width: 145,
                height: 1,
                color: const Color(0xFF18202B),
              ),

              const SizedBox(height: 25),

              // ---------------------------------------------------------------
              // TITLE
              // ---------------------------------------------------------------
              const Text(
                'FACE RECOGNITION',
                style: TextStyle(
                  color: Color(0xFF3298FF),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Position your face in the frame',
                style: TextStyle(
                  color: Color(0xFFD6DAE0),
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                ),
              ),

              const SizedBox(height: 22),

              // ---------------------------------------------------------------
              // CAMERA
              // ---------------------------------------------------------------
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: _CameraFrame(
                      controller: widget.controller,
                      animation: _scanController,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ---------------------------------------------------------------
              // SCANNING STATUS
              // ---------------------------------------------------------------
              Row(
                children: [
                  Text(
                    widget.status,
                    style: const TextStyle(
                      color: Color(0xFF3B9CFF),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(widget.progress * 100).round()}%',
                    style: const TextStyle(
                      color: Color(0xFF3B9CFF),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 9),

              _ProgressBar(progress: widget.progress),

              const SizedBox(height: 20),

              // ---------------------------------------------------------------
              // PROCESS STEPS
              // ---------------------------------------------------------------
              Container(
                height: 105,
                decoration: BoxDecoration(
                  color: const Color(0x080F1720),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0x141E2935),
                  ),
                ),
                child: Row(
                  children: const [
                    Expanded(
                      child: _Step(
                        icon: Icons.face_retouching_natural,
                        label: 'Face Detected',
                        active: true,
                      ),
                    ),
                    _Divider(),
                    Expanded(
                      child: _Step(
                        icon: Icons.layers_outlined,
                        label: 'Capturing',
                        active: true,
                      ),
                    ),
                    _Divider(),
                    Expanded(
                      child: _Step(
                        icon: Icons.verified_user_outlined,
                        label: 'Verifying',
                        active: false,
                      ),
                    ),
                    _Divider(),
                    Expanded(
                      child: _Step(
                        icon: Icons.lock_outline,
                        label: 'Unlocking',
                        active: false,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ---------------------------------------------------------------
              // SECURITY FOOTER
              // ---------------------------------------------------------------
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0x080F1720),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0x141E2935),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF318FFF),
                      size: 29,
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Secure. Private. Local.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Your biometric data never leaves your device.',
                          style: TextStyle(
                            color: Color(0xFF7F8995),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF647181),
                      size: 21,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CAMERA FRAME
// =============================================================================

class _CameraFrame extends StatelessWidget {
  const _CameraFrame({
    required this.controller,
    required this.animation,
  });

  final CameraController controller;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Actual webcam image.
              CameraPreview(controller),

              // Dark glass overlay.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.20),
                    ],
                  ),
                ),
              ),

              // Face scanning HUD.
              CustomPaint(
                painter: _FaceScannerPainter(
                  progress: animation.value,
                ),
              ),

              // Animated horizontal scan line.
              Positioned(
                left: 0,
                right: 0,
                top: (40.0 + (animation.value * 65.0).clamp(0.0, 65.0)),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3298FF),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3298FF).withValues(alpha: 0.85),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// FACE HUD
// =============================================================================

class _FaceScannerPainter extends CustomPainter {
  const _FaceScannerPainter({
    required this.progress,
  });

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final double faceWidth = math.min(size.width * 0.43, 330.0).toDouble();
    final faceHeight = faceWidth * 1.22;

    final rect = Rect.fromCenter(
      center: center,
      width: faceWidth,
      height: faceHeight,
    );

    final bluePaint = Paint()
      ..color = const Color(0xFF46A5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Face recognition circle.
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: faceWidth + 75,
        height: faceHeight + 15,
      ),
      bluePaint..strokeWidth = 1.5,
    );

    // Four corner brackets.
    const cornerLength = 48.0;

    _corner(
      canvas,
      rect.topLeft,
      const Offset(1, 0),
      const Offset(0, 1),
      cornerLength,
      bluePaint,
    );

    _corner(
      canvas,
      rect.topRight,
      const Offset(-1, 0),
      const Offset(0, 1),
      cornerLength,
      bluePaint,
    );

    _corner(
      canvas,
      rect.bottomLeft,
      const Offset(1, 0),
      const Offset(0, -1),
      cornerLength,
      bluePaint,
    );

    _corner(
      canvas,
      rect.bottomRight,
      const Offset(-1, 0),
      const Offset(0, -1),
      cornerLength,
      bluePaint,
    );

    // Rotating recognition arc.
    final arcPaint = Paint()
      ..color = const Color(0xFF3298FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawArc(
      Rect.fromCenter(
        center: center,
        width: faceWidth + 90,
        height: faceHeight + 30,
      ),
      progress * math.pi * 2,
      math.pi * 0.65,
      false,
      arcPaint,
    );
  }

  void _corner(
    Canvas canvas,
    Offset origin,
    Offset horizontal,
    Offset vertical,
    double length,
    Paint paint,
  ) {
    canvas.drawLine(
      origin,
      origin + horizontal * length,
      paint,
    );

    canvas.drawLine(
      origin,
      origin + vertical * length,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceScannerPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// =============================================================================
// PROGRESS BAR
// =============================================================================

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
  });

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 7,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 7,
                backgroundColor: const Color(0x152A3542),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF3298FF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PROCESS STEP
// =============================================================================

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 28,
          color: active
              ? const Color(0xFF3CA3FF)
              : const Color(0xFF7A8490),
        ),
        const SizedBox(height: 9),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active
                ? const Color(0xFFDCE3EB)
                : const Color(0xFF858E99),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      color: const Color(0x1D738091),
    );
  }
}




