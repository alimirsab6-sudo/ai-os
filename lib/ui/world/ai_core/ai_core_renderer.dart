import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'ai_core_controller.dart';
import 'ai_core_state.dart';

/// Native Flutter port of the approved CronyX AI OS HTML Core.
///
/// The visual math intentionally mirrors the final HTML implementation:
/// fibonacci direction basis, procedural breathing/flow/turbulence, smooth
/// state profiles, perspective projection, mouse repulsion/ripple, blue
/// particle palette and additive particle blending. No separate central glow is rendered.
class AiCoreRenderer extends StatefulWidget {
  const AiCoreRenderer({
    required this.controller,
    this.animationEnabled = true,
    this.particleDensity = 1,
    super.key,
  }) : assert(particleDensity > 0 && particleDensity <= 1);

  final AiCoreController controller;
  final bool animationEnabled;
  final double particleDensity;

  @override
  State<AiCoreRenderer> createState() => _AiCoreRendererState();
}

class _AiCoreRendererState extends State<AiCoreRenderer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _FrameSignal _repaint;

  final _HtmlCoreModel _model = _HtmlCoreModel();
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _repaint = _FrameSignal();
    _ticker = createTicker(_tick);
    // Seed the renderer from the controller immediately. This prevents a
    // state selected before the first frame from being lost.
    _model.setState(widget.controller.state);
    widget.controller.addListener(_controllerChanged);
    if (widget.animationEnabled) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant AiCoreRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      _model.setState(widget.controller.state);
    }
    if (oldWidget.animationEnabled != widget.animationEnabled) {
      if (widget.animationEnabled) {
        _last = Duration.zero;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    }
  }

  void _controllerChanged() {
    _model.setState(widget.controller.state);
    if (!widget.controller.mouseInteraction) {
      _model.targetMouse = Offset.zero;
      _model.mouseActive = false;
    }
    _repaint.tick();
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1000000).clamp(0.0, 0.05);
    _last = elapsed;
    _model.update(dt, widget.controller);
    _repaint.tick();
  }

  void _hover(PointerHoverEvent event, Size size) {
    if (!widget.controller.mouseInteraction || size.isEmpty) return;
    _model.targetMouse = Offset(event.localPosition.dx, event.localPosition.dy);
    _model.mouseActive = true;
    if (!widget.animationEnabled) _repaint.tick();
  }

  void _exit(PointerExitEvent event) {
    _model.mouseActive = false;
    if (!widget.animationEnabled) _repaint.tick();
  }

  void _dragStart(DragStartDetails details) {
    _model.dragging = true;
    _model.lastDrag = details.localPosition;
  }

  void _dragUpdate(DragUpdateDetails details) {
    _model.targetYaw += details.delta.dx * 0.005;
    _model.targetPitch = (_model.targetPitch + details.delta.dy * 0.005)
        .clamp(-1.2, 1.2)
        .toDouble();
  }

  void _dragEnd(DragEndDetails details) => _model.dragging = false;

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      return MouseRegion(
        cursor: SystemMouseCursors.grab,
        onHover: (event) => _hover(event, size),
        onExit: _exit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _dragStart,
          onPanUpdate: _dragUpdate,
          onPanEnd: _dragEnd,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _HtmlCorePainter(
                model: _model,
                controller: widget.controller,
                particleDensity: widget.particleDensity,
                repaint: _repaint,
              ),
            ),
          ),
        ),
      );
    },
  );
}

final class _FrameSignal extends ChangeNotifier {
  void tick() => notifyListeners();
}

final class _StateParams {
  const _StateParams({
    required this.radius,
    required this.breathe,
    required this.flow,
    required this.turb,
    required this.asym,
    required this.irregular,
    required this.speak,
    required this.rotate,
    required this.bright,
  });

  final double radius;
  final double breathe;
  final double flow;
  final double turb;
  final double asym;
  final double irregular;
  final double speak;
  final double rotate;
  final double bright;
}

