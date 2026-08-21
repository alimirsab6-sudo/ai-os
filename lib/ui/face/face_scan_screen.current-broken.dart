import 'dart:math' as math;
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final ValueChanged<String> onAccessGranted;

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with SingleTickerProviderStateMixin {
  final FaceEnrollmentService _faceService = FaceEnrollmentService();

  final CronyxIdentityStore _identityStore = CronyxIdentityStore();

  late final AnimationController _scanAnimation;

  bool _busy = false;
  bool _faceDetected = false;
  bool _pinRequired = false;

  double _progress = 0;

  String _status = 'LOOKING FOR YOU';
  String? _error;

  @override
  void initState() {
    super.initState();

    _scanAnimation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    if (!widget.enrollmentMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _verifyAutomatically(),
      );
    }
  }

  @override
  void dispose() {
    _scanAnimation.dispose();
    _faceService.dispose();
    super.dispose();
  }

  Future<void> _beginEnrollment() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _faceDetected = false;
      _progress = 0;
      _status = 'DETECTING';
    });

    final result = await _faceService.enroll(
      widget.controller,
      requiredSamples: 5,
      onProgress: (current, total) {
        if (!mounted) return;

        setState(() {
          _faceDetected = true;
          _progress = current / total;

          if (current == 1) {
            _status = 'DETECTING';
          } else if (current < total) {
            _status = 'CAPTURING';
          } else {
            _status = 'PROCESSING';
          }
        });
      },
    );

    if (!mounted) return;

    if (!result.success || result.embedding == null) {
      setState(() {
        _busy = false;
        _error = result.message ?? 'Enrollment failed.';
        _status = 'FACE NOT DETECTED';
      });
      return;
    }

    setState(() {
      _status = 'SECURING';
      _progress = 1;
    });

    final profile = await _showCreateProfileDialog(result.embedding!);

    if (!mounted) return;

    if (profile == null) {
      setState(() {
        _busy = false;
        _status = 'IDENTITY CAPTURED';
      });
      return;
    }

    await _identityStore.save(
      name: profile.name,
      pin: profile.pin,
      embedding: result.embedding!,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;
      _status = 'IDENTITY ENROLLED';
    });

    await Future<void>.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    widget.onAccessGranted(profile.name);
  }

  Future<void> _verifyAutomatically() async {
    if (_busy || widget.enrollmentMode) return;

    final profile = await _identityStore.load();

    if (!mounted) return;

    if (profile == null) {
      setState(() {
        _error = 'Identity profile is missing.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = 'LOOKING FOR YOU';
      _progress = 0;
      _error = null;
    });

    final result = await _faceService.verify(
      widget.controller,
      profile.embedding,
      samples: 3,
      onProgress: (current, total) {
        if (!mounted) return;

        setState(() {
          _faceDetected = true;
          _progress = current / total;
          _status = current < total ? 'VERIFYING' : 'PROCESSING';
        });
      },
    );

    if (!mounted) return;

    if (result.matched) {
      setState(() {
        _status = 'IDENTITY VERIFIED';
        _progress = 1;
      });

      await Future<void>.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;

      widget.onAccessGranted(profile.name);
      return;
    }

    setState(() {
      _busy = false;
      _pinRequired = true;
      _status = 'IDENTITY NOT RECOGNIZED';
      _error = 'Face did not match. Enter your PIN to continue.';
    });
  }

  Future<void> _showPinDialog() async {
    final profile = await _identityStore.load();

    if (!mounted || profile == null) return;

    final controller = TextEditingController();
    var error = '';

    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF071019),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Color(0xFF164A70)),
              ),
              child: SizedBox(
                width: 430,
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: Color(0xFF2D9CFF),
                        size: 46,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'IDENTITY LOCKED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Face recognition did not match.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .65),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        obscureText: true,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          letterSpacing: 10,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'PIN',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: .25),
                            letterSpacing: 4,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF03080D),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF163B57),
                            ),
                          ),
                        ),
                      ),
                      if (error.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          error,
                          style: const TextStyle(color: Color(0xFFFF6262)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: () async {
                            final pin = controller.text.trim();

                            if (pin.length < 4) {
                              setDialogState(() {
                                error = 'Enter your 4â€“6 digit PIN.';
                              });
                              return;
                            }

                            final valid = await _identityStore.verifyPin(
                              profile,
                              pin,
                            );

                            if (valid) {
                              if (context.mounted) {
                                Navigator.of(context).pop(true);
                              }
                            } else {
                              setDialogState(() {
                                error = 'Wrong PIN. Access denied.';
                              });
                              controller.clear();
                            }
                          },
                          child: const Text(
                            'UNLOCK CRONYX',
                            style: TextStyle(
                              letterSpacing: 2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();

    if (!mounted) return;

    if (granted == true) {
      widget.onAccessGranted(profile.name);
    }
  }

  Future<_ProfileInput?> _showCreateProfileDialog(
    List<double> embedding,
  ) async {
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    final confirmController = TextEditingController();

    String error = '';

    final result = await showDialog<_ProfileInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF071019),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Color(0xFF164A70)),
              ),
              child: SizedBox(
                width: 470,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: Color(0xFF2D9CFF),
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'IDENTITY SECURED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your CronyX local profile.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .65),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _profileField(
                        nameController,
                        'YOUR NAME',
                        Icons.person_outline,
                        false,
                      ),
                      const SizedBox(height: 14),
                      _profileField(
                        pinController,
                        'CREATE PIN',
                        Icons.lock_outline,
                        true,
                      ),
                      const SizedBox(height: 14),
                      _profileField(
                        confirmController,
                        'CONFIRM PIN',
                        Icons.lock_reset_outlined,
                        true,
                      ),
                      if (error.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF6262)),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: () {
                            final name = nameController.text.trim();
                            final pin = pinController.text.trim();
                            final confirm = confirmController.text.trim();

                            if (name.isEmpty) {
                              setDialogState(() {
                                error = 'Enter your name.';
                              });
                              return;
                            }

                            if (pin.length < 4 || pin.length > 6) {
                              setDialogState(() {
                                error = 'PIN must contain 4â€“6 digits.';
                              });
                              return;
                            }

                            if (pin != confirm) {
                              setDialogState(() {
                                error = 'PINs do not match.';
                              });
                              return;
                            }

                            Navigator.of(
                              context,
                            ).pop(_ProfileInput(name: name, pin: pin));
                          },
                          child: const Text(
                            'SAVE PROFILE',
                            style: TextStyle(
                              letterSpacing: 2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    pinController.dispose();
    confirmController.dispose();

    return result;
  }

  Widget _profileField(
    TextEditingController controller,
    String label,
    IconData icon,
    bool obscure,
  ) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: obscure ? TextInputType.number : TextInputType.name,
      inputFormatters: obscure
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF3298FF)),
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8FA2B5)),
        filled: true,
        fillColor: const Color(0xFF03080D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF163B57)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02070C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFF164666)),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF02070C),
                  Color(0xFF030A11),
                  Color(0xFF020609),
                ],
              ),
            ),
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final height = constraints.maxHeight;

                      final wide = width >= 1200;
                      final medium = width >= 850;

                      if (wide) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(34, 18, 34, 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 190,
                                child: _leftPanel(),
                              ),
                              const SizedBox(width: 28),
                              Expanded(
                                flex: 5,
                                child: _cameraPanel(),
                              ),
                              const SizedBox(width: 36),
                              Expanded(
                                flex: 4,
                                child: _rightPanel(),
                              ),
                            ],
                          ),
                        );
                      }

                      if (medium) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: height - 42,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: _cameraPanel(),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 4,
                                  child: _rightPanel(),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _cameraPanel(),
                            const SizedBox(height: 22),
                            _rightPanel(),
                            const SizedBox(height: 22),
                            _leftPanel(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 32, 0),
      child: Row(
        children: [
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w300,
                letterSpacing: 10,
              ),
              children: [
                TextSpan(
                  text: 'CRONY',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: 'X',
                  style: TextStyle(color: Color(0xFF148EFF)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          const Text(
            'AI OPERATING SYSTEM',
            style: TextStyle(
              color: Color(0xFF168DDF),
              fontSize: 13,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          const Icon(Icons.remove, color: Color(0xFF7B8C9A)),
          const SizedBox(width: 25),
          const Icon(Icons.crop_square, color: Color(0xFF7B8C9A)),
          const SizedBox(width: 25),
          const Icon(Icons.close, color: Color(0xFF7B8C9A)),
        ],
      ),
    );
  }

  Widget _leftPanel() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF123B58)),
        color: const Color(0x99101A22),
      ),
      child: Column(
        children: [
          const SizedBox(height: 28),
          const Icon(Icons.shield_outlined, color: Color(0xFF138EFF), size: 54),
          const SizedBox(height: 12),
          const Text(
            'IDENTITY SYSTEM',
            style: TextStyle(
              color: Color(0xFF1698FF),
              letterSpacing: 2,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          _navItem(
            Icons.center_focus_strong,
            'ENROLL',
            'IDENTITY',
            widget.enrollmentMode,
          ),
          _navItem(
            Icons.lock_outline,
            'VERIFY',
            'IDENTITY',
            !widget.enrollmentMode,
          ),
          const Spacer(),
          const Divider(color: Color(0xFF12364E), indent: 26, endIndent: 26),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    color: Color(0xFF18C77A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'OFFLINE',
                  style: TextStyle(color: Color(0xFF18C77A), letterSpacing: 1),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 26),
            child: Text(
              'All data is processed\nlocally on this device.',
              style: TextStyle(color: Color(0xFF84919D), height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String title, String subtitle, bool active) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: active ? const Color(0x18108EFF) : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: active ? const Color(0xFF169EFF) : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? const Color(0xFF159BFF) : const Color(0xFF7A8997),
            size: 29,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF159BFF)
                      : const Color(0xFF8B99A6),
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF159BFF)
                      : const Color(0xFF8B99A6),
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cameraPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;

        final cameraHeight = availableHeight.isFinite
            ? (availableHeight - 90).clamp(260.0, 620.0)
            : (availableWidth * 0.68).clamp(260.0, 620.0);

        return Column(
          children: [
            SizedBox(
              height: cameraHeight,
              child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF159BFF), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x30159BFF),
                  blurRadius: 25,
                  spreadRadius: 1,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(widget.controller),
                Container(color: Colors.black.withValues(alpha: .12)),
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (_, _) {
                    return CustomPaint(
                      painter: _HudPainter(
                        progress: _scanAnimation.value,
                        detected: _faceDetected,
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 25,
                  left: 30,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3838),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'REC',
                        style: TextStyle(
                          color: Color(0xFFFF4A4A),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 30,
                  bottom: 26,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _faceDetected
                          ? const Color(0x1827D987)
                          : const Color(0x18159BFF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _faceDetected
                            ? const Color(0xFF16D879)
                            : const Color(0xFF168EFF),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _faceDetected
                              ? Icons.check_circle_outline
                              : Icons.face_retouching_natural,
                          color: _faceDetected
                              ? const Color(0xFF20D987)
                              : const Color(0xFF168EFF),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _faceDetected ? 'FACE DETECTED' : 'LOOKING FOR FACE',
                          style: TextStyle(
                            color: _faceDetected
                                ? const Color(0xFF20D987)
                                : const Color(0xFF168EFF),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _status,
                style: const TextStyle(
                  color: Color(0xFF159BFF),
                  fontSize: 18,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${(_progress * 100).round()}%',
              style: const TextStyle(color: Color(0xFF159BFF), fontSize: 17),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _progress,
          minHeight: 5,
          backgroundColor: const Color(0x162D465A),
          valueColor: const AlwaysStoppedAnimation(Color(0xFF159BFF)),
        ),
      ],
    );
  }

  Widget _rightPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 700;

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(
              top: compact ? 2 : 8,
              bottom: 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WELCOME TO',
                  style: TextStyle(
                    color: const Color(0xFF168EFF),
                    fontSize: compact ? 15 : 18,
                    letterSpacing: 5,
                  ),
                ),

                SizedBox(height: compact ? 4 : 8),

                Text(
                  'CRONYX',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 38 : 48,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 8,
                  ),
                ),

                SizedBox(height: compact ? 6 : 12),

                Text(
                  widget.enrollmentMode
                      ? 'ENROLL YOUR IDENTITY'
                      : 'VERIFY YOUR IDENTITY',
                  style: TextStyle(
                    color: const Color(0xFF168EFF),
                    fontSize: compact ? 19 : 24,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2,
                  ),
                ),

                SizedBox(height: compact ? 6 : 10),

                Text(
                  'Your identity keeps CronyX secure.\n'
                  'This data is private and stays on your device.',
                  style: TextStyle(
                    color: const Color(0xFFB2BEC9),
                    fontSize: compact ? 14 : 16,
                    height: 1.4,
                  ),
                ),

                SizedBox(height: compact ? 12 : 20),

                _instructions(),

                SizedBox(height: compact ? 12 : 18),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFF6464),
                        fontSize: 13,
                      ),
                    ),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: compact ? 62 : 72,
                  child: _buildPrimaryButton(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _instructions() {
    final items = [
      (
        Icons.person_outline,
        'Look at the camera',
        'Position your face in the frame',
      ),
      (
        Icons.wb_sunny_outlined,
        'Good lighting',
        'Make sure your face is well lit',
      ),
      (
        Icons.accessibility_new,
        'Stay still',
        'We will capture several samples',
      ),
      (
        Icons.shield_outlined,
        'Secure & Private',
        'Your data never leaves this device',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF16415E)),
        color: const Color(0x70101B24),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(19),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF128FFF)),
                        ),
                        child: Icon(
                          items[i].$1,
                          color: const Color(0xFF128FFF),
                        ),
                      ),
                      const SizedBox(width: 17),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              items[i].$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              items[i].$3,
                              style: const TextStyle(
                                color: Color(0xFF8D9BA7),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (i != items.length - 1)
                  const Divider(
                    color: Color(0xFF17364B),
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 14),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF14374D)),
        color: const Color(0x80101A22),
      ),
      child: Row(
        children: [
          _footerItem(
            Icons.verified_user_outlined,
            'CRONYX CORE',
            'SECURED BY YOU',
          ),
          _footerDivider(),
          _footerItem(Icons.memory_outlined, 'LOCAL AI ENGINE', 'READY'),
          _footerDivider(),
          _footerItem(Icons.storage_outlined, 'LOCAL STORAGE', 'SECURE'),
          _footerDivider(),
          _footerItem(Icons.bolt_outlined, 'SYSTEM STATUS', 'OPTIMAL'),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                TimeOfDay.now().format(context),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              Text(
                _dateString(),
                style: const TextStyle(color: Color(0xFF7D8A96), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(width: 25),
          const Icon(Icons.radar, color: Color(0xFF148EFF), size: 38),
        ],
      ),
    );
  }

  Widget _footerItem(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF718796), size: 28),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF7F94A4),
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFAAB7C2),
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footerDivider() {
    return Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      color: const Color(0xFF17364B),
    );
  }

  String _dateString() {
    final now = DateTime.now();

    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];

    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

