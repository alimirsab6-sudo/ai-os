import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
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
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'PIN'),
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
    const blue = Color(0xFF168EFF);
    const panel = Color(0xFF071019);
    const border = Color(0xFF12364E);

    return Scaffold(
      backgroundColor: const Color(0xFF03070B),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 680 || constraints.maxWidth < 1050;
            final leftWidth = compact ? 190.0 : 225.0;
            final rightWidth = compact ? 275.0 : 320.0;

            return Column(
              children: [
                Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF05090E),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF102331)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 20),
                      const Text(
                        'CRONYX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Minimize',
                        onPressed: () => windowManager.minimize(),
                        icon: const Icon(
                          Icons.remove,
                          color: Color(0xFF8FA2B3),
                          size: 17,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Maximize / Restore',
                        onPressed: () async {
                          if (await windowManager.isMaximized()) {
                            await windowManager.unmaximize();
                          } else {
                            await windowManager.maximize();
                          }
                        },
                        icon: const Icon(
                          Icons.crop_square,
                          color: Color(0xFF8FA2B3),
                          size: 16,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => windowManager.close(),
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFFB9C4CE),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: leftWidth,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(14, 14, 7, 14),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: border),
                          ),
                          child: Column(
                            children: [
                              const SizedBox(height: 20),
                              const Icon(
                                Icons.face_retouching_natural,
                                color: blue,
                                size: 34,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'IDENTITY SYSTEM',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.7,
                                ),
                              ),
                              const SizedBox(height: 22),

                              _sideItem(
                                Icons.center_focus_strong,
                                'ENROLL',
                                'IDENTITY',
                                widget.enrollmentMode,
                              ),

                              _sideItem(
                                Icons.lock_outline,
                                'VERIFY',
                                'IDENTITY',
                                !widget.enrollmentMode,
                              ),

                              const Spacer(),

                              Container(
                                margin: const EdgeInsets.all(12),
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF16364A),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      color: Color(0xFF00D477),
                                      size: 9,
                                    ),
                                    SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        'OFFLINE\nLocal processing enabled',
                                        style: TextStyle(
                                          color: Color(0xFF8FA2B3),
                                          fontSize: 9,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(7, 14, 7, 14),
                          child: Column(
                            children: [
                              Text(
                                widget.enrollmentMode
                                    ? 'ENROLL YOUR IDENTITY'
                                    : 'VERIFY YOUR IDENTITY',
                                style: const TextStyle(
                                  color: blue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 3.5,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                widget.enrollmentMode
                                    ? 'Position your face in the frame'
                                    : 'Look at the camera to verify your identity',
                                style: const TextStyle(
                                  color: Color(0xFFB8C5D0),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),

                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: border),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CameraPreview(widget.controller),

                                      Container(
                                        color: Colors.black.withValues(
                                          alpha: .08,
                                        ),
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
                                        top: 14,
                                        left: 16,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
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
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 9),

                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _status,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: blue,
                                        fontSize: 11,
                                        letterSpacing: 1.8,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(_progress * 100).round()}%',
                                    style: const TextStyle(
                                      color: blue,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 4),

                              LinearProgressIndicator(
                                value: _progress.clamp(0, 1),
                                minHeight: 3,
                                backgroundColor: const Color(0x182A4050),
                                valueColor: const AlwaysStoppedAnimation(blue),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(
                        width: rightWidth,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(7, 14, 14, 14),
                          padding: const EdgeInsets.fromLTRB(17, 18, 17, 16),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.enrollmentMode
                                    ? 'WELCOME TO CRONYX'
                                    : 'IDENTITY CHECK',
                                style: const TextStyle(
                                  color: blue,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.5,
                                ),
                              ),

                              const SizedBox(height: 8),

                              Text(
                                widget.enrollmentMode
                                    ? 'Create your secure local identity.'
                                    : 'Confirm your enrolled identity.',
                                style: const TextStyle(
                                  color: Color(0xFFD8E0E7),
                                  fontSize: 17,
                                  height: 1.3,
                                ),
                              ),

                              const SizedBox(height: 15),

                              _instruction(
                                Icons.person_outline,
                                'Look at the camera',
                                'Position your face inside the frame.',
                              ),

                              _instruction(
                                Icons.wb_sunny_outlined,
                                'Good lighting',
                                'Make sure your face is clearly visible.',
                              ),

                              _instruction(
                                Icons.pan_tool_outlined,
                                'Stay still',
                                widget.enrollmentMode
                                    ? 'We will capture several samples.'
                                    : 'Hold still while we verify you.',
                              ),

                              _instruction(
                                Icons.shield_outlined,
                                'Secure & Private',
                                'Your biometric data stays on this device.',
                              ),

                              const Spacer(),

                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 9),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFFF6464),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : widget.enrollmentMode
                                      ? _enroll
                                      : _verify,
                                  icon: Icon(
                                    widget.enrollmentMode
                                        ? Icons.face_retouching_natural
                                        : Icons.lock_open_rounded,
                                  ),
                                  label: Text(
                                    _busy
                                        ? _status
                                        : widget.enrollmentMode
                                        ? 'BEGIN ENROLLMENT'
                                        : 'VERIFY IDENTITY',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0878E8),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              const Center(
                                child: Text(
                                  'LOCAL AI  •  LOCAL STORAGE  •  SECURE',
                                  style: TextStyle(
                                    color: Color(0xFF647789),
                                    fontSize: 8,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sideItem(IconData icon, String title, String subtitle, bool active) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0C2537) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? const Color(0xFF168EFF) : const Color(0x0012364E),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              icon,
              color: active ? const Color(0xFF168EFF) : const Color(0xFF718393),
              size: 25,
            ),
            const SizedBox(width: 11),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF8798A8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF5D7080), fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _instruction(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF12364E))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF168EFF)),
              ),
              child: Icon(icon, color: const Color(0xFF168EFF), size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Color(0xFF8FA0AF),
                      fontSize: 9,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

    final rect = Rect.fromCenter(center: center, width: width, height: height);

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
      canvas.drawLine(item.$1, item.$1 + item.$2 * corner, paint);
      canvas.drawLine(item.$1, item.$1 + item.$3 * corner, paint);
    }

    canvas.drawArc(
      Rect.fromCenter(center: center, width: width + 50, height: height + 20),
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