const Map<AiCoreState, _StateParams> _stateParams = {
  AiCoreState.idle: _StateParams(
    radius: 1,
    breathe: 1,
    flow: 1,
    turb: .05,
    asym: 0,
    irregular: 0,
    speak: 0,
    rotate: 1,
    bright: 1,
  ),
  AiCoreState.listening: _StateParams(
    radius: 1.05,
    breathe: 1.4,
    flow: 1.2,
    turb: .07,
    asym: .05,
    irregular: 0,
    speak: 0,
    rotate: 1,
    bright: 1.06,
  ),
  AiCoreState.thinking: _StateParams(
    radius: 1,
    breathe: 1,
    flow: 2.1,
    turb: .09,
    asym: .11,
    irregular: 0,
    speak: 0,
    rotate: 1.15,
    bright: 1.02,
  ),
  AiCoreState.speaking: _StateParams(
    radius: 1.06,
    breathe: 1.3,
    flow: 1.8,
    turb: .12,
    asym: .10,
    irregular: 0,
    speak: 1,
    rotate: 1.1,
    bright: 1.14,
  ),
  AiCoreState.executing: _StateParams(
    radius: 1.08,
    breathe: 1.1,
    flow: 2.3,
    turb: .17,
    asym: .16,
    irregular: 0,
    speak: 0,
    rotate: 1.7,
    bright: 1.10,
  ),
  AiCoreState.success: _StateParams(
    radius: 1.16,
    breathe: 1,
    flow: 1.3,
    turb: .05,
    asym: 0,
    irregular: 0,
    speak: 0,
    rotate: 1,
    bright: 1.38,
  ),
  AiCoreState.error: _StateParams(
    radius: 1.02,
    breathe: 1,
    flow: 1.4,
    turb: .16,
    asym: .10,
    irregular: .20,
    speak: 0,
    rotate: 1,
    bright: 1,
  ),
};

final class _HtmlCoreModel {
  static const rows = 42;
  static const cols = 64;
  static const count = rows * cols;
  static const r0 = 2.15;

  final List<double> dirX = List<double>.filled(count, 0);
  final List<double> dirY = List<double>.filled(count, 0);
  final List<double> dirZ = List<double>.filled(count, 0);
  final List<double> polarA = List<double>.filled(count, 0);
  final List<double> azimA = List<double>.filled(count, 0);
  final List<double> phaseA = List<double>.filled(count, 0);
  final List<double> phaseB = List<double>.filled(count, 0);
  final List<double> colorR = List<double>.filled(count, 0);
  final List<double> colorG = List<double>.filled(count, 0);
  final List<double> colorB = List<double>.filled(count, 0);
  final List<double> offX = List<double>.filled(count, 0);
  final List<double> offY = List<double>.filled(count, 0);
  final List<_Projection> projections = List<_Projection>.generate(
    count,
    (_) => _Projection(),
  );

  AiCoreState targetState = AiCoreState.idle;
  _StateParams current = _stateParams[AiCoreState.idle]!;
  double time = 0;
  double yaw = .4;
  double pitch = -.15;
  double targetYaw = .4;
  double targetPitch = -.15;
  double zoom = 1;
  bool dragging = false;
  Offset lastDrag = Offset.zero;
  Offset targetMouse = Offset.zero;
  bool mouseActive = false;

  _HtmlCoreModel() {
    final golden = math.pi * (3 - math.sqrt(5));
    const p0 = [
      [0.4, 0.7, 1.0],
      [0.6, 0.85, 1.0],
      [0.5, 0.6, 1.0],
    ];
    for (var i = 0; i < count; i++) {
      final y = 1 - (i / (count - 1)) * 2;
      final rad = math.sqrt(math.max(0.0, 1 - y * y));
      final theta = golden * i;
      final x = math.cos(theta) * rad;
      final z = math.sin(theta) * rad;
      dirX[i] = x;
      dirY[i] = y;
      dirZ[i] = z;
      polarA[i] = math.acos(y.clamp(-1, 1));
      azimA[i] = math.atan2(z, x);
      phaseA[i] = _hash1(i * .913 + 4.7) * math.pi * 2;
      phaseB[i] = _hash1(i * 2.231 + 1.9) * math.pi * 2;
      final t = i / count;
      final pos = t * (p0.length - 1);
      final lo = pos.floor();
      final hi = math.min(p0.length - 1, lo + 1);
      final f = pos - lo;
      colorR[i] = p0[lo][0] + (p0[hi][0] - p0[lo][0]) * f;
      colorG[i] = p0[lo][1] + (p0[hi][1] - p0[lo][1]) * f;
      colorB[i] = p0[lo][2] + (p0[hi][2] - p0[lo][2]) * f;
    }
  }

  void setState(AiCoreState state) => targetState = state;

