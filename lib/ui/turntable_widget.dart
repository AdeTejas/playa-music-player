import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../services/player_controller.dart';
import '../services/artwork_cache_service.dart';
import '../services/settings_service.dart';
import 'high_tech_speaker.dart';

class TurntableDeck extends StatefulWidget {
  final PlayerController ctrl;
  final MediaItem? item;
  final bool isVisible; // CEO-Mandated Performance Flag

  const TurntableDeck({
    required this.ctrl,
    this.item,
    this.isVisible = true,
    super.key,
  });

  @override
  State<TurntableDeck> createState() => _TurntableDeckState();
}

class _TurntableDeckState extends State<TurntableDeck>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  StreamSubscription<bool>? _playingSub;

  // Physics state
  double _discAngle = 0.0;
  double _platterAngle = 0.0;
  double _slipOffset = 0.0; // record angle relative to platter
  double _angularVelocity = 0.0; // 0.0 to 1.0 (1.0 = 33.3 RPM)
  double _targetVelocity = 0.0;

  // Interaction state
  double _dragVelocity = 0.0;
  bool _isDragging = false;
  bool _isDraggingArm = false;
  double? _lastDragAngle;
  Duration? _dragPosition;
  int _lastSeekAtMs = 0;
  Duration? _pendingSeek;

  double? _armProgressOverride;
  bool _wasPlayingBeforeArmDrag = false;

  // Pitch Control State
  bool _isTurningKnob = false;
  double _pitchValue = 1.0; // 1.0 = normal speed
  double? _lastKnobAngle;
  double? _lastPitchDetent;

  // RPM State
  bool _is33RPM = true;

  // Strobe Light State
  final bool _strobeEnabled = true;

  // Cue lever / tonearm lift (0 = down, 1 = up)
  double _cueLift = 1.0;
  double _cueTarget = 1.0;
  bool _cueMoving = false;
  bool _pendingPlayAfterCue = false;
  bool _pendingPauseAfterCue = false;

  // Label Image State
  ui.Image? _labelImage;
  ui.Image? _generatedLabelImage;
  String? _generatedLabelKey;

  ui.Image? _dustImage;
  int? _dustImageSize;
  int? _dustSeed;
  bool _dustGenerating = false;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  // Constants
  static const double _kMaxRPM = 33.3333;
  static const double _kRadPerSecond =
      (_kMaxRPM * 2 * pi) / 60.0; // real angular speed per second

  Duration? _lastTickTime;
  double _beatPulse = 0.0;
  double _tonearmPulse = 0.0;
  double _groovePulse = 0.0;
  double _neuralPhase = 0.0;
  double _currentBpm = 120.0;
  bool _neuralMixActive = false;
  VoidCallback? _neuralMixListener;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.isVisible) {
      _ticker.start();
    }

    _cueLift = widget.ctrl.player.playing ? 0.0 : 1.0;
    _cueTarget = _cueLift;

    _updateBpmFromItem();
    _neuralMixListener = () {
      final active = widget.ctrl.neuralMixActiveNotifier.value;
      if (active != _neuralMixActive) {
        setState(() => _neuralMixActive = active);
      }
    };
    widget.ctrl.neuralMixActiveNotifier.addListener(_neuralMixListener!);

    // Listen to playback state for motor control
    _playingSub = widget.ctrl.player.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() {
        _targetVelocity = playing ? 1.0 : 0.0;
        // Keep cue position in sync with external play/pause, but don't
        // interrupt an in-flight lever/arm action.
        if (!_cueMoving) {
          _cueTarget = playing ? 0.0 : 1.0;
          _cueMoving = true;
          if (playing) {
            HapticFeedback.selectionClick();
          } else {
            HapticFeedback.lightImpact();
          }
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-initialize the ticker if it's not active and should be
    if (widget.isVisible && !_ticker.isActive) {
      _ticker.start();
    }
    _updateLabelImage();
  }

  @override
  void didUpdateWidget(TurntableDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item != oldWidget.item) {
      _updateLabelImage();
      _updateBpmFromItem();
    }

    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        if (!_ticker.isActive) _ticker.start();
      } else {
        if (_ticker.isActive) _ticker.stop();
      }
    }
  }

  void _updateBpmFromItem() {
    final extras = widget.item?.extras;
    final bpm = (extras?['bpm'] as num?)?.toDouble();
    if (bpm != null && bpm > 0 && bpm != _currentBpm) {
      if (mounted) {
        setState(() => _currentBpm = bpm);
      } else {
        _currentBpm = bpm;
      }
    }
  }

  Future<void> _updateLabelImage() async {
    final item = widget.item;

    // Target size for the label (optimization)
    const int targetSize = 300;

    final imageConfig = createLocalImageConfiguration(context);

    // 1. Try to get image from song ID (Android MediaStore)
    if (item?.extras != null && item!.extras!.containsKey('songId')) {
      try {
        // OnAudioQuery.queryArtwork is not supported on Windows/Linux; skip step 1.
        if (!(Platform.isWindows || Platform.isLinux)) {
          final songId = item.extras!['songId'] as int;
          final bytes = await ArtworkCacheService.instance.getArtworkBytes(
            id: songId,
            type: oaq.ArtworkType.AUDIO,
            size: 400,
            format: oaq.ArtworkFormat.JPEG,
          );

          if (bytes != null && bytes.isNotEmpty) {
            // OPTIMIZATION: Decode image to specific dimensions to save RAM and GPU texture memory
            final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
            final descriptor = await ui.ImageDescriptor.encoded(buffer);
            final codec = await descriptor.instantiateCodec(
              targetWidth: targetSize,
              targetHeight: targetSize,
            );
            final frame = await codec.getNextFrame();

            if (mounted) {
              setState(() {
                _labelImage = frame.image;
                _generatedLabelImage = null;
                _generatedLabelKey = null;
              });
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('Error loading artwork from ID: $e');
      }
    }

    // 2. Fallback to URI if available
    if (item?.artUri != null) {
      final uri = item!.artUri!;
      ImageProvider? provider;

      if (uri.scheme.startsWith('http')) {
        provider = NetworkImage(uri.toString());
      } else if (uri.scheme == 'file') {
        provider = FileImage(File.fromUri(uri));
      } else {
        // content:// or other schemes are not supported by FileImage
        // On Android, OnAudioQuery (Step 1) should have handled it.
        // If we are here, it means Step 1 failed or didn't apply.
        // We can't easily load content:// as ImageProvider without a plugin or custom loader.
        // So we skip to avoid crash.
      }

      if (provider != null) {
        final oldStream = _imageStream;
        _imageStream = provider.resolve(imageConfig);

        if (_imageStream!.key != oldStream?.key) {
          final listener = ImageStreamListener(
            (info, _) {
              if (mounted) {
                setState(() {
                  _labelImage = info.image;
                  _generatedLabelImage = null;
                  _generatedLabelKey = null;
                });
              }
            },
            onError: (exception, stackTrace) {
              debugPrint('Error loading label image: $exception');
            },
          );
          _imageListener = listener;
          _imageStream!.addListener(listener);
        }
        return;
      }
    }

    // 3. No image found
    if (_labelImage != null) {
      setState(() => _labelImage = null);
    }
    await _updateGeneratedLabelImage(targetSize: targetSize);
  }

  Future<void> _updateGeneratedLabelImage({required int targetSize}) async {
    final item = widget.item;
    if (item == null) {
      if (_generatedLabelImage != null) {
        setState(() {
          _generatedLabelImage = null;
          _generatedLabelKey = null;
        });
      }
      return;
    }
    if (_labelImage != null) {
      if (_generatedLabelImage != null) {
        setState(() {
          _generatedLabelImage = null;
          _generatedLabelKey = null;
        });
      }
      return;
    }

    final settings = SettingsService.instance;
    final accent = Color(settings.accentColor);
    final key = '${item.id}|${item.title}|${item.artist}|${accent.toARGB32()}';
    if (_generatedLabelKey == key && _generatedLabelImage != null) return;

    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    final sz = Size(targetSize.toDouble(), targetSize.toDouble());
    final center = sz.center(Offset.zero);
    final r = sz.width * 0.48;

    final seed = (item.title.hashCode) ^ (item.artist?.hashCode ?? 0);
    final rand = Random(seed);

    final hsl = HSLColor.fromColor(accent);
    final bg =
        hsl
            .withSaturation((hsl.saturation * 0.18).clamp(0.0, 1.0))
            .withLightness((hsl.lightness * 0.78).clamp(0.0, 1.0))
            .toColor();
    final ring1 =
        hsl
            .withSaturation((hsl.saturation * 0.28).clamp(0.0, 1.0))
            .withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0))
            .toColor();
    final ring2 =
        hsl
            .withSaturation((hsl.saturation * 0.22).clamp(0.0, 1.0))
            .withLightness((hsl.lightness * 0.52).clamp(0.0, 1.0))
            .toColor();

    c.drawCircle(center, r, Paint()..color = bg);

    // Radial stripes
    final stripePaint =
        Paint()
          ..color = Colors.black.withValues(alpha: 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    for (int i = 0; i < 28; i++) {
      final a = (i / 28) * 2 * pi + rand.nextDouble() * 0.02;
      final p1 = center + Offset(cos(a) * (r * 0.18), sin(a) * (r * 0.18));
      final p2 = center + Offset(cos(a) * (r * 0.95), sin(a) * (r * 0.95));
      c.drawLine(p1, p2, stripePaint);
    }

    // Rings
    c.drawCircle(
      center,
      r * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08
        ..color = ring1.withValues(alpha: 0.55),
    );
    c.drawCircle(
      center,
      r * 0.48,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = ring2.withValues(alpha: 0.55),
    );

    // Speckle print texture
    final speckle = Paint()..color = Colors.white.withValues(alpha: 0.08);
    for (int i = 0; i < 220; i++) {
      final rr = r * sqrt(rand.nextDouble());
      final aa = rand.nextDouble() * 2 * pi;
      final p = center + Offset(cos(aa) * rr, sin(aa) * rr);
      c.drawCircle(p, 0.8 + rand.nextDouble() * 1.3, speckle);
    }

    // Center title block
    final title = (item.title).trim();
    final artist = (item.artist ?? '').trim();
    final titleText = title.isEmpty ? 'UNKNOWN' : title;
    final artistText = artist.isEmpty ? '' : artist;

    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.textAlign = TextAlign.center;
    tp.text = TextSpan(
      text: titleText,
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.75),
        fontSize: r * 0.13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
    tp.layout(maxWidth: r * 1.35);
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height * 0.8));

    if (artistText.isNotEmpty) {
      final ap = TextPainter(textDirection: TextDirection.ltr);
      ap.textAlign = TextAlign.center;
      ap.text = TextSpan(
        text: artistText,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.62),
          fontSize: r * 0.09,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      );
      ap.layout(maxWidth: r * 1.25);
      ap.paint(c, Offset(center.dx - ap.width / 2, center.dy + r * 0.06));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(targetSize, targetSize);
    if (!mounted) return;
    setState(() {
      _generatedLabelImage = img;
      _generatedLabelKey = key;
    });
  }

  void _ensureDustTexture({required int size, required int seed}) {
    final needsRegen =
        _dustImage == null || _dustImageSize != size || _dustSeed != seed;
    if (!needsRegen || _dustGenerating) return;

    _dustImageSize = size;
    _dustSeed = seed;
    _dustGenerating = true;

    // Run after this frame so we don't do heavy work during build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _generateDustTexture(size: size, seed: seed).whenComplete(() {
          if (mounted) {
            setState(() => _dustGenerating = false);
          }
        }),
      );
    });
  }

  Future<void> _generateDustTexture({
    required int size,
    required int seed,
  }) async {
    await Future<void>.delayed(Duration.zero);
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    final sz = Size(size.toDouble(), size.toDouble());
    final center = sz.center(Offset.zero);
    final r = sz.width * 0.5;

    final rand = Random(seed);

    // Transparent background
    c.drawRect(Offset.zero & sz, Paint()..color = Colors.transparent);

    // Smudges (soft radial fades)
    for (int i = 0; i < 6; i++) {
      final rr = r * (0.18 + rand.nextDouble() * 0.22);
      final a = rand.nextDouble() * 2 * pi;
      final p = center + Offset(cos(a) * r * 0.28, sin(a) * r * 0.28);
      final shader = ui.Gradient.radial(
        p,
        rr,
        [
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.0),
        ],
        [0.0, 1.0],
      );
      c.drawCircle(p, rr, Paint()..shader = shader);
    }

    // Dust specks
    final dustPaint = Paint()..color = Colors.white.withValues(alpha: 0.10);
    for (int i = 0; i < 700; i++) {
      final rr = r * sqrt(rand.nextDouble());
      final a = rand.nextDouble() * 2 * pi;
      final p = center + Offset(cos(a) * rr, sin(a) * rr);
      c.drawCircle(p, 0.35 + rand.nextDouble() * 0.75, dustPaint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    if (!mounted) return;
    setState(() => _dustImage = img);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final previous = _lastTickTime;
    _lastTickTime = elapsed;
    if (previous == null) {
      return; // Skip first frame until we have delta
    }

    double dt = (elapsed - previous).inMicroseconds / 1e6;
    if (dt <= 0) return;
    dt = dt.clamp(0.0, 0.1); // cap to avoid jumps after resume

    final disableAnimations =
        SchedulerBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;

    if (disableAnimations) {
      // Keep visuals alive but significantly slower.
      dt *= 0.18;
    }

    // Cue motion (lever-controlled tonearm lift)
    if (_cueMoving && !disableAnimations) {
      const cueRate = 3.2; // units per second
      final cueDelta = _cueTarget - _cueLift;
      final cueStep = cueRate * dt;
      if (cueDelta.abs() <= 0.002) {
        _cueLift = _cueTarget;
      } else {
        _cueLift += cueDelta.clamp(-cueStep, cueStep);
      }
      if ((_cueLift - _cueTarget).abs() <= 0.002) {
        _cueLift = _cueTarget;
        _cueMoving = false;

        if (_cueTarget <= 0.01 && _pendingPlayAfterCue) {
          _pendingPlayAfterCue = false;
          widget.ctrl.player.play();
        }
        if (_cueTarget >= 0.99 && _pendingPauseAfterCue) {
          _pendingPauseAfterCue = false;
          widget.ctrl.player.pause();
        }
      }
    } else if (disableAnimations) {
      // Snap for reduced motion.
      _cueLift = _cueTarget;
      _cueMoving = false;
      if (_cueTarget <= 0.01 && _pendingPlayAfterCue) {
        _pendingPlayAfterCue = false;
        widget.ctrl.player.play();
      }
      if (_cueTarget >= 0.99 && _pendingPauseAfterCue) {
        _pendingPauseAfterCue = false;
        widget.ctrl.player.pause();
      }
      _pendingPlayAfterCue = false;
      _pendingPauseAfterCue = false;
    }

    // Update progress for smooth animation
    final p = widget.ctrl.player;
    if (p.duration != null && p.duration!.inMilliseconds > 0) {
      // Authentic behavior: arm stays in run-out groove at end of record
      // until manually lifted back to rest. (No auto-return.)
      // if (p.processingState == ProcessingState.completed) {
      //   if (!_isDraggingArm && !_cueMoving) {
      //     _cueTarget = 1.0;
      //     _cueMoving = true;
      //     _pendingPlayAfterCue = false;
      //     _pendingPauseAfterCue = false;
      //     _armProgressOverride = null;
      //     _dragPosition = null;
      //   }
      // }
    } else {}

    // 1) Motor model: separate accel / brake, plus tiny wow/flutter drift.
    final rpmMult = _is33RPM ? 1.0 : 1.35;
    final baseTarget = _targetVelocity * _pitchValue * rpmMult;

    final seconds = elapsed.inMicroseconds / 1e6;
    final wowFlutter =
        (!disableAnimations && widget.ctrl.player.playing)
            ? (0.0022 * sin(seconds * 2 * pi * 0.70) +
                0.0015 *
                    sin(seconds * 2 * pi * 6.40 + sin(seconds * 2 * pi * 0.85)))
            : 0.0;
    final drift =
        (!disableAnimations && widget.ctrl.player.playing)
            ? (0.0009 * sin(seconds * 2 * pi * 0.08))
            : 0.0;

    final target = (baseTarget + wowFlutter + drift).clamp(0.0, 1.1);

    final delta = target - _angularVelocity;
    const accelRate = 3.2; // per-second normalized spin-up
    const brakeRate = 6.0; // per-second normalized spin-down
    final rate = delta >= 0 ? accelRate : brakeRate;
    final step = rate * dt;
    if (delta.abs() > 0.0005) {
      _angularVelocity += delta.clamp(-step, step);
    } else {
      _angularVelocity = target;
    }

    // 2) Update platter rotation (always motor-driven).
    if (_angularVelocity.abs() > 0.0005 || widget.ctrl.player.playing) {
      _platterAngle += _kRadPerSecond * _angularVelocity * dt;
      if (_platterAngle > 2 * pi) _platterAngle -= 2 * pi;
      if (_platterAngle < 0) _platterAngle += 2 * pi;
    }

    double wrapAngle(double a) {
      var v = a;
      while (v > pi) {
        v -= 2 * pi;
      }
      while (v < -pi) {
        v += 2 * pi;
      }
      return v;
    }

    // 3) Slipmat model: record can slip while dragging; otherwise it re-catches.
    if (_isDragging && !_isTurningKnob) {
      setState(() {
        _discAngle += _dragVelocity * dt * 6.0;
        if (_discAngle > 2 * pi) _discAngle -= 2 * pi;
        if (_discAngle < 0) _discAngle += 2 * pi;
        _slipOffset = wrapAngle(_discAngle - _platterAngle);
      });
      _dragVelocity *= 0.9;
    } else {
      // Exponential catch-up back to platter.
      final catchFactor = 1.0 - exp(-4.2 * dt);
      _slipOffset += (0.0 - _slipOffset) * catchFactor;
      setState(() {
        _discAngle = _platterAngle + _slipOffset;
        if (_discAngle > 2 * pi) _discAngle -= 2 * pi;
        if (_discAngle < 0) _discAngle += 2 * pi;
      });
    }

    // Motion cues + pulses
    final bpm = _currentBpm.clamp(60.0, 220.0);
    final beatFreq = bpm / 60.0;
    _beatPulse =
        disableAnimations ? 0.0 : (sin(seconds * beatFreq * 2 * pi) + 1) / 2;
    _tonearmPulse =
        disableAnimations ? 0.0 : sin(seconds * beatFreq * pi * 0.35) * 0.012;
    if (_neuralMixActive) {
      _neuralPhase += dt * 4.0;
      _groovePulse = (sin(_neuralPhase) + 1) / 2;
    } else {
      _neuralPhase = 0.0;
      _groovePulse = 0.0;
    }
  }

  double _currentProgressFromPlayer() {
    final p = widget.ctrl.player;
    final dur = p.duration;
    if (dur == null || dur.inMilliseconds <= 0) return 0.0;
    return (p.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
  }

  Offset _stylusForProgress({
    required double w,
    required double h,
    required double progress,
  }) {
    final platterRadius = w * 0.33;
    final platterCenter = Offset(w * 0.42, h * 0.45);
    final recordR = platterRadius * 0.90;
    final pivot = Offset(w * 0.84, h * 0.38);

    final pivotToSpindle = (platterCenter - pivot).distance;
    final armLength = pivotToSpindle + (w * 0.04);

    // Resting angle just outside the lead-in.
    final restingAngle =
        atan2(platterCenter.dy - pivot.dy, platterCenter.dx - pivot.dx) - 0.4;
    final restingStylus = pivot + Offset.fromDirection(restingAngle, armLength);

    // When the cue is up, keep the arm in the resting position unless the
    // user is actively placing the needle.
    if (_cueLift >= 0.95 && !_isDraggingArm && _armProgressOverride == null) {
      return restingStylus;
    }

    // Groove radii (lead-in -> inner groove)
    final leadInRadius = recordR * 0.92;
    final finalRadius = recordR * 0.35;

    final animatedRadius =
        ui.lerpDouble(leadInRadius, finalRadius, progress.clamp(0.0, 1.0))!;

    final d = pivotToSpindle;
    if (d > armLength + animatedRadius ||
        d < (armLength - animatedRadius).abs()) {
      return restingStylus;
    }

    final a =
        (d * d - animatedRadius * animatedRadius + armLength * armLength) /
        (2 * d);
    final hIntersect = sqrt(max(0, armLength * armLength - a * a));
    final p2 = pivot + (platterCenter - pivot) * (a / d);

    final x3 = p2.dx + hIntersect * (platterCenter.dy - pivot.dy) / d;
    final y3 = p2.dy - hIntersect * (platterCenter.dx - pivot.dx) / d;
    return Offset(x3, y3);
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLen2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLen2 <= 0.000001) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLen2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  void _handlePanStart(DragStartDetails details) {
    if (_cueMoving) return;
    final settings = SettingsService.instance;
    final box = context.findRenderObject() as RenderBox;
    final w = box.size.width;
    final h = box.size.height;
    final local = box.globalToLocal(details.globalPosition);

    // Control hitboxes should not start a record drag.
    final knobCenter = Offset(w * 0.12, h * 0.88);
    final knobR = w * 0.07;
    final knobRect = Rect.fromCircle(center: knobCenter, radius: knobR * 1.5);
    if (knobRect.contains(local)) {
      _isTurningKnob = true;
      _lastKnobAngle = atan2(
        local.dy - knobCenter.dy,
        local.dx - knobCenter.dx,
      );
      HapticFeedback.selectionClick();
      return;
    }

    final leverRect = Rect.fromCenter(
      center: Offset(w * 0.24, h * 0.88),
      width: w * 0.12,
      height: w * 0.12,
    );
    if (leverRect.contains(local)) return;

    final rpmRect = Rect.fromCenter(
      center: Offset(w * 0.60, h * 0.88),
      width: w * 0.12,
      height: w * 0.08,
    );
    if (rpmRect.contains(local)) return;

    // Tonearm hit test (manual needle drop)
    if (settings.turntableNeedleDropEnabled) {
      final progress = _armProgressOverride ?? _currentProgressFromPlayer();
      final pivot = Offset(w * 0.84, h * 0.38);
      final stylus = _stylusForProgress(w: w, h: h, progress: progress);
      final dist = _distancePointToSegment(local, pivot, stylus);
      final armHit = dist <= (w * 0.05) && local.dx > w * 0.50;
      if (armHit) {
        _isDraggingArm = true;
        _isDragging = false;
        _lastDragAngle = null;
        _wasPlayingBeforeArmDrag = widget.ctrl.player.playing;

        // Lift cue + pause while placing the needle.
        // Important: don't set `_cueMoving=true` here, or pan updates get blocked.
        setState(() {
          _cueLift = 1.0;
          _cueTarget = 1.0;
          _cueMoving = false;
          _pendingPauseAfterCue = false;
          _pendingPlayAfterCue = false;
          _armProgressOverride = progress;
        });
        if (_wasPlayingBeforeArmDrag) {
          widget.ctrl.player.pause();
        }
        HapticFeedback.selectionClick();
        return;
      }
    }

    if (!settings.turntableSlipmatEnabled) return;

    // Only start a record drag if the touch begins on the platter area.
    final platterCenter = Offset(w * 0.42, h * 0.45);
    final platterRadius = w * 0.33;
    final recordR = platterRadius * 0.90;
    if ((local - platterCenter).distance > recordR) return;

    _isDragging = true;
    _dragVelocity = 0;
    _dragPosition = widget.ctrl.player.position;
    _lastDragAngle = atan2(
      local.dy - platterCenter.dy,
      local.dx - platterCenter.dx,
    );
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_cueMoving && !_isDraggingArm) return;
    final settings = SettingsService.instance;
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(details.globalPosition);

    if (_isDraggingArm) {
      if (!settings.turntableNeedleDropEnabled) return;
      final w = box.size.width;
      final h = box.size.height;
      final platterRadius = w * 0.33;
      final platterCenter = Offset(w * 0.42, h * 0.45);
      final recordR = platterRadius * 0.90;
      final pivot = Offset(w * 0.84, h * 0.38);
      final pivotToSpindle = (platterCenter - pivot).distance;
      final armLength = pivotToSpindle + (w * 0.04);

      // Project touch onto the arm-length circle around the pivot.
      final ang = atan2(local.dy - pivot.dy, local.dx - pivot.dx);
      final stylus = pivot + Offset.fromDirection(ang, armLength);
      final radius = (stylus - platterCenter).distance;

      final leadInRadius = recordR * 0.92;
      final finalRadius = recordR * 0.35;
      final t = ((leadInRadius - radius) / (leadInRadius - finalRadius)).clamp(
        0.0,
        1.0,
      );

      final p = widget.ctrl.player;
      final dur = p.duration;
      if (dur != null && dur.inMilliseconds > 0) {
        final newPos = Duration(milliseconds: (dur.inMilliseconds * t).round());
        _seekThrottled(newPos);
        setState(() {
          _armProgressOverride = t;
          _dragPosition = newPos;
        });
      } else {
        setState(() => _armProgressOverride = t);
      }
      return;
    }

    if (_isTurningKnob) {
      final w = box.size.width;
      final h = box.size.height;
      final knobCenter = Offset(w * 0.12, h * 0.88);

      final currentAngle = atan2(
        local.dy - knobCenter.dy,
        local.dx - knobCenter.dx,
      );
      if (_lastKnobAngle != null) {
        var delta = currentAngle - _lastKnobAngle!;
        if (delta > pi) delta -= 2 * pi;
        if (delta < -pi) delta += 2 * pi;

        // Update pitch
        setState(() {
          // Map rotation to pitch (0.8 to 1.2)
          // Sensitivity: 1 full rotation = 0.4 change?
          _pitchValue = (_pitchValue + delta * 0.2).clamp(0.8, 1.2);

          const detents = <double>[0.90, 0.95, 1.00, 1.05, 1.10];
          const snapThreshold = 0.007;
          double? snapped;
          for (final d in detents) {
            if ((_pitchValue - d).abs() <= snapThreshold) {
              snapped = d;
              break;
            }
          }
          if (snapped != null) {
            _pitchValue = snapped;
            if (_lastPitchDetent == null ||
                (_lastPitchDetent! - snapped).abs() > 0.0001) {
              _lastPitchDetent = snapped;
              HapticFeedback.selectionClick();
            }
          } else {
            _lastPitchDetent = null;
          }
        });
        widget.ctrl.setSpeed(_pitchValue);
      }
      _lastKnobAngle = currentAngle;
      return;
    }

    if (!_isDragging || !settings.turntableSlipmatEnabled) return;

    final w = box.size.width;
    final h = box.size.height;
    final platterCenter = Offset(w * 0.42, h * 0.45);
    final currentAngle = atan2(
      local.dy - platterCenter.dy,
      local.dx - platterCenter.dx,
    );

    if (_lastDragAngle != null) {
      var delta = currentAngle - _lastDragAngle!;
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;

      _dragVelocity = delta * 5.0; // Boost for feel

      // Seek audio!
      final p = widget.ctrl.player;
      if (p.duration != null && _dragPosition != null) {
        final seekDelta = Duration(
          milliseconds: (delta * 1000).toInt(),
        ); // 1 rad = 1 sec
        final newPos = _dragPosition! + seekDelta;
        if (newPos >= Duration.zero && newPos <= p.duration!) {
          _dragPosition = newPos;
          _seekThrottled(newPos);
        }
      }
    }

    _lastDragAngle = currentAngle;
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_isTurningKnob) {
      _isTurningKnob = false;
      _lastKnobAngle = null;
      // Snap to 1.0 if close?
      if ((_pitchValue - 1.0).abs() < 0.02) {
        setState(() => _pitchValue = 1.0);
        widget.ctrl.setSpeed(1.0);
        HapticFeedback.mediumImpact();
      }
      return;
    }

    if (_isDraggingArm) {
      _isDraggingArm = false;
      final pending = _pendingSeek;
      if (pending != null) {
        widget.ctrl.player.seek(pending);
        _pendingSeek = null;
      }
      final shouldResume = _wasPlayingBeforeArmDrag;
      _wasPlayingBeforeArmDrag = false;

      setState(() {
        _armProgressOverride = null;
        _dragPosition = null;
        if (shouldResume) {
          _cueTarget = 0.0;
          _cueMoving = true;
          _pendingPlayAfterCue = true;
        } else {
          _cueTarget = 1.0;
          _cueMoving = true;
        }
      });
      return;
    }

    final pending = _pendingSeek;
    if (pending != null) {
      widget.ctrl.player.seek(pending);
      _pendingSeek = null;
    }

    _isDragging = false;
    _lastDragAngle = null;
    _dragPosition = null;
    // If we were playing, resume target velocity
    if (widget.ctrl.player.playing) {
      _targetVelocity = 1.0;
    } else {
      _targetVelocity = 0.0;
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_cueMoving) return;
    final box = context.findRenderObject() as RenderBox;
    final w = box.size.width;
    final h = box.size.height;
    final local = box.globalToLocal(details.globalPosition);

    // Lever Hitbox (Moved to Bottom Left, right of Knob)
    final leverRect = Rect.fromCenter(
      center: Offset(w * 0.24, h * 0.88),
      width: w * 0.12,
      height: w * 0.12,
    );
    if (leverRect.contains(local)) {
      // Cue lever: lift/drop tonearm with a timed motion.
      final isPlaying = widget.ctrl.player.playing;
      final goingDown = _cueTarget >= 0.5;
      setState(() {
        _cueTarget = goingDown ? 0.0 : 1.0;
        _cueMoving = true;
        _pendingPlayAfterCue = goingDown && !isPlaying;
        _pendingPauseAfterCue = (!goingDown) && isPlaying;
      });
      HapticFeedback.selectionClick();
      return;
    }

    // RPM Hitbox (Moved further left)
    final rpmRect = Rect.fromCenter(
      center: Offset(w * 0.60, h * 0.88),
      width: w * 0.12,
      height: w * 0.08,
    );
    if (rpmRect.contains(local)) {
      setState(() => _is33RPM = !_is33RPM);
      HapticFeedback.selectionClick();
      return;
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final w = box.size.width;
    final h = box.size.height;
    final local = box.globalToLocal(details.globalPosition);

    // Knob Hit Test (Updated)
    final knobCenter = Offset(w * 0.12, h * 0.88);
    final knobR = w * 0.07;
    final knobRect = Rect.fromCircle(center: knobCenter, radius: knobR * 2.0);

    if (knobRect.contains(local)) {
      setState(() {
        _pitchValue = 1.0;
        _lastKnobAngle = null;
      });
      widget.ctrl.setSpeed(1.0);
      HapticFeedback.heavyImpact();
      _toast('Pitch Reset');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _playingSub?.cancel();
    if (_imageListener != null && _imageStream != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    if (_neuralMixListener != null) {
      widget.ctrl.neuralMixActiveNotifier.removeListener(_neuralMixListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.ctrl.player;
    final settings = SettingsService.instance;
    final accentColor = Color(settings.accentColor);

    final disableAnimations =
        MediaQuery.of(context).disableAnimations ||
        SchedulerBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    final configuredTier = settings.turntablePerfTier.clamp(0, 2);
    final perfTier =
        disableAnimations
            ? 0
            : (settings.lowPerformanceMode
                ? min(configuredTier, 1)
                : configuredTier);
    // Generate a unique color for this track
    final baseHue =
        widget.item != null
            ? (widget.item!.title.hashCode % 360).toDouble()
            : 120.0;
    // Cycle through colors based on disc rotation for more dynamic range
    final hueShift = (_discAngle * 180 / pi) % 360;
    final trackColor =
        HSVColor.fromAHSV(1.0, (baseHue + hueShift) % 360, 0.85, 1.0).toColor();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight) * 0.95;

        if (perfTier == 2) {
          _ensureDustTexture(
            size: 512,
            seed: widget.item?.id.hashCode ?? 424242,
          );
        }

        return Center(
          child: GestureDetector(
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onTapUp: _handleTapUp,
            onDoubleTapDown: _handleDoubleTapDown,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  // 1. Static Base (Cached)
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size(size, size),
                      painter: _TurntableBasePainter(
                        strobeEnabled: _strobeEnabled,
                        strobeColor: trackColor,
                        accentColor: accentColor,
                      ),
                      isComplex: true,
                    ),
                  ),
                  // 1.5 High Tech Speaker
                  Positioned(
                    left: size * 0.69,
                    top: size * 0.69,
                    width: size * 0.24,
                    height: size * 0.24,
                    child: StreamBuilder<bool>(
                      stream: player.playingStream,
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return StreamBuilder<double>(
                          stream: player.volumeStream,
                          builder: (context, volSnap) {
                            final volume = volSnap.data ?? 1.0;
                            return StreamBuilder<Duration>(
                              stream: player.positionStream,
                              builder: (context, posSnap) {
                                return HighTechSpeaker(
                                  isPlaying: isPlaying,
                                  bpm: _currentBpm,
                                  position: posSnap.data ?? player.position,
                                  volume: volume,
                                  accentColor: accentColor,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // 2. Dynamic Spinner (Animated)
                  RepaintBoundary(
                    child: StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, posSnap) {
                        final pos =
                            _dragPosition ?? posSnap.data ?? Duration.zero;
                        final dur =
                            player.duration ?? const Duration(milliseconds: 1);
                        final progress =
                            dur.inMilliseconds == 0
                                ? 0.0
                                : pos.inMilliseconds / dur.inMilliseconds;

                        return CustomPaint(
                          size: Size(size, size),
                          painter: _TurntableSpinnerPainter(
                            progress: progress.clamp(0.0, 1.0),
                            discAngle: _discAngle,
                            velocity: _angularVelocity,
                            strobeColor: trackColor,
                            knobAngle: (_pitchValue - 1.0) * 5.0,
                            labelImage: _labelImage ?? _generatedLabelImage,
                            strobeEnabled: _strobeEnabled,
                            is33RPM: _is33RPM,
                            isPlaying: player.playing,
                            lowPerformanceMode: settings.lowPerformanceMode,
                            accentColor: accentColor,
                            tonearmPulse: _tonearmPulse,
                            groovePulse: _groovePulse,
                            beatPulse: _beatPulse,
                            cueLift: _cueLift,
                            armProgressOverride: _armProgressOverride,
                            perfTier: perfTier,
                            dustImage: perfTier == 2 ? _dustImage : null,
                          ),
                          willChange: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _seekThrottled(Duration position) {
    _pendingSeek = position;
    final now = DateTime.now().millisecondsSinceEpoch;
    // ~20 Hz cap avoids seek storms during drags.
    if (now - _lastSeekAtMs < 50) return;
    _lastSeekAtMs = now;
    widget.ctrl.player.seek(position);
  }
}

class _TurntableBasePainter extends CustomPainter {
  final bool strobeEnabled;
  final Color strobeColor;
  final Color accentColor;

  _TurntableBasePainter({
    required this.strobeEnabled,
    required this.strobeColor,
    required this.accentColor,
  });

  @override
  bool shouldRepaint(covariant _TurntableBasePainter oldDelegate) =>
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
    final platterRadius = w * 0.33;
    final platterCenter = Offset(
      w * 0.42,
      h * 0.45,
    ); // Slightly up-left to make room

    // Accent-driven "metallic paint" (Coruscant-inspired): deep base + brighter edge + subtle flake.
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

    // Wood Grain
    canvas.save();
    canvas.clipRRect(plinthRRect);
    final grainPaint =
        Paint()
          ..color = Colors.black.withValues(alpha: 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    final rand = Random(42);
    for (double i = 0; i < w * 1.5; i += w * 0.02) {
      final path = Path();
      path.moveTo(i, 0);
      path.cubicTo(
        i + (rand.nextDouble() - 0.5) * w * 0.1,
        h * 0.33,
        i + (rand.nextDouble() - 0.5) * w * 0.1,
        h * 0.66,
        i + (rand.nextDouble() - 0.5) * w * 0.05,
        h,
      );
      canvas.drawPath(path, grainPaint);
    }
    canvas.restore();

    // Metallic flake (lightweight): stable speckle so it doesn't shimmer.
    canvas.save();
    canvas.clipRRect(plinthRRect);
    final flakeRand = Random(4242);
    for (int i = 0; i < 900; i++) {
      final t = flakeRand.nextDouble();
      final flakeColor = Color.lerp(
        Colors.white,
        accentColor,
        t,
      )!.withValues(alpha: 0.04 + (t * 0.05));
      canvas.drawCircle(
        Offset(flakeRand.nextDouble() * w, flakeRand.nextDouble() * h),
        0.4 + flakeRand.nextDouble() * 0.6,
        Paint()..color = flakeColor,
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

    // Speaker Background (Black Hole for Liquid)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        speakerRect.deflate(w * 0.01),
        Radius.circular(w * 0.01),
      ),
      Paint()..color = const Color(0xFF000000),
    );

    // 3. TONEARM BASE PLATE (Right Side)
    final basePlateRect = Rect.fromCenter(
      center: Offset(w * 0.84, h * 0.38),
      width: w * 0.17,
      height: h * 0.47,
    );

    final basePlatePath = Path();
    basePlatePath.addRRect(
      RRect.fromRectAndRadius(basePlateRect, Radius.circular(w * 0.07)),
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
      basePlateRect.topCenter.translate(0, w * 0.032),
      screwR,
      screwP,
    );
    canvas.drawCircle(
      basePlateRect.bottomCenter.translate(0, -w * 0.032),
      screwR,
      screwP,
    );

    // 4. PLATTER WELL (Shadow) - REMOVED as per request
    // canvas.drawCircle(...)

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
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void drawLabel(String text, Offset center) {
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF666666),
          fontSize: w * 0.015,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier', // Monospace for technical look
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }

    drawLabel("33", rpmBaseRect.centerLeft.translate(w * 0.02, 0));
    drawLabel("45", rpmBaseRect.centerRight.translate(-w * 0.02, 0));

    // START/STOP Labels
    final leverBaseCenter = Offset(w * 0.24, h * 0.88);
    drawLabel("START", leverBaseCenter.translate(0, w * 0.04));
    drawLabel("STOP", leverBaseCenter.translate(0, -w * 0.04));

    // PITCH Label
    final knobCenter = Offset(w * 0.12, h * 0.88);
    drawLabel("PITCH", knobCenter.translate(0, w * 0.055));

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

class _TurntableSpinnerPainter extends CustomPainter {
  final double progress;
  final double? armProgressOverride;
  final double discAngle;
  final double velocity; // 0.0 to 1.0
  final Color strobeColor;
  final double knobAngle;
  final ui.Image? labelImage;
  final ui.Image? dustImage;
  final bool strobeEnabled;
  final bool is33RPM;
  final bool isPlaying;
  final bool lowPerformanceMode;
  final int perfTier; // 0=off, 1=minimal, 2=full
  final Color accentColor;
  final double tonearmPulse;
  final double groovePulse;
  final double beatPulse;
  final double cueLift;

  _TurntableSpinnerPainter({
    required this.progress,
    this.armProgressOverride,
    required this.discAngle,
    this.velocity = 1.0,
    this.strobeColor = const Color(0xFF00FF00),
    this.knobAngle = 0.0,
    this.labelImage,
    this.dustImage,
    this.strobeEnabled = true,
    this.is33RPM = true,
    this.isPlaying = false,
    this.lowPerformanceMode = false,
    this.perfTier = 2,
    required this.accentColor,
    this.tonearmPulse = 0.0,
    this.groovePulse = 0.0,
    this.beatPulse = 0.0,
    this.cueLift = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final effectiveProgress = (armProgressOverride ?? progress).clamp(0.0, 1.0);
    final tier = perfTier.clamp(0, 2);
    final minimal = tier >= 1;
    final full = tier >= 2 && !lowPerformanceMode;

    // Layout Constants - MUST MATCH BASE PAINTER
    final platterRadius = w * 0.33;
    final platterCenter = Offset(w * 0.42, h * 0.45);

    // SPINNING PLATTER + MAT + RECORD
    canvas.save();
    canvas.translate(platterCenter.dx, platterCenter.dy);
    canvas.rotate(discAngle);
    canvas.translate(-platterCenter.dx, -platterCenter.dy);

    // 0. Strobe Dots (On the Platter Rim) - REMOVED
    // if (strobeEnabled) { ... }

    final platterR = platterRadius * 0.99;
    final matR = platterRadius * 0.93;
    final recordR = platterRadius * 0.90;

    // Platter (dark metal) with subtle depth.
    canvas.drawCircle(
      platterCenter,
      platterR,
      Paint()
        ..shader = ui.Gradient.radial(
          platterCenter,
          platterR,
          const [Color(0xFF1A1A1A), Color(0xFF0C0C0C), Color(0xFF191919)],
          [0.0, 0.72, 1.0],
        ),
    );
    // Platter lip highlight/shadow.
    canvas.drawCircle(
      platterCenter,
      platterR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.010
        ..shader = ui.Gradient.linear(
          platterCenter.translate(-platterR, -platterR),
          platterCenter.translate(platterR, platterR),
          [
            Colors.white.withValues(alpha: 0.045),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.22),
          ],
          [0.0, 0.55, 1.0],
        ),
    );

    // Slipmat (kept visible under the record).
    canvas.drawCircle(
      platterCenter,
      matR,
      Paint()
        ..shader = ui.Gradient.radial(
          platterCenter,
          matR,
          const [Color(0xFF121212), Color(0xFF0B0B0B)],
          [0.0, 1.0],
        ),
    );
    canvas.drawCircle(
      platterCenter,
      matR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.006
        ..color = Colors.white.withValues(alpha: 0.018),
    );

    // Record base (slightly lifted from mat).
    canvas.drawCircle(
      platterCenter.translate(0, w * 0.0015),
      recordR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.26)
        ..maskFilter =
            full ? MaskFilter.blur(BlurStyle.normal, w * 0.006) : null,
    );
    canvas.drawCircle(
      platterCenter,
      recordR,
      Paint()
        ..shader = ui.Gradient.radial(
          platterCenter,
          recordR,
          const [Color(0xFF0B0B0B), Color(0xFF050505), Color(0xFF0A0A0A)],
          [0.0, 0.72, 1.0],
        ),
    );
    // Edge bevel for thickness.
    canvas.drawCircle(
      platterCenter,
      recordR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.008
        ..shader = ui.Gradient.linear(
          platterCenter.translate(-recordR, -recordR),
          platterCenter.translate(recordR, recordR),
          [
            Colors.white.withValues(alpha: 0.03),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.20),
          ],
          [0.0, 0.6, 1.0],
        ),
    );

    // Grooves - Full tier only (subtle)
    if (full) {
      final grooveRange = recordR * 0.95 - recordR * 0.35;
      final grooveSteps = (grooveRange / 2).floor();
      for (int i = 0; i < grooveSteps; i++) {
        final r = recordR * 0.35 + i * 2.0;
        final grooveAlpha =
            0.02 + groovePulse * 0.05 * (1 - i / max(1, grooveSteps));
        final grooveWidth = 0.35 + groovePulse * 0.25;
        canvas.drawCircle(
          platterCenter,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = grooveWidth
            ..color = Colors.white.withValues(alpha: grooveAlpha * 0.55),
        );
      }
    }

    // Dust / smudges overlay (record space; rotates with the record)
    if (dustImage != null && full) {
      canvas.save();
      canvas.clipPath(
        Path()
          ..addOval(Rect.fromCircle(center: platterCenter, radius: recordR)),
      );
      final src = Rect.fromLTWH(
        0,
        0,
        dustImage!.width.toDouble(),
        dustImage!.height.toDouble(),
      );
      final dst = Rect.fromCircle(center: platterCenter, radius: recordR);
      canvas.drawImageRect(
        dustImage!,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.low
          ..blendMode = BlendMode.srcOver
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: 0.10),
            BlendMode.modulate,
          ),
      );
      canvas.restore();
    }

    // LABEL
    final labelR = recordR * 0.34;
    final labelHsl = HSLColor.fromColor(accentColor);
    final labelColor =
        labelHsl
            .withLightness((labelHsl.lightness * 0.88).clamp(0.0, 1.0))
            .withSaturation((labelHsl.saturation * 0.20).clamp(0.0, 1.0))
            .toColor();
    canvas.drawCircle(platterCenter, labelR, Paint()..color = labelColor);

    // Light label highlight (subtle; avoid a second strong reflection)
    if (minimal && !lowPerformanceMode) {
      canvas.drawCircle(
        platterCenter,
        labelR,
        Paint()
          ..shader = ui.Gradient.linear(
            platterCenter.translate(-labelR, -labelR),
            platterCenter.translate(labelR, labelR),
            [
              Colors.white.withValues(alpha: 0.06),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.06),
            ],
            [0.0, 0.6, 1.0],
          ),
      );

      if (full) {
        final flakeRand = Random(9901);
        for (int i = 0; i < 260; i++) {
          final r = labelR * sqrt(flakeRand.nextDouble());
          final a = flakeRand.nextDouble() * 2 * pi;
          final p = platterCenter + Offset(cos(a) * r, sin(a) * r);
          final c = Color.lerp(
            Colors.white,
            accentColor,
            flakeRand.nextDouble(),
          )!.withValues(alpha: 0.05);
          canvas.drawCircle(
            p,
            0.35 + flakeRand.nextDouble() * 0.45,
            Paint()..color = c,
          );
        }
      }
    }

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
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    }

    // Label Hole (Spindle Hole) - Larger to be visible
    canvas.drawCircle(
      platterCenter,
      labelR * 0.15,
      Paint()..color = const Color(0xFF050505),
    );

    canvas.restore(); // Restore from spinning rotation

    // Single, restrained world-space highlight (avoids multiple competing glints).
    if (minimal && !lowPerformanceMode) {
      const lightAngle = -0.85;
      final shimmer =
          (0.5 + 0.5 * sin(discAngle * 1.4)) * 0.04 * velocity.clamp(0.0, 1.0);

      final wedge =
          Path()
            ..moveTo(platterCenter.dx, platterCenter.dy)
            ..arcTo(
              Rect.fromCircle(center: platterCenter, radius: recordR),
              lightAngle - 0.28,
              0.56,
              false,
            )
            ..close();

      final labelPath =
          Path()
            ..addOval(Rect.fromCircle(center: platterCenter, radius: labelR));
      final highlightPath = Path.combine(
        PathOperation.difference,
        wedge,
        labelPath,
      );

      canvas.drawPath(
        highlightPath,
        Paint()
          ..shader = ui.Gradient.linear(
            platterCenter.translate(
              cos(lightAngle) * recordR,
              sin(lightAngle) * recordR,
            ),
            platterCenter.translate(
              -cos(lightAngle) * recordR,
              -sin(lightAngle) * recordR,
            ),
            [
              Colors.white.withValues(alpha: 0.10 + shimmer),
              Colors.transparent,
            ],
            [0.0, 1.0],
          )
          ..blendMode = BlendMode.plus,
      );
    }

    // Outer edge falloff (subtle darkening to sell depth)
    if (minimal && !lowPerformanceMode) {
      canvas.drawCircle(
        platterCenter,
        recordR,
        Paint()
          ..shader = ui.Gradient.radial(
            platterCenter,
            recordR,
            [Colors.transparent, Colors.black.withValues(alpha: 0.12)],
            [0.75, 1.0],
          )
          ..blendMode = BlendMode.multiply,
      );
    }

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
      Paint()..color = Colors.white.withValues(alpha: 0.65),
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

      // Glow - Skip in low performance mode
      if (!lowPerformanceMode) {
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
      }

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
    final leadInRadius = recordR * 0.92;
    final finalRadius = recordR * 0.35;

    final animatedRadius =
        ui.lerpDouble(leadInRadius, finalRadius, effectiveProgress)!;

    final d = pivotToSpindle;
    Offset stylusPos;

    if (cueLift >= 0.95 && armProgressOverride == null) {
      final restingAngle =
          atan2(platterCenter.dy - pivot.dy, platterCenter.dx - pivot.dx) - 0.4;
      stylusPos = pivot + Offset.fromDirection(restingAngle, armLength);
    } else if (d > armLength + animatedRadius ||
        d < (armLength - animatedRadius).abs()) {
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
    Offset rotateAround(Offset point, Offset center, double angle) {
      final dx = point.dx - center.dx;
      final dy = point.dy - center.dy;
      final cosA = cos(angle);
      final sinA = sin(angle);
      return Offset(
        center.dx + (dx * cosA - dy * sinA),
        center.dy + (dx * sinA + dy * cosA),
      );
    }

    var adjustedStylus = rotateAround(stylusPos, pivot, tonearmPulse * 0.25);
    final armAngle = atan2(
      adjustedStylus.dy - pivot.dy,
      adjustedStylus.dx - pivot.dx,
    );
    final lift = cueLift.clamp(0.0, 1.0);
    final liftOffset = Offset(0, -lift * 10 - tonearmPulse * 3);

    final engaged = lift <= 0.15 && isPlaying && effectiveProgress < 0.995;
    if (engaged && !lowPerformanceMode) {
      final vib =
          (sin(discAngle * 23.0) + sin(discAngle * 47.0)) * (w * 0.00022);
      final perp = Offset(-sin(armAngle), cos(armAngle));
      adjustedStylus = adjustedStylus + perp * vib;
    }

    // DYNAMIC TONEARM SHADOW
    // Shadow offset depends on lift height
    final shadowOffset = const Offset(4, 4) + Offset(lift * 10, lift * 10);

    canvas.drawLine(
      pivot.translate(shadowOffset.dx, shadowOffset.dy),
      adjustedStylus.translate(shadowOffset.dx, shadowOffset.dy),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..strokeWidth = w * 0.0135
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // VINYL REFLECTION (Subtle reflection of arm on the record)
    // Full tier only
    if (full) {
      canvas.save();
      // Clip to vinyl area
      canvas.clipPath(
        Path()
          ..addOval(Rect.fromCircle(center: platterCenter, radius: recordR)),
      );

      // Draw reflection (mirrored or just projected)
      // Simple projection: Draw arm again with low opacity and blur
      canvas.drawLine(
        pivot,
        adjustedStylus,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..strokeWidth = w * 0.0135
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.restore();
    }

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
      adjustedStylus.translate(liftOffset.dx, liftOffset.dy),
      Paint()
        ..shader = ui.Gradient.linear(
          pivot,
          adjustedStylus,
          [
            const Color(0xFFCCCCCC),
            const Color(0xFFEEEEEE),
            const Color(0xFFCCCCCC),
          ],
          [0.0, 0.5, 1.0],
        )
        ..strokeWidth = w * 0.0135
        ..strokeCap = StrokeCap.butt,
    );

    // HEADSHELL (Angled)
    canvas.save();
    canvas.translate(
      adjustedStylus.dx + liftOffset.dx,
      adjustedStylus.dy + liftOffset.dy,
    );
    canvas.rotate(armAngle + 0.4); // Offset angle for headshell

    // Headshell shape
    final headshellPath =
        Path()
          ..moveTo(-w * 0.012, -w * 0.018)
          ..lineTo(w * 0.07, -w * 0.013)
          ..lineTo(w * 0.07, w * 0.013)
          ..lineTo(-w * 0.012, w * 0.018)
          ..close();

    canvas.drawPath(headshellPath, Paint()..color = const Color(0xFF111111));

    // Finger lift
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.044, 0)
        ..quadraticBezierTo(w * 0.088, w * 0.018, w * 0.105, -w * 0.035),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF111111),
    );

    // Cartridge (Red tip)
    canvas.drawRect(
      Rect.fromLTWH(w * 0.018, -w * 0.0085, w * 0.035, w * 0.018),
      Paint()..color = const Color(0xFF333333),
    );
    canvas.drawCircle(
      Offset(w * 0.045, 0),
      w * 0.004,
      Paint()..color = Colors.red,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TurntableSpinnerPainter oldDelegate) =>
      discAngle != oldDelegate.discAngle ||
      isPlaying != oldDelegate.isPlaying ||
      is33RPM != oldDelegate.is33RPM ||
      progress != oldDelegate.progress ||
      armProgressOverride != oldDelegate.armProgressOverride ||
      lowPerformanceMode != oldDelegate.lowPerformanceMode ||
      perfTier != oldDelegate.perfTier ||
      tonearmPulse != oldDelegate.tonearmPulse ||
      groovePulse != oldDelegate.groovePulse ||
      beatPulse != oldDelegate.beatPulse ||
      cueLift != oldDelegate.cueLift ||
      dustImage != oldDelegate.dustImage;
}
