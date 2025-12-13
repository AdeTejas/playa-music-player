import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class TurntableBasePainter extends CustomPainter {
  final bool strobeEnabled;
  final Color strobeColor;
  final Color accentColor;

  TurntableBasePainter({
    required this.strobeEnabled,
    required this.strobeColor,
    required this.accentColor,
  });

  @override
  bool shouldRepaint(covariant TurntableBasePainter oldDelegate) =>
      oldDelegate.strobeEnabled != strobeEnabled ||
      oldDelegate.strobeColor != strobeColor ||
      oldDelegate.accentColor != accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. PLINTH (Main Chassis)
    final plinthRect = Rect.fromLTWH(w * 0.02, h * 0.02, w * 0.96, h * 0.96);
    final plinthRRect = RRect.fromRectAndRadius(
      plinthRect,
      Radius.circular(w * 0.04),
    );

    // Layout Constants - REFINED SCALES
    final platterRadius = w * 0.36;
    final platterCenter = Offset(
      w * 0.42,
      h * 0.45,
    ); // Slightly up-left to make room

    // Accent-driven "metallic paint" (Coruscant-inspired)
    final hsl = HSLColor.fromColor(accentColor);
    final c1 =
        hsl
            .withLightness((hsl.lightness * 1.08).clamp(0.0, 1.0))
            .withSaturation((hsl.saturation * 0.95).clamp(0.0, 1.0))
            .toColor();
    final c2 =
        hsl
            .withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0))
            .withSaturation((hsl.saturation * 1.00).clamp(0.0, 1.0))
            .toColor();
    final c3 =
        hsl
            .withLightness((hsl.lightness * 0.42).clamp(0.0, 1.0))
            .withSaturation((hsl.saturation * 1.05).clamp(0.0, 1.0))
            .toColor();

    final plinthPaint =
        Paint()
          ..shader = ui.Gradient.linear(
            plinthRect.topLeft,
            plinthRect.bottomRight,
            [c1, c2, c3],
            [0.0, 0.6, 1.0],
          );
    canvas.drawRRect(plinthRRect, plinthPaint);

    // Wood Grain - Enhanced
    canvas.save();
    canvas.clipRRect(plinthRRect);
    final grainPaint =
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15) // Darker grain
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;

    final rand = Random(42);
    // More dense grain
    for (double i = -w * 0.5; i < w * 1.5; i += w * 0.015) {
      final path = Path();
      path.moveTo(i, 0);
      // More waviness
      final x1 = i + (rand.nextDouble() - 0.5) * w * 0.15;
      final y1 = h * 0.33;
      final x2 = i + (rand.nextDouble() - 0.5) * w * 0.15;
      final y2 = h * 0.66;
      final x3 = i + (rand.nextDouble() - 0.5) * w * 0.1;
      final y3 = h;
      path.cubicTo(x1, y1, x2, y2, x3, y3);
      canvas.drawPath(path, grainPaint);
    }

    // Add subtle metallic flake/speckle for realism
    for (int i = 0; i < 1600; i++) {
      final t = rand.nextDouble();
      final noisePaint =
          Paint()
            ..color = Color.lerp(
              Colors.white,
              accentColor,
              t,
            )!.withValues(alpha: 0.02 + t * 0.05);
      canvas.drawCircle(
        Offset(rand.nextDouble() * w, rand.nextDouble() * h),
        0.5,
        noisePaint,
      );
    }
    canvas.restore();

    // 2. SPEAKER GRILL (Bottom Right)
    final speakerSize = w * 0.24;
    final speakerRect = Rect.fromLTWH(
      plinthRect.right - speakerSize - w * 0.05,
      plinthRect.bottom - speakerSize - w * 0.05,
      speakerSize,
      speakerSize,
    );

    // Grill Frame
    canvas.drawRRect(
      RRect.fromRectAndRadius(speakerRect, Radius.circular(w * 0.02)),
      Paint()..color = const Color(0xFF222222),
    );

    // Mesh Pattern
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        speakerRect.deflate(w * 0.01),
        Radius.circular(w * 0.01),
      ),
    );
    final meshPaint = Paint()..color = const Color(0xFF111111);
    canvas.drawRect(speakerRect, meshPaint);

    final dotPaint = Paint()..color = const Color(0xFF333333);
    final dotSpacing = w * 0.015;
    for (
      double dx = speakerRect.left;
      dx < speakerRect.right;
      dx += dotSpacing
    ) {
      for (
        double dy = speakerRect.top;
        dy < speakerRect.bottom;
        dy += dotSpacing
      ) {
        // Circular pattern mask
        if ((Offset(dx, dy) - speakerRect.center).distance <
            speakerSize * 0.42) {
          canvas.drawCircle(Offset(dx, dy), w * 0.004, dotPaint);
        }
      }
    }
    canvas.restore();

    // 3. TONEARM BASE PLATE (Right Side)
    final basePlateRect = Rect.fromCenter(
      center: Offset(w * 0.84, h * 0.38),
      width: w * 0.2,
      height: h * 0.55,
    );

    final basePlatePath = Path();
    basePlatePath.addRRect(
      RRect.fromRectAndRadius(basePlateRect, Radius.circular(w * 0.08)),
    );

    // Shadow
    canvas.drawPath(
      basePlatePath.shift(Offset(w * 0.01, w * 0.01)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Plate
    canvas.drawPath(
      basePlatePath,
      Paint()
        ..shader = ui.Gradient.linear(
          basePlateRect.topLeft,
          basePlateRect.bottomRight,
          [const Color(0xFF2A2A2A), const Color(0xFF111111)],
        ),
    );

    // Screws
    final screwR = w * 0.01;
    final screwP = Paint()..color = const Color(0xFF444444);
    canvas.drawCircle(
      basePlateRect.topCenter.translate(0, w * 0.04),
      screwR,
      screwP,
    );
    canvas.drawCircle(
      basePlateRect.bottomCenter.translate(0, -w * 0.04),
      screwR,
      screwP,
    );

    // Platter Rim (Static part)
    canvas.drawCircle(
      platterCenter,
      platterRadius,
      Paint()..color = const Color(0xFF181818),
    );

    // 5. DUST COVER HINGES (Top Edge)
    final hingePaint = Paint()..color = const Color(0xFF222222);
    final hingeDetailPaint = Paint()..color = const Color(0xFF444444);

    // Left Hinge
    final hingeL = Rect.fromCenter(
      center: Offset(w * 0.25, h * 0.03),
      width: w * 0.08,
      height: h * 0.04,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hingeL, const Radius.circular(2)),
      hingePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: hingeL.center, width: w * 0.06, height: h * 0.01),
      hingeDetailPaint,
    );

    // Right Hinge
    final hingeR = Rect.fromCenter(
      center: Offset(w * 0.75, h * 0.03),
      width: w * 0.08,
      height: h * 0.04,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hingeR, const Radius.circular(2)),
      hingePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: hingeR.center, width: w * 0.06, height: h * 0.01),
      hingeDetailPaint,
    );

    // 6. START/STOP LEVER BASE (Moved to Bottom Left, right of Knob)
    final leverBaseRect = Rect.fromCenter(
      center: Offset(w * 0.24, h * 0.88),
      width: w * 0.06,
      height: w * 0.1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(leverBaseRect, Radius.circular(w * 0.01)),
      Paint()..color = const Color(0xFF111111),
    );
    // Slot
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        leverBaseRect.deflate(w * 0.015),
        Radius.circular(w * 0.005),
      ),
      Paint()..color = const Color(0xFF000000),
    );

    // 7. RPM SWITCH BASE (Moved further left of Speaker)
    final rpmBaseRect = Rect.fromCenter(
      center: Offset(w * 0.60, h * 0.88),
      width: w * 0.08,
      height: w * 0.05,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rpmBaseRect, Radius.circular(w * 0.01)),
      Paint()..color = const Color(0xFF111111),
    );
    // Labels "33" and "45"
    canvas.drawCircle(
      rpmBaseRect.centerLeft.translate(w * 0.02, 0),
      2,
      Paint()..color = const Color(0xFF555555),
    );
    canvas.drawCircle(
      rpmBaseRect.centerRight.translate(-w * 0.02, 0),
      2,
      Paint()..color = const Color(0xFF555555),
    );

    // 8. POWER LIGHT BASE (Moved to Top Left)
    final powerLightPos = Offset(w * 0.08, h * 0.08);
    // Black Bezel
    canvas.drawCircle(
      powerLightPos,
      w * 0.025,
      Paint()..color = const Color(0xFF000000),
    );
    // Metal Ring
    canvas.drawCircle(
      powerLightPos,
      w * 0.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF444444),
    );
    // Bulb (Off state)
    canvas.drawCircle(
      powerLightPos,
      w * 0.015,
      Paint()..color = const Color(0xFF002200),
    );
  }
}