  void update(double dt, AiCoreController controller) {
    time += dt;
    final target = _stateParams[targetState]!;
    const rate = .035;
    current = _StateParams(
      radius: _lerp(current.radius, target.radius, rate),
      breathe: _lerp(current.breathe, target.breathe, rate),
      flow: _lerp(current.flow, target.flow, rate),
      turb: _lerp(current.turb, target.turb, rate),
      asym: _lerp(current.asym, target.asym, rate),
      irregular: _lerp(current.irregular, target.irregular, rate),
      speak: _lerp(current.speak, target.speak, rate),
      rotate: _lerp(current.rotate, target.rotate, rate),
      bright: _lerp(current.bright, target.bright, rate),
    );

    if (!dragging) targetYaw += .15 * current.rotate * .008;
    yaw += (targetYaw - yaw) * .08;
    pitch += (targetPitch - pitch) * .08;

    if (!controller.mouseInteraction) {
      mouseActive = false;
      targetMouse = Offset.zero;
    }
  }

  double projectMouseX(Size size) => targetMouse.dx;
  double projectMouseY(Size size) => targetMouse.dy;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

final class _Projection {
  double sx = 0;
  double sy = 0;
  double z = 0;
  double persp = 1;
  int index = 0;
}

final class _HtmlCorePainter extends CustomPainter {
  _HtmlCorePainter({
    required this.model,
    required this.controller,
    required this.particleDensity,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _HtmlCoreModel model;
  final AiCoreController controller;
  final double particleDensity;

  static const focal = 5.0;
  static const breathAmp = .05;
  static const breathFreq = .3;
  static const flowAmp = .05;
  static const flowRadialAmp = .02;
  static const flowSpeed = .15;
  static const repelRadius = 90.0;
  static const repelStrength = 46.0;
  static const repelFalloff = 35.0;
  static const repelEaseIn = .14;
  static const repelEaseOut = .05;
  static const rippleAmp = 1.4;
  static const rippleWavelength = 24.0;
  static const rippleSpeed = .006;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = model.time;
    final breathe =
        1 +
        math.sin(t * math.pi * 2 * breathFreq) *
            breathAmp *
            model.current.breathe;
    final cosY = math.cos(model.yaw), sinY = math.sin(model.yaw);
    final cosP = math.cos(model.pitch), sinP = math.sin(model.pitch);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scaleBase = math.min(size.width, size.height) / 6.5 * model.zoom;
    final flowT = t * model.current.flow;
    final errStep = (t * 6).floor();
    final mouseX = model.projectMouseX(size);
    final mouseY = model.projectMouseY(size);

    for (var i = 0; i < _HtmlCoreModel.count; i++) {
      final theta = model.polarA[i];
      final phi = model.azimA[i];
      final asym =
          model.current.asym *
          math.sin(phi * 2 + t * .22 + model.phaseA[i] * .15) *
          math.sin(theta * 1.4 - t * .15);
      final turb =
          model.current.turb *
          (.5 * math.sin(phi * 6 + t * .6 + model.phaseA[i]) +
              .5 * math.sin(theta * 8 - t * .9 + model.phaseB[i]));
      final irregular =
          model.current.irregular * (_hash1(i * 3.1 + errStep) - .5) * 2;

      var speakMod = 0.0;
      if (model.current.speak > .001) {
        final rdx = model.dirX[i] * cosY - model.dirZ[i] * sinY;
        final rdz = model.dirX[i] * sinY + model.dirZ[i] * cosY;
        final frontAmt = 1 - (rdz + 1) * .5;
        final depthGain = .7 + .45 * frontAmt;
        final env = _speechEnvelope(t * 1.15 + phi * .18 + theta * .09);
        final regional = math.sin(rdx * 2.6 - t * 1.8 + model.phaseA[i] * .12);
        final phraseWave = .5 + .5 * math.sin(phi * .9 + t * .35);
        final microWave = .5 + .5 * math.sin(model.phaseB[i] + t * 9);
        speakMod =
            model.current.speak *
            .16 *
            depthGain *
            (.30 * env.phrase * phraseWave +
                .45 * env.syllable * (.5 + .5 * regional) +
                .25 * env.micro * microWave);
      }

      final radiusMult = 1 + asym + turb + irregular + speakMod;
      final r = _HtmlCoreModel.r0 * model.current.radius * radiusMult;
      var x = model.dirX[i] * r;
      var y = model.dirY[i] * r;
      var z = model.dirZ[i] * r;

      final swirl = math.sin(flowT * flowSpeed + theta * 1.6) * flowAmp;
      x += -model.dirZ[i] * swirl;
      z += model.dirX[i] * swirl;
      final radial = math.sin(flowT * flowSpeed * .7 + phi * 2) * flowRadialAmp;
      x += model.dirX[i] * radial;
      y += model.dirY[i] * radial;
      z += model.dirZ[i] * radial;

      x *= breathe;
      y *= breathe;
      z *= breathe;

      final x1 = x * cosY - z * sinY;
      final z1 = x * sinY + z * cosY;
      final y1 = y * cosP - z1 * sinP;
      final z2 = y * sinP + z1 * cosP;
      final persp = focal / (focal + z2);
      var sx = cx + x1 * scaleBase * persp;
      var sy = cy + y1 * scaleBase * persp;

      var tx = 0.0;
      var ty = 0.0;
      if (model.mouseActive) {
        final dx = sx - mouseX;
        final dy = sy - mouseY;
        final dist = math.sqrt(dx * dx + dy * dy);
        final outer = repelRadius + repelFalloff;
        if (dist < outer && dist > .001) {
          final n = dist / outer;
          final falloff = 1 - n * n * (3 - 2 * n);
          final depthPush =
              .55 + .45 * ((persp - .7) / (1.35 - .7)).clamp(0, 1);
          final force = falloff * repelStrength * depthPush;
          tx = dx / dist * force;
          ty = dy / dist * force;
          final ripple =
              math.sin(dist / rippleWavelength - t * rippleSpeed * 1000) *
              rippleAmp *
              falloff;
          tx += dx / dist * ripple;
          ty += dy / dist * ripple;
        }
      }
      final targetMag = math.sqrt(tx * tx + ty * ty);
      final curMag = math.sqrt(
        model.offX[i] * model.offX[i] + model.offY[i] * model.offY[i],
      );
      final ease = targetMag > curMag ? repelEaseIn : repelEaseOut;
      model.offX[i] += (tx - model.offX[i]) * ease;
      model.offY[i] += (ty - model.offY[i]) * ease;
      sx += model.offX[i];
      sy += model.offY[i];

      final p = model.projections[i];
      p.sx = sx;
      p.sy = sy;
      p.z = z2;
      p.persp = persp;
      p.index = i;
    }

    model.projections.sort((a, b) => a.z.compareTo(b.z));

    final paint = Paint()..blendMode = BlendMode.plus;
    for (final p in model.projections) {
      final i = p.index;
      if (particleDensity < 1 && _hash1(i * 13.17 + 8.2) > particleDensity) {
        continue;
      }
      final depth = p.persp.clamp(.7, 1.35).toDouble();
      final depthT = (depth - .7) / (.65);
      final pointSize = (1.6 + math.sin(t * 2 + i * .01) * .3) * depth;
      final alpha = math
          .min(
            1.0,
            (.62 + .3 * depthT) * model.current.bright * controller.intensity,
          )
          .toDouble();
      paint.color = Color.fromRGBO(
        (model.colorR[i] * 255).round(),
        (model.colorG[i] * 255).round(),
        (model.colorB[i] * 255).round(),
        alpha,
      );
      canvas.drawCircle(
        Offset(p.sx, p.sy),
        math.max(.4, pointSize).toDouble(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HtmlCorePainter oldDelegate) => true;
}

({double phrase, double syllable, double micro, double total}) _speechEnvelope(
  double t,
) {
  final phrase = .5 + .5 * math.sin(t * .7 + math.sin(t * .13) * 2);
  final gate = phrase > .32 ? 1.0 : math.max(0.0, phrase / .32).toDouble();
  final syllable = math
      .max(0.0, math.sin(t * 3.1 + 1.7 + math.sin(t * .9 + .6) * 1.5))
      .toDouble();
  final micro = .5 + .5 * math.sin(t * 11 + 3.4);
  return (
    phrase: gate,
    syllable: syllable,
    micro: micro,
    total: gate * (.6 * syllable + .4 * micro),
  );
}

double _hash1(double n) {
  final x = math.sin(n * 127.1 + 311.7) * 43758.5453123;
  return x - x.floorToDouble();
}