class _ProfileInput {
  const _ProfileInput({required this.name, required this.pin});

  final String name;
  final String pin;
}

class _HudPainter extends CustomPainter {
  const _HudPainter({required this.progress, required this.detected});

  final double progress;
  final bool detected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final width = size.width * .48;
    final height = width * 1.18;

    final faceRect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );

    final paint = Paint()
      ..color = detected ? const Color(0xFF36D99A) : const Color(0xFF159BFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;

    canvas.drawOval(faceRect, paint);

    final outer = Rect.fromCenter(
      center: center,
      width: width + 80,
      height: height + 40,
    );

    canvas.drawArc(outer, progress * math.pi * 2, math.pi * 1.45, false, paint);

    final cornerPaint = Paint()
      ..color = const Color(0xFF159BFF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const length = 45.0;

    final left = faceRect.left - 25;
    final right = faceRect.right + 25;
    final top = faceRect.top - 20;
    final bottom = faceRect.bottom + 20;

    canvas
      ..drawLine(Offset(left, top), Offset(left + length, top), cornerPaint)
      ..drawLine(Offset(left, top), Offset(left, top + length), cornerPaint)
      ..drawLine(Offset(right, top), Offset(right - length, top), cornerPaint)
      ..drawLine(Offset(right, top), Offset(right, top + length), cornerPaint)
      ..drawLine(
        Offset(left, bottom),
        Offset(left + length, bottom),
        cornerPaint,
      )
      ..drawLine(
        Offset(left, bottom),
        Offset(left, bottom - length),
        cornerPaint,
      )
      ..drawLine(
        Offset(right, bottom),
        Offset(right - length, bottom),
        cornerPaint,
      )
      ..drawLine(
        Offset(right, bottom),
        Offset(right, bottom - length),
        cornerPaint,
      );
  }

  @override
  bool shouldRepaint(covariant _HudPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.detected != detected;
  }
}




extension _FaceScanPrimaryButton on _FaceScanScreenState {
  Widget _buildPrimaryButton() {
    final enabled = !_busy;

    return SizedBox(
      width: double.infinity,
      height: 72,
      child: FilledButton(
        onPressed: enabled
            ? () async {
                if (widget.enrollmentMode) {
                  await _beginEnrollment();
                } else if (_pinRequired) {
                  await _showPinDialog();
                }
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF0878E8),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF12395C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.enrollmentMode
                  ? Icons.face_retouching_natural
                  : Icons.lock_open_rounded,
              size: 25,
            ),
            const SizedBox(width: 14),
            Text(
              widget.enrollmentMode
                  ? 'BEGIN ENROLLMENT'
                  : _pinRequired
                      ? 'ENTER PIN TO CONTINUE'
                      : 'SCANNING IDENTITY...',
              style: const TextStyle(
                fontSize: 17,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