class TurntableSpinnerPainter extends CustomPainter {
  final double progress;
  final double discAngle;
  final double velocity; // 0.0 to 1.0
  final Color strobeColor;
  final double knobAngle;
  final ui.Image? labelImage;
  final bool strobeEnabled;
  final bool is33RPM;
  final bool isPlaying;
  final Color accentColor;

  TurntableSpinnerPainter({
    required this.progress,
    required this.discAngle,
    this.velocity = 1.0,
    this.strobeColor = const Color(0xFF00FF00),
    this.knobAngle = 0.0,
    this.labelImage,
    this.strobeEnabled = true,
    this.is33RPM = true,
    this.isPlaying = false,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Layout Constants - MUST MATCH BASE PAINTER
    final platterRadius = w * 0.36;
    final platterCenter = Offset(w * 0.42, h * 0.45);

    // SPINNING PLATTER & VINYL
    // 1. Draw Vinyl & Grooves (Rotated)
    canvas.save();
    canvas.translate(platterCenter.dx, platterCenter.dy);
    canvas.rotate(discAngle);
    canvas.translate(-platterCenter.dx, -platterCenter.dy);

    // 0. Strobe Dots (On the Platter Rim)
    if (strobeEnabled) {
      const dotCount = 60; // 60Hz strobe
      final dotRadius = w * 0.004;
      // Reduced contrast to prevent dizziness
      final dotPaint = Paint()..color = const Color(0xFF666666);

      for (int i = 0; i < dotCount; i++) {
        final angle = (i / dotCount) * 2 * pi;
        final dx = platterCenter.dx + cos(angle) * (platterRadius * 0.98);
        final dy = platterCenter.dy + sin(angle) * (platterRadius * 0.98);
        canvas.drawCircle(Offset(dx, dy), dotRadius, dotPaint);
      }
    }

    final recordR = platterRadius * 0.96; // Full size

    // Authentic Vinyl Color
    const vinylColor = Color(0xFF0A0A0A);
    canvas.drawCircle(platterCenter, recordR, Paint()..color = vinylColor);

    // Vinyl grooves
    for (double r = recordR * 0.35; r < recordR * 0.95; r += 2.0) {
      canvas.drawCircle(
        platterCenter,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = Colors.white.withValues(alpha: 0.04),
      );
    }
    canvas.restore(); // End rotation for Vinyl

    // 2. Specular highlight - Anisotropic "V" shape reflection (STATIONARY)
    // Drawn outside the rotation block so it doesn't spin with the record
    const lightAngle = -0.8;
    const shimmerCount = 2;

    for (int i = 0; i < shimmerCount; i++) {
      final angleOffset = (i == 0 ? 0 : pi);
      final shimmerAngle = lightAngle + angleOffset;

      final path = Path();
      path.moveTo(platterCenter.dx, platterCenter.dy);
      path.arcTo(
        Rect.fromCircle(center: platterCenter, radius: recordR),
        shimmerAngle - 0.35,
        0.7,
        false,
      );
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.radial(
            platterCenter,
            recordR,
            [Colors.white.withValues(alpha: 0.12), Colors.transparent],
            [0.0, 1.0],
          )
          ..blendMode = BlendMode.plus,
      );
    }

    // 3. Label (Rotated)
    canvas.save();
    canvas.translate(platterCenter.dx, platterCenter.dy);
    canvas.rotate(discAngle);
    canvas.translate(-platterCenter.dx, -platterCenter.dy);

    // LABEL
    final labelR = platterRadius * 0.44;
    final labelHsl = HSLColor.fromColor(accentColor);
    final labelColor =
        labelHsl
            .withLightness((labelHsl.lightness * 0.88).clamp(0.0, 1.0))
            .withSaturation((labelHsl.saturation * 0.20).clamp(0.0, 1.0))
            .toColor();
    canvas.drawCircle(platterCenter, labelR, Paint()..color = labelColor);

    if (labelImage != null) {
      canvas.save();
      final labelPath =
          Path()
            ..addOval(Rect.fromCircle(center: platterCenter, radius: labelR));
      canvas.clipPath(labelPath);

      final imgSize = Size(
        labelImage!.width.toDouble(),
        labelImage!.height.toDouble(),
      );
      double srcW = imgSize.width;
      double srcH = imgSize.height;
      double srcX = 0;
      double srcY = 0;

      if (srcW > srcH) {
        srcX = (srcW - srcH) / 2;
        srcW = srcH;
      } else {
        srcY = (srcH - srcW) / 2;
        srcH = srcW;
      }

      canvas.drawImageRect(
        labelImage!,
        Rect.fromLTWH(srcX, srcY, srcW, srcH),
        Rect.fromCircle(center: platterCenter, radius: labelR),
        Paint(),
      );
      canvas.restore();
    }

    // Label Hole (Spindle Hole) - Larger to be visible
    canvas.drawCircle(
      platterCenter,
      labelR * 0.15,
      Paint()..color = const Color(0xFF050505),
    );

    canvas.restore(); // Restore from spinning vinyl rotation

    // SPINDLE - Chrome Reflection
    final spindleR = platterRadius * 0.025;
    canvas.drawCircle(
      platterCenter,
      spindleR,
      Paint()
        ..shader = ui.Gradient.linear(
          platterCenter.translate(-spindleR, -spindleR),
          platterCenter.translate(spindleR, spindleR),
          [const Color(0xFF888888), Colors.white, const Color(0xFF888888)],
          [0.0, 0.5, 1.0],
        ),
    );
    // Spindle Top Highlight
    canvas.drawCircle(
      platterCenter.translate(-spindleR * 0.3, -spindleR * 0.3),
      spindleR * 0.3,
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );

    // KNOB (Bottom Left)
    final knobCenter = Offset(w * 0.12, h * 0.88);
    final knobR = w * 0.07; // Slightly larger

    // Knob Shadow
    canvas.drawCircle(
      knobCenter.translate(2, 2),
      knobR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Knob Body (Knurled texture hint)
    canvas.drawCircle(
      knobCenter,
      knobR,
      Paint()
        ..shader = ui.Gradient.radial(knobCenter, knobR, [
          const Color(0xFF222222),
          const Color(0xFF000000),
        ]),
    );

    // Knob Indicator
    final kAngle = -pi / 4 + knobAngle; // Start at 7 o'clock ish
    canvas.drawLine(
      knobCenter,
      knobCenter + Offset(cos(kAngle) * knobR * 0.8, sin(kAngle) * knobR * 0.8),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // START/STOP LEVER HANDLE (Moved to Bottom Left, right of Knob)
    final leverBaseCenter = Offset(w * 0.24, h * 0.88);
    final leverOffset =
        isPlaying ? w * 0.02 : -w * 0.02; // Down = Play, Up = Stop
    final leverHandleRect = Rect.fromCenter(
      center: leverBaseCenter.translate(0, leverOffset),
      width: w * 0.04,
      height: w * 0.02,
    );

    // Lever Shaft
    canvas.drawRect(
      Rect.fromCenter(
        center: leverBaseCenter,
        width: w * 0.01,
        height: w * 0.06,
      ),
      Paint()..color = const Color(0xFF111111),
    );

    // Lever Knob (Chrome)
    canvas.drawRRect(
      RRect.fromRectAndRadius(leverHandleRect, const Radius.circular(2)),
      Paint()
        ..shader = ui.Gradient.linear(
          leverHandleRect.topLeft,
          leverHandleRect.bottomRight,
          [
            const Color(0xFFFFFFFF),
            const Color(0xFFAAAAAA),
            const Color(0xFF555555),
          ],
          [0.0, 0.5, 1.0],
        ),
    );

    // RPM SWITCH HANDLE (Moved further left)
    final rpmBaseCenter = Offset(w * 0.60, h * 0.88);
    final rpmOffset = is33RPM ? -w * 0.02 : w * 0.02; // Left = 33, Right = 45
    final rpmHandleRect = Rect.fromCenter(
      center: rpmBaseCenter.translate(rpmOffset, 0),
      width: w * 0.02,
      height: w * 0.04,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rpmHandleRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFFCCCCCC),
    );

    // POWER LIGHT GLOW (Top Left)
    final powerLightPos = Offset(w * 0.08, h * 0.08);

    // Intensity based on velocity (fades out as it stops)
    final intensity = velocity.clamp(0.0, 1.0);

    if (intensity > 0.01) {
      final glowColor =
          Color.lerp(
            const Color(0xFF003300),
            const Color(0xFF00FF00),
            intensity,
          )!;

      // Glow
      canvas.drawCircle(
        powerLightPos,
        w * 0.025 * intensity,
        Paint()
          ..shader = ui.Gradient.radial(powerLightPos, w * 0.03, [
            glowColor.withValues(alpha: 0.8 * intensity),
            Colors.transparent,
          ])
          ..blendMode = BlendMode.plus,
      );

      // Bulb Center
      canvas.drawCircle(
        powerLightPos,
        w * 0.015,
        Paint()..color = glowColor.withValues(alpha: intensity),
      );
    }

    // ================= TONEARM (STRAIGHT ARM) =================

    // 1. Pivot Position (Matches Base Plate Center)
    final pivot = Offset(w * 0.84, h * 0.38);

    // Calculate arm length to reach spindle + overhang
    final pivotToSpindle = (platterCenter - pivot).distance;
    final armLength = pivotToSpindle + (w * 0.04); // Overhang

    // 2. Stylus Position Logic
    // recordR is already defined above
    final restingRadius = recordR * 0.98;
    final finalRadius = recordR * 0.35;
    final animatedRadius =
        ui.lerpDouble(restingRadius, finalRadius, progress.clamp(0.0, 1.0))!;

    final d = pivotToSpindle;
    Offset stylusPos;

    if (d > armLength + animatedRadius ||
        d < (armLength - animatedRadius).abs()) {
      // Resting position
      final restingAngle =
          atan2(platterCenter.dy - pivot.dy, platterCenter.dx - pivot.dx) - 0.4;
      stylusPos = pivot + Offset.fromDirection(restingAngle, armLength);
    } else {
      // Intersection
      final a =
          (d * d - animatedRadius * animatedRadius + armLength * armLength) /
          (2 * d);
      final hIntersect = sqrt(max(0, armLength * armLength - a * a));
      final p2 = pivot + (platterCenter - pivot) * (a / d);

      final x3 = p2.dx + hIntersect * (platterCenter.dy - pivot.dy) / d;
      final y3 = p2.dy - hIntersect * (platterCenter.dx - pivot.dx) / d;
      stylusPos = Offset(x3, y3);
    }

    final armAngle = atan2(stylusPos.dy - pivot.dy, stylusPos.dx - pivot.dx);
    final lift = 1 - Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    final liftOffset = Offset(0, -lift * 8);

    // DYNAMIC TONEARM SHADOW
    // Shadow offset depends on lift height
    final shadowOffset = const Offset(4, 4) + Offset(lift * 10, lift * 10);

    canvas.drawLine(
      pivot.translate(shadowOffset.dx, shadowOffset.dy),
      stylusPos.translate(shadowOffset.dx, shadowOffset.dy),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..strokeWidth = w * 0.015
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // VINYL REFLECTION (Subtle reflection of arm on the record)
    canvas.save();
    // Clip to vinyl area
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: platterCenter, radius: recordR)),
    );

