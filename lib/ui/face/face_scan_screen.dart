import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../face/face_enrollment_service.dart';
import '../../face/face_identity_profile.dart';

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({
    required this.controller,
    required this.enrollmentMode,
    required this.onAccessGranted,
    super.key,
  });

  final CameraController controller;
  final bool enrollmentMode;
  final void Function(String name, bool returningUser) onAccessGranted;

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with SingleTickerProviderStateMixin {
  final FaceEnrollmentService _service = FaceEnrollmentService();
  final CronyxIdentityStore _store = CronyxIdentityStore();

  late final AnimationController _animation;

  bool _busy = false;
  double _progress = 0;
  String _status = 'READY';
  String? _error;

  @override
  void initState() {
    super.initState();

    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    if (!widget.enrollmentMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _verify(),
      );
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = 'DETECTING FACE';
    });

    final result = await _service.enroll(
      widget.controller,
      requiredSamples: 3,
      onProgress: (current, total) {
        if (!mounted) return;

        setState(() {
          _progress = current / total;
          _status = current == total
              ? 'PROCESSING'
              : 'CAPTURING $current / $total';
        });
      },
    );

    if (!mounted) return;

    if (!result.success || result.embedding == null) {
      setState(() {
        _busy = false;
        _status = 'ENROLLMENT FAILED';
        _error = result.message;
      });
      return;
    }

    final input = await _profileDialog();

    if (!mounted) return;

    if (input == null) {
      setState(() {
        _busy = false;
        _status = 'READY';
      });
      return;
    }

    await _store.save(
      name: input.$1,
      pin: input.$2,
      embedding: result.embedding!,
    );

    if (!mounted) return;

    setState(() {
      _progress = 1;
      _status = 'IDENTITY ENROLLED';
      _busy = false;
    });

    await Future<void>.delayed(const Duration(milliseconds: 150));

    if (mounted) {
      widget.onAccessGranted(input.$1, false);
    }
  }

  Future<void> _verify() async {
    if (_busy || widget.enrollmentMode) return;

    final profile = await _store.load();

    if (!mounted) return;

    if (profile == null) {
      setState(() {
        _error = 'No identity is enrolled.';
        _status = 'ENROLLMENT REQUIRED';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'LOOKING FOR YOU';
      _progress = 0;
    });

    final result = await _service.verify(
      widget.controller,
      profile.embedding,
      samples: 1,
      onProgress: (current, total) {
        if (!mounted) return;

        setState(() {
          _progress = current / total;
          _status = 'VERIFYING IDENTITY';
        });
      },
    );

    if (!mounted) return;

    if (result.matched) {
      setState(() {
        _progress = 1;
        _status = 'IDENTITY VERIFIED';
        _busy = false;
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        widget.onAccessGranted(profile.name, true);
      }

      return;
    }

    setState(() {
      _busy = false;
      _status = 'IDENTITY NOT RECOGNIZED';
      _error = result.message;
    });
  }

  Future<(String, String)?> _profileDialog() async {
    final nameController = TextEditingController();
    final pinController = TextEditingController();

    final result = await showDialog<(String, String)>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF10161D),
          title: const Text(
            'Create your CronyX identity',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'PIN',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final pin = pinController.text.trim();

                if (name.isEmpty || pin.length < 4) return;

                Navigator.pop(context, (name, pin));
              },
              child: const Text('ENROLL'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    pinController.dispose();

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070A),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 720;
            final horizontal = constraints.maxWidth < 900 ? 20.0 : 42.0;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontal,
                compact ? 16 : 24,
                horizontal,
                20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 36,
                ),
                child: Column(
                  children: [
                    const Text(
                      'CRONYX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 10,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 145,
                      height: 1,
                      color: const Color(0xFF18202B),
                    ),
                    SizedBox(height: compact ? 14 : 24),
                    Text(
                      widget.enrollmentMode
                          ? 'WELCOME TO CRONYX'
                          : 'FACE RECOGNITION',
                      style: const TextStyle(
                        color: Color(0xFF3298FF),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.enrollmentMode
                          ? 'Create your secure local identity'
                          : 'Position your face in the frame',
                      style: const TextStyle(
                        color: Color(0xFFD6DAE0),
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: compact ? 14 : 22),
                    AspectRatio(
                      aspectRatio: constraints.maxWidth < 700 ? 16 / 11 : 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(widget.controller),
                            Container(
                              color: Colors.black.withValues(alpha: .16),
                            ),
                            AnimatedBuilder(
                              animation: _animation,
                              builder: (_, _) {
                                return CustomPaint(
                                  painter: _HudPainter(
                                    progress: _animation.value,
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              top: 18,
                              left: 20,
                              child: Row(
                                children: [
                                  Container(
                                    width: 9,
                                    height: 9,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF3838),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Color(0xFFFF4A4A),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _status,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF3298FF),
                              fontSize: 16,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${(_progress * 100).round()}%',
                          style: const TextStyle(
                            color: Color(0xFF3298FF),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress.clamp(0, 1),
                      minHeight: 5,
                      backgroundColor: const Color(0x162D465A),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF3298FF),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFF6464),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 14 : 20),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : widget.enrollmentMode
                                ? _enroll
                                : _verify,
                        child: Text(
                          _busy
                              ? _status
                              : widget.enrollmentMode
                                  ? 'BEGIN ENROLLMENT'
                                  : 'SCAN MY FACE',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
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
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Secure. Private. Local.\nYour biometric identity stays on this device.',
                              style: TextStyle(
                                color: Color(0xFFB7C1CC),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  const _HudPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final width = (size.width * .40).clamp(180.0, 340.0);
    final height = width * 1.18;

    final rect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );

    final paint = Paint()
      ..color = const Color(0xFF46A5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    const corner = 38.0;

    for (final item in [
      (rect.topLeft, const Offset(1, 0), const Offset(0, 1)),
      (rect.topRight, const Offset(-1, 0), const Offset(0, 1)),
      (rect.bottomLeft, const Offset(1, 0), const Offset(0, -1)),
      (rect.bottomRight, const Offset(-1, 0), const Offset(0, -1)),
    ]) {
      canvas.drawLine(
        item.$1,
        item.$1 + item.$2 * corner,
        paint,
      );
      canvas.drawLine(
        item.$1,
        item.$1 + item.$3 * corner,
        paint,
      );
    }

    canvas.drawArc(
      Rect.fromCenter(
        center: center,
        width: width + 50,
        height: height + 20,
      ),
      progress * 6.283,
      1.8,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HudPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