    // Draw reflection (mirrored or just projected)
    // Simple projection: Draw arm again with low opacity and blur
    canvas.drawLine(
      pivot,
      stylusPos,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = w * 0.015
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();

    // GIMBAL / PIVOT ASSEMBLY
    // Main Pivot Cylinder
    canvas.drawCircle(
      pivot,
      w * 0.05,
      Paint()
        ..shader = ui.Gradient.linear(
          pivot.translate(-10, -10),
          pivot.translate(10, 10),
          [const Color(0xFF333333), const Color(0xFF111111)],
        ),
    );

    // Anti-Skate Knob (Small dial next to pivot)
    final antiSkatePos = pivot.translate(w * 0.06, w * 0.02);
    canvas.drawCircle(
      antiSkatePos,
      w * 0.015,
      Paint()..color = const Color(0xFF222222),
    );
    canvas.drawLine(
      antiSkatePos,
      antiSkatePos.translate(0, -w * 0.01),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1,
    );

    // Yoke (U-shape holding the arm)
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(armAngle);

    // Counterweight Shaft
    canvas.drawRect(
      Rect.fromLTWH(-w * 0.12, -4, w * 0.12, 8),
      Paint()..color = const Color(0xFF222222),
    );

    // Counterweight (Detailed)
    final cwRect = Rect.fromCenter(
      center: Offset(-w * 0.1, 0),
      width: w * 0.08,
      height: w * 0.08,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(cwRect, const Radius.circular(4)),
      Paint()
        ..shader = ui.Gradient.linear(cwRect.topLeft, cwRect.bottomRight, [
          const Color(0xFF444444),
          const Color(0xFF111111),
        ]),
    );
    // Counterweight Dial Markings
    canvas.drawLine(
      Offset(-w * 0.1, -w * 0.03),
      Offset(-w * 0.1, w * 0.03),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    canvas.restore();

    // ARM TUBE (Straight Silver)
    canvas.drawLine(
      pivot,
      stylusPos.translate(liftOffset.dx, liftOffset.dy),
      Paint()
        ..shader = ui.Gradient.linear(
          pivot,
          stylusPos,
          [
            const Color(0xFFCCCCCC),
            const Color(0xFFEEEEEE),
            const Color(0xFFCCCCCC),
          ],
          [0.0, 0.5, 1.0],
        )
        ..strokeWidth = w * 0.015
        ..strokeCap = StrokeCap.butt,
    );

    // HEADSHELL (Angled with MCRN Details)
    canvas.save();
    canvas.translate(
      stylusPos.dx + liftOffset.dx,
      stylusPos.dy + liftOffset.dy,
    );
    canvas.rotate(armAngle + 0.4); // Offset angle for headshell

    // Headshell shape (Reverted to original angled design)
    final headshellPath =
        Path()
          ..moveTo(-w * 0.015, -w * 0.02)
          ..lineTo(w * 0.08, -w * 0.015)
          ..lineTo(w * 0.08, w * 0.015)
          ..lineTo(-w * 0.015, w * 0.02)
          ..close();

    // Main Body (Dark Grey)
    canvas.drawPath(headshellPath, Paint()..color = const Color(0xFF1A1A1A));

    // MCRN Orange Stripe
    const mcrnOrange = Color(0xFFFF5722);
    canvas.drawLine(
      Offset(w * 0.02, -w * 0.015),
      Offset(w * 0.02, w * 0.015),
      Paint()
        ..color = mcrnOrange
        ..strokeWidth = w * 0.005,
    );

    // "ECF 270" Text (Tiny technical marking)
    final textSpan = TextSpan(
      text: "ECF 270",
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: w * 0.008,
        fontWeight: FontWeight.bold,
        fontFamily: "Roboto",
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    // Rotate text to align with headshell
    canvas.save();
    canvas.translate(w * 0.03, -w * 0.005);
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();

    // Finger lift
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.05, 0)
        ..quadraticBezierTo(w * 0.1, w * 0.02, w * 0.12, -w * 0.04),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF111111),
    );

    // Cartridge (Red tip)
    canvas.drawRect(
      Rect.fromLTWH(w * 0.02, -w * 0.01, w * 0.04, w * 0.02),
      Paint()..color = const Color(0xFF333333),
    );
    canvas.drawCircle(
      Offset(w * 0.05, 0),
      w * 0.005,
      Paint()..color = Colors.red,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TurntableSpinnerPainter oldDelegate) =>
      discAngle != oldDelegate.discAngle ||
      isPlaying != oldDelegate.isPlaying ||
      is33RPM != oldDelegate.is33RPM ||
      progress != oldDelegate.progress ||
      labelImage != oldDelegate.labelImage;
}
