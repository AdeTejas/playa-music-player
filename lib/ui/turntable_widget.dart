// ignore_for_file: prefer_const_declarations

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../services/player_controller.dart';
import '../services/artwork_cache_service.dart';
import '../services/settings_service.dart';
import '../utils/content_mode.dart';
import 'high_tech_speaker.dart';

class TurntableDeck extends StatefulWidget {
  final PlayerController ctrl;
  final MediaItem? item;
  final bool isVisible;

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
  StreamSubscription<PlayerState>? _playingSub;

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

  // Cached static base (plinth, wood grain, controls, etc.)
  // This is the biggest perf win — static elements no longer redraw every frame.
  ui.Image? _baseImage;
  Color? _baseAccentKey;
  double? _baseSizeKey;
  bool _baseGenerating = false;

  // Cached strobe ring (60 dots) - B1 optimization
  ui.Image? _strobeRingImage;
  Color? _strobeRingColorKey;
  bool _strobeRingGenerating = false;

  // Constants
  static const double _kMaxRPM = 33.3333;
  static const double _kRadPerSecond =
      (_kMaxRPM * 2 * pi) / 60.0; // real angular speed per second

  Duration? _lastTickTime;
  double _beatPulse = 0.0;
  double _tonearmPulse = 0.0;
  double _groovePulse = 0.0;

  // B2: Visual progress driven mostly by ticker for lower rebuild pressure
  double _currentVisualProgress = 0.0;
  double _neuralPhase = 0.0;
  double _currentBpm = 120.0;
  bool _neuralMixActive = false;
  VoidCallback? _neuralMixListener;

  Timer? _armReturnSettleTimer;

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

    // Listen to playback state for motor control (handles both pause and natural track end)
    _playingSub = widget.ctrl.player.playerStateStream.listen((state) {
      if (!mounted) return;

      final isActuallyPlaying = state.playing && state.processingState == ProcessingState.ready;

      setState(() {
        _targetVelocity = isActuallyPlaying ? 1.0 : 0.0;

        // On natural track completion, stop the platter but delay the arm return for theatrical effect
        final justEnded = state.processingState == ProcessingState.completed;
        if (justEnded) {
          _targetVelocity = 0.0;
          _armProgressOverride = null;
          _isDraggingArm = false;
          _isDragging = false;

          // Cancel any previous pending arm movement
          _armReturnSettleTimer?.cancel();

          // Theatrical settle delay before the tonearm lifts and returns to rest
          _armReturnSettleTimer = Timer(const Duration(milliseconds: 720), () {
            if (!mounted) return;
            setState(() {
              _cueTarget = 1.0;
              _cueMoving = true;
              // Give the arm a little initial lift so the animation feels intentional
              if (_cueLift < 0.25) _cueLift = 0.25;
            });
          });
        }

        // Manage tonearm cue lift for normal play/pause (not during settle delay)
        if (!_cueMoving && !justEnded) {
          final shouldLiftArm = !isActuallyPlaying;
          _cueTarget = shouldLiftArm ? 1.0 : 0.0;
          _cueMoving = true;

          if (isActuallyPlaying) {
            HapticFeedback.selectionClick();
          } else {
            HapticFeedback.lightImpact();
          }
        }

        // If user starts playing (or next track begins), cancel any pending theatrical arm return
        if (isActuallyPlaying) {
          _armReturnSettleTimer?.cancel();
          _armReturnSettleTimer = null;
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

  bool get _isAudiobookMode =>
      ContentModeDetector.detectFromMediaItem(widget.item) ==
      ContentMode.audiobook;

  void _syncPitchFromPlaybackSpeed() {
    if (!_isAudiobookMode) return;
    final speed = widget.ctrl.player.speed;
    if ((speed - _pitchValue).abs() > 0.01) {
      _pitchValue = speed.clamp(0.75, 2.0);
    }
  }

  void _updateBpmFromItem() {
    if (_isAudiobookMode) {
      _currentBpm = 0;
      _syncPitchFromPlaybackSpeed();
      return;
    }

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

    // 1. Try to get image from media ID (Android MediaStore)
    if (item?.extras != null && item!.extras!.containsKey('mediaId')) {
      try {
        // OnAudioQuery.queryArtwork is not supported on Windows/Linux; skip step 1.
        if (!(Platform.isWindows || Platform.isLinux)) {
          final mediaId = item.extras!['mediaId'] as int;
          final bytes = await ArtworkCacheService.instance.getArtworkBytes(
            id: mediaId,
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
      }

      if (provider != null) {
        if (_imageListener != null && _imageStream != null) {
          _imageStream!.removeListener(_imageListener!);
          _imageListener = null;
          _imageStream = null;
        }

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
              if (!mounted) return;
              setState(() => _labelImage = null);
              unawaited(_updateGeneratedLabelImage(targetSize: targetSize));
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
    final labelBaseLight = min(hsl.lightness, 0.65);
    final labelBaseSat = hsl.saturation;
    final bg = hsl
      .withSaturation((labelBaseSat * 0.18).clamp(0.0, 1.0))
      .withLightness((labelBaseLight * 0.80).clamp(0.0, 1.0))
      .toColor();
    final ring1 = hsl
      .withSaturation((labelBaseSat * 0.28).clamp(0.0, 1.0))
      .withLightness((labelBaseLight * 0.62).clamp(0.0, 1.0))
      .toColor();
    final ring2 = hsl
      .withSaturation((labelBaseSat * 0.22).clamp(0.0, 1.0))
      .withLightness((labelBaseLight * 0.52).clamp(0.0, 1.0))
      .toColor();

    c.drawCircle(center, r, Paint()..color = bg);

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

    final speckle = Paint()..color = Colors.white.withValues(alpha: 0.08);
    for (int i = 0; i < 220; i++) {
      final rr = r * sqrt(rand.nextDouble());
      final aa = rand.nextDouble() * 2 * pi;
      final p = center + Offset(cos(aa) * rr, sin(aa) * rr);
      c.drawCircle(p, 0.8 + rand.nextDouble() * 1.3, speckle);
    }

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
    c.drawRect(Offset.zero & sz, Paint()..color = Colors.transparent);

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

  /// Caches the expensive static base layer (plinth, wood grain, grill, controls, etc.)
  /// as an image. This is the single biggest performance win for the turntable
  /// while keeping 100% of the visual detail.
  void _ensureBaseImage(double size, Color accentColor) {
    final needsRegen = _baseImage == null ||
        _baseSizeKey != size ||
        _baseAccentKey != accentColor;

    if (!needsRegen || _baseGenerating) return;

    _baseSizeKey = size;
    _baseAccentKey = accentColor;
    _baseGenerating = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _generateBaseImage(size: size, accentColor: accentColor).whenComplete(() {
          if (mounted) {
            setState(() => _baseGenerating = false);
          }
        }),
      );
    });
  }

  Future<void> _generateBaseImage({
    required double size,
    required Color accentColor,
  }) async {
    await Future<void>.delayed(Duration.zero); // yield

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final sz = Size(size, size);

    // Use the existing heavy painter to generate the exact same visual
    final basePainter = _TurntableBasePainter(
      strobeEnabled: _strobeEnabled,
      strobeColor: accentColor, // highlight version is close enough for cache key
      accentColor: accentColor,
    );

    basePainter.paint(canvas, sz);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());

    if (!mounted) return;

    // Dispose previous image to free GPU memory
    _baseImage?.dispose();

    setState(() {
      _baseImage = img;
    });
  }

  /// B1: Pre-render the 60 strobe dots as a single image.
  /// Drawing 60 circles every frame is expensive; one rotated image is cheap.
  void _ensureStrobeRing(double size, Color strobeColor) {
    final needsRegen = _strobeRingImage == null || _strobeRingColorKey != strobeColor;
    if (!needsRegen || _strobeRingGenerating) return;

    _strobeRingColorKey = strobeColor;
    _strobeRingGenerating = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _generateStrobeRing(size: size, strobeColor: strobeColor).whenComplete(() {
          if (mounted) setState(() => _strobeRingGenerating = false);
        }),
      );
    });
  }

  Future<void> _generateStrobeRing({
    required double size,
    required Color strobeColor,
  }) async {
    await Future<void>.delayed(Duration.zero);

    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final platterRadius = size * 0.36; // must match painter constants
    final dotRadius = size * 0.004;
    const dotCount = 60;

    final paint = Paint()..color = strobeColor.withValues(alpha: 0.85);

    for (int i = 0; i < dotCount; i++) {
      final angle = (i / dotCount) * 2 * pi;
      final dx = center.dx + cos(angle) * (platterRadius * 0.98);
      final dy = center.dy + sin(angle) * (platterRadius * 0.98);
      c.drawCircle(Offset(dx, dy), dotRadius, paint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());

    if (!mounted) return;

    _strobeRingImage?.dispose();
    setState(() {
      _strobeRingImage = img;
    });
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final previous = _lastTickTime;
    _lastTickTime = elapsed;
    if (previous == null) return;

    double dt = (elapsed - previous).inMicroseconds / 1e6;
    if (dt <= 0) return;
    dt = dt.clamp(0.0, 0.1);

    final disableAnimations =
        SchedulerBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;

    if (disableAnimations) dt *= 0.18;

    if (_cueMoving && !disableAnimations) {
      const cueRate = 3.2;
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

    _syncPitchFromPlaybackSpeed();

    final rpmMult = _is33RPM ? 1.0 : 1.35;
    final speedFactor =
        _isAudiobookMode ? widget.ctrl.player.speed.clamp(0.5, 2.0) : _pitchValue;
    final baseTarget = _targetVelocity * speedFactor * rpmMult;
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
    const accelRate = 3.2;
    // Gentler braking when coming to a natural stop (sounds more like real vinyl)
    final isComingToStop = _targetVelocity < 0.05;
    const brakeRate = 6.0;
    const gentleBrakeRate = 2.6;
    final effectiveBrake = isComingToStop ? gentleBrakeRate : brakeRate;

    final rate = delta >= 0 ? accelRate : effectiveBrake;
    final step = rate * dt;
    if (delta.abs() > 0.0005) {
      _angularVelocity += delta.clamp(-step, step);
    } else {
      _angularVelocity = target;
    }

    // Allow the platter to coast naturally when stopping (more realistic vinyl behavior)
    final isCoastingToStop = _angularVelocity.abs() > 0.0003 && _targetVelocity < 0.01;
    if (_angularVelocity.abs() > 0.0003 || widget.ctrl.player.playing || isCoastingToStop) {
      _platterAngle += _kRadPerSecond * _angularVelocity * dt;
      if (_platterAngle > 2 * pi) _platterAngle -= 2 * pi;
      if (_platterAngle < 0) _platterAngle += 2 * pi;
    }

    double wrapAngle(double a) {
      var v = a;
      while (v > pi) v -= 2 * pi;
      while (v < -pi) v += 2 * pi;
      return v;
    }

    if (_isDragging && !_isTurningKnob) {
      setState(() {
        _discAngle += _dragVelocity * dt * 6.0;
        if (_discAngle > 2 * pi) _discAngle -= 2 * pi;
        if (_discAngle < 0) _discAngle += 2 * pi;
        _slipOffset = wrapAngle(_discAngle - _platterAngle);
      });
      _dragVelocity *= 0.9;
    } else {
      final catchFactor = 1.0 - exp(-4.2 * dt);
      _slipOffset += (0.0 - _slipOffset) * catchFactor;
      setState(() {
        _discAngle = _platterAngle + _slipOffset;
        if (_discAngle > 2 * pi) _discAngle -= 2 * pi;
        if (_discAngle < 0) _discAngle += 2 * pi;

        // B2 support: keep a visual progress advancing from ticker
        if (widget.ctrl.player.playing) {
          _currentVisualProgress = (_currentVisualProgress + 0.016) % 1.0;
        }
      });
    }

    final audiobookCalm = _isAudiobookMode;
    final bpm = _currentBpm.clamp(60.0, 220.0);
    final beatFreq = audiobookCalm ? 0.0 : bpm / 60.0;
    _beatPulse = disableAnimations || audiobookCalm
        ? 0.0
        : (sin(seconds * beatFreq * 2 * pi) + 1) / 2;
    _tonearmPulse = disableAnimations || audiobookCalm
        ? 0.0
        : sin(seconds * beatFreq * pi * 0.35) * 0.012;
    if (_neuralMixActive && !audiobookCalm) {
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
    final restingAngle =
        atan2(platterCenter.dy - pivot.dy, platterCenter.dx - pivot.dx) - 0.4;
    final restingStylus = pivot + Offset.fromDirection(restingAngle, armLength);

    if (_cueLift >= 0.95 && !_isDraggingArm && _armProgressOverride == null) {
      return restingStylus;
    }

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

    final knobCenter = Offset(w * 0.12, h * 0.88);
    final knobR = w * 0.07;
    if (Rect.fromCircle(center: knobCenter, radius: knobR * 1.5).contains(local)) {
      _isTurningKnob = true;
      _lastKnobAngle = atan2(local.dy - knobCenter.dy, local.dx - knobCenter.dx);
      HapticFeedback.selectionClick();
      return;
    }

    if (settings.turntableNeedleDropEnabled) {
      final progress = _armProgressOverride ?? _currentProgressFromPlayer();
      final pivot = Offset(w * 0.84, h * 0.38);
      final stylus = _stylusForProgress(w: w, h: h, progress: progress);
      final dist = _distancePointToSegment(local, pivot, stylus);
        if (dist <= (w * 0.05) && local.dx > w * 0.50) {
          _isDraggingArm = true;
          _isDragging = false;
          _wasPlayingBeforeArmDrag = widget.ctrl.player.playing;

          _armReturnSettleTimer?.cancel();
          _armReturnSettleTimer = null;

          setState(() {
            _cueLift = 1.0;
            _cueTarget = 1.0;
            _cueMoving = false;
            _armProgressOverride = progress;
          });
        if (_wasPlayingBeforeArmDrag) widget.ctrl.player.pause();
        HapticFeedback.selectionClick();
        return;
      }
    }

    if (!settings.turntableSlipmatEnabled) return;
    final platterCenter = Offset(w * 0.42, h * 0.45);
    final recordR = (w * 0.33) * 0.90;
    if ((local - platterCenter).distance > recordR) return;

    _isDragging = true;
    _dragVelocity = 0;
    _dragPosition = widget.ctrl.player.position;
    _lastDragAngle = atan2(local.dy - platterCenter.dy, local.dx - platterCenter.dx);
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
      final recordR = (w * 0.33) * 0.90;
      final platterCenter = Offset(w * 0.42, h * 0.45);
      final pivot = Offset(w * 0.84, h * 0.38);
      final armLength = (platterCenter - pivot).distance + (w * 0.04);
      final ang = atan2(local.dy - pivot.dy, local.dx - pivot.dx);
      final stylus = pivot + Offset.fromDirection(ang, armLength);
      final radius = (stylus - platterCenter).distance;
      final leadInRadius = recordR * 0.92;
      final finalRadius = recordR * 0.35;
      final t = ((leadInRadius - radius) / (leadInRadius - finalRadius)).clamp(0.0, 1.0);
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
      final currentAngle = atan2(local.dy - knobCenter.dy, local.dx - knobCenter.dx);
      if (_lastKnobAngle != null) {
        var delta = currentAngle - _lastKnobAngle!;
        if (delta > pi) delta -= 2 * pi;
        if (delta < -pi) delta += 2 * pi;
        final audiobookKnob = _isAudiobookMode;
        setState(() {
          if (audiobookKnob) {
            _pitchValue = (_pitchValue + delta * 0.35).clamp(0.75, 2.0);
            const detents = <double>[1.0, 1.25, 1.5, 1.75, 2.0];
            double? snapped;
            for (final d in detents) {
              if ((_pitchValue - d).abs() <= 0.03) {
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
          } else {
            _pitchValue = (_pitchValue + delta * 0.2).clamp(0.8, 1.2);
            const detents = <double>[0.90, 0.95, 1.00, 1.05, 1.10];
            double? snapped;
            for (final d in detents) {
              if ((_pitchValue - d).abs() <= 0.007) {
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
          }
        });
        widget.ctrl.setPlaybackSpeed(_pitchValue);
      }
      _lastKnobAngle = currentAngle;
      return;
    }

    if (!_isDragging || !settings.turntableSlipmatEnabled) return;
    final w = box.size.width;
    final h = box.size.height;
    final platterCenter = Offset(w * 0.42, h * 0.45);
    final currentAngle = atan2(local.dy - platterCenter.dy, local.dx - platterCenter.dx);

    if (_lastDragAngle != null) {
      var delta = currentAngle - _lastDragAngle!;
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;
      _dragVelocity = delta * 5.0;
      final p = widget.ctrl.player;
      if (p.duration != null && _dragPosition != null) {
        final seekDelta = Duration(milliseconds: (delta * 1000).toInt());
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
    _targetVelocity = widget.ctrl.player.playing ? 1.0 : 0.0;
  }

  void _handleTapUp(TapUpDetails details) {
    if (_cueMoving) return;
    final box = context.findRenderObject() as RenderBox;
    final w = box.size.width;
    final h = box.size.height;
    final local = box.globalToLocal(details.globalPosition);

    if (Rect.fromCenter(center: Offset(w * 0.24, h * 0.88), width: w * 0.12, height: w * 0.12).contains(local)) {
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

    if (Rect.fromCenter(center: Offset(w * 0.60, h * 0.88), width: w * 0.12, height: w * 0.08).contains(local)) {
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
    final knobCenter = Offset(w * 0.12, h * 0.88);
    if (Rect.fromCircle(center: knobCenter, radius: (w * 0.07) * 2.0).contains(local)) {
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
    _armReturnSettleTimer?.cancel();
    if (_imageListener != null && _imageStream != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    if (_neuralMixListener != null) {
      widget.ctrl.neuralMixActiveNotifier.removeListener(_neuralMixListener!);
    }
    _baseImage?.dispose();
    _dustImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.ctrl.player;
    final settings = SettingsService.instance;
    final accentColor =
        settings.resolveNowPlayingAccent(item: widget.item);
    final highlightAccent = accentColor;
    final disableAnimations = SchedulerBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    final perfTier = disableAnimations ? 0 : (settings.lowPerformanceMode ? min(settings.turntablePerfTier, 1) : settings.turntablePerfTier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight);
        if (perfTier == 2) _ensureDustTexture(size: 512, seed: widget.item?.id.hashCode ?? 424242);

        // Trigger static base caching (major perf win)
        if (perfTier >= 1) {
          _ensureBaseImage(size, accentColor);
        }

        // B1: Cache expensive strobe dots
        if (_strobeEnabled && perfTier >= 1) {
          _ensureStrobeRing(size, highlightAccent);
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
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size(size, size),
                      painter: _baseImage != null
                          ? _CachedStaticBasePainter(_baseImage!)
                          : _TurntableBasePainter(
                              strobeEnabled: _strobeEnabled,
                              strobeColor: highlightAccent,
                              accentColor: accentColor,
                            ),
                      isComplex: true,
                    ),
                  ),
                  Positioned(
                    left: size * 0.69, top: size * 0.69, width: size * 0.24, height: size * 0.24,
                    child: StreamBuilder<bool>(
                      stream: player.playingStream,
                      builder: (context, snapshot) => StreamBuilder<double>(
                        stream: player.volumeStream,
                        builder: (context, volSnap) => StreamBuilder<Duration>(
                          stream: player.positionStream,
                          builder: (context, posSnap) => HighTechSpeaker(
                            isPlaying: snapshot.data ?? false,
                            bpm: _currentBpm,
                            position: posSnap.data ?? player.position,
                            volume: volSnap.data ?? 1.0,
                            accentColor: accentColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                    // B2: Drive the expensive rotating disc primarily from our internal ticker
                    // instead of rebuilding on every positionStream tick.
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size(size, size),
                        painter: _TurntableSpinnerPainter(
                          progress: _currentProgressFromPlayer(), // actual song progress for tonearm position
                          discAngle: _discAngle,
                          velocity: _angularVelocity,
                          strobeColor: highlightAccent,
                          knobAngle: (_pitchValue - 1.0) * 5.0,
                          labelImage: _labelImage ?? _generatedLabelImage,
                          strobeEnabled: _strobeEnabled,
                          is33RPM: _is33RPM,
                          isPlaying: player.playing,
                          lowPerformanceMode: settings.lowPerformanceMode,
                          accentColor: accentColor,
                          accentHighlight: highlightAccent,
                          tonearmPulse: _tonearmPulse,
                          groovePulse: _groovePulse,
                          beatPulse: _beatPulse,
                          cueLift: _cueLift,
                          armProgressOverride: _armProgressOverride,
                          perfTier: perfTier,
                          dustImage: perfTier == 2 ? _dustImage : null,
                          strobeRingImage: _strobeRingImage,
                        ),
                        willChange: true,
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
    final isWindows = Platform.isWindows;
    final plinthRect = Rect.fromLTWH(w * 0.02, h * 0.02, w * 0.96, h * 0.96);
    final plinthRRect = RRect.fromRectAndRadius(plinthRect, Radius.circular(w * 0.04));
    final platterRadius = w * 0.33;
    final platterCenter = Offset(w * 0.42, h * 0.45);
    final c1 = Color.lerp(const Color(0xFF2A2A2A), accentColor, 0.24)!;
    final c2 = Color.lerp(const Color(0xFF1A1A1A), accentColor, 0.18)!;
    final c3 = Color.lerp(const Color(0xFF0F0F0F), accentColor, 0.12)!;

    canvas.drawRRect(plinthRRect, Paint()..shader = ui.Gradient.linear(plinthRect.topLeft, plinthRect.bottomRight, [c1, c2, c3], [0.0, 0.6, 1.0]));

    if (isWindows) {
      canvas.drawRRect(plinthRRect, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.0035..shader = ui.Gradient.linear(plinthRect.topLeft, plinthRect.bottomRight, [Colors.white.withValues(alpha: 0.14), Colors.transparent, Colors.black.withValues(alpha: 0.20)], [0.0, 0.55, 1.0]));
    }

    canvas.save();
    canvas.clipRRect(plinthRRect);
    final rand = Random(42);
    for (double i = 0; i < w * 1.5; i += w * (isWindows ? 0.014 : 0.02)) {
      final path = Path()..moveTo(i, 0)..cubicTo(i + (rand.nextDouble() - 0.5) * w * 0.1, h * 0.33, i + (rand.nextDouble() - 0.5) * w * 0.1, h * 0.66, i + (rand.nextDouble() - 0.5) * w * 0.05, h);
      canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.1)..style = PaintingStyle.stroke..strokeWidth = isWindows ? 1.4 : 2.0);
    }
    canvas.restore();

    canvas.save();
    canvas.clipRRect(plinthRRect);
    final flakeRand = Random(4242);
    for (int i = 0; i < (isWindows ? 2400 : 900); i++) {
      canvas.drawCircle(Offset(flakeRand.nextDouble() * w, flakeRand.nextDouble() * h), (isWindows ? 0.28 : 0.4) + flakeRand.nextDouble() * (isWindows ? 0.55 : 0.6), Paint()..color = Colors.white.withValues(alpha: 0.04 + (flakeRand.nextDouble() * 0.05)));
    }
    canvas.restore();

    final speakerSize = w * 0.24;
    final speakerRect = Rect.fromLTWH(plinthRect.right - speakerSize - w * 0.05, plinthRect.bottom - speakerSize - w * 0.05, speakerSize, speakerSize);
    canvas.drawRRect(RRect.fromRectAndRadius(speakerRect, Radius.circular(w * 0.02)), Paint()..color = Color.lerp(const Color(0xFF222222), accentColor, 0.15)!);
    canvas.drawRRect(RRect.fromRectAndRadius(speakerRect.deflate(w * 0.01), Radius.circular(w * 0.01)), Paint()..color = Color.lerp(const Color(0xFF000000), accentColor, 0.10)!);

    final grillInner = speakerRect.deflate(w * 0.018);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(grillInner, Radius.circular(w * 0.014)));
    canvas.drawRect(grillInner, Paint()..shader = ui.Gradient.radial(grillInner.center, grillInner.shortestSide * 0.65, [const Color(0xFF0A0A0A), const Color(0xFF000000)], [0.0, 1.0]));
    final holeSpacing = w * (isWindows ? 0.013 : 0.016);
    final holeR = w * (isWindows ? 0.0032 : 0.0038);
    for (double y = grillInner.top; y <= grillInner.bottom; y += holeSpacing) {
      for (double x = grillInner.left; x <= grillInner.right; x += holeSpacing) {
        final p = Offset(x, y);
        if ((p - grillInner.center).distance > grillInner.shortestSide * 0.48) continue;
        canvas.drawCircle(p, holeR, Paint()..color = const Color(0xFF000000));
        canvas.drawCircle(p.translate(-holeR * 0.35, -holeR * 0.35), holeR * 0.55, Paint()..color = Colors.white.withValues(alpha: 0.05)..blendMode = BlendMode.plus);
      }
    }
    canvas.restore();

    final basePlateRect = Rect.fromCenter(center: Offset(w * 0.84, h * 0.38), width: w * 0.17, height: h * 0.47);
    canvas.drawRRect(RRect.fromRectAndRadius(basePlateRect, Radius.circular(w * 0.07)), Paint()..color = Colors.black.withValues(alpha: 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawRRect(RRect.fromRectAndRadius(basePlateRect, Radius.circular(w * 0.07)), Paint()..shader = ui.Gradient.linear(basePlateRect.topLeft, basePlateRect.bottomRight, [Color.lerp(const Color(0xFF2A2A2A), accentColor, 0.18)!, Color.lerp(const Color(0xFF111111), accentColor, 0.12)!]));
    canvas.drawCircle(basePlateRect.topCenter.translate(0, w * 0.032), w * 0.01, Paint()..color = const Color(0xFF444444));
    canvas.drawCircle(basePlateRect.bottomCenter.translate(0, -w * 0.032), w * 0.01, Paint()..color = const Color(0xFF444444));

    canvas.drawCircle(platterCenter, platterRadius, Paint()..color = Color.lerp(const Color(0xFF181818), accentColor, 0.15)!);
    final hingeL = Rect.fromCenter(center: Offset(w * 0.25, h * 0.03), width: w * 0.08, height: h * 0.04);
    canvas.drawRRect(RRect.fromRectAndRadius(hingeL, const Radius.circular(2)), Paint()..color = Color.lerp(const Color(0xFF222222), accentColor, 0.20)!);
    canvas.drawRect(Rect.fromCenter(center: hingeL.center, width: w * 0.06, height: h * 0.01), Paint()..color = Color.lerp(const Color(0xFF444444), accentColor, 0.22)!);
    final hingeR = Rect.fromCenter(center: Offset(w * 0.75, h * 0.03), width: w * 0.08, height: h * 0.04);
    canvas.drawRRect(RRect.fromRectAndRadius(hingeR, const Radius.circular(2)), Paint()..color = Color.lerp(const Color(0xFF222222), accentColor, 0.20)!);
    canvas.drawRect(Rect.fromCenter(center: hingeR.center, width: w * 0.06, height: h * 0.01), Paint()..color = Color.lerp(const Color(0xFF444444), accentColor, 0.22)!);

    final leverBaseRect = Rect.fromCenter(center: Offset(w * 0.24, h * 0.88), width: w * 0.06, height: w * 0.1);
    canvas.drawRRect(RRect.fromRectAndRadius(leverBaseRect, Radius.circular(w * 0.01)), Paint()..color = Color.lerp(const Color(0xFF111111), accentColor, 0.18)!);
    canvas.drawRRect(RRect.fromRectAndRadius(leverBaseRect.deflate(w * 0.015), Radius.circular(w * 0.005)), Paint()..color = Color.lerp(const Color(0xFF000000), accentColor, 0.14)!);
    final rpmBaseRect = Rect.fromCenter(center: Offset(w * 0.60, h * 0.88), width: w * 0.08, height: h * 0.05);
    canvas.drawRRect(RRect.fromRectAndRadius(rpmBaseRect, Radius.circular(w * 0.01)), Paint()..color = const Color(0xFF111111));

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Offset center) {
      textPainter.text = TextSpan(text: text, style: TextStyle(color: const Color(0xFF666666), fontSize: w * 0.015, fontWeight: FontWeight.bold, fontFamily: 'Courier'));
      textPainter.layout();
      textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
    }
    drawLabel("33", rpmBaseRect.centerLeft.translate(w * 0.02, 0));
    drawLabel("45", rpmBaseRect.centerRight.translate(-w * 0.02, 0));
    drawLabel("START", Offset(w * 0.24, h * 0.88).translate(0, w * 0.04));
    drawLabel("STOP", Offset(w * 0.24, h * 0.88).translate(0, -w * 0.04));
    drawLabel("PITCH", Offset(w * 0.12, h * 0.88).translate(0, w * 0.055));

    final powerLightPos = Offset(w * 0.08, h * 0.08);
    canvas.drawCircle(powerLightPos, w * 0.025, Paint()..color = Color.lerp(const Color(0xFF000000), accentColor, 0.12)!);
    canvas.drawCircle(powerLightPos, w * 0.02, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Color.lerp(const Color(0xFF444444), accentColor, 0.25)!);
    canvas.drawCircle(powerLightPos, w * 0.015, Paint()..color = Color.lerp(const Color(0xFF002200), accentColor, 0.35)!);
  }
}

class _TurntableSpinnerPainter extends CustomPainter {
  final double progress;
  final double? armProgressOverride;
  final double discAngle;
  final double velocity;
  final Color strobeColor;
  final double knobAngle;
  final ui.Image? labelImage;
  final ui.Image? dustImage;
  final bool strobeEnabled;
  final bool is33RPM;
  final bool isPlaying;
  final bool lowPerformanceMode;
  final int perfTier;
  final Color accentColor;
  final Color accentHighlight;
  final double tonearmPulse;
  final double groovePulse;
  final double beatPulse;
  final double cueLift;
  final ui.Image? strobeRingImage;

  _TurntableSpinnerPainter({
    required this.progress, this.armProgressOverride, required this.discAngle,
    this.velocity = 1.0, this.strobeColor = const Color(0xFF00FF00), this.knobAngle = 0.0,
    this.labelImage, this.dustImage, this.strobeEnabled = true, this.is33RPM = true,
    this.isPlaying = false, this.lowPerformanceMode = false, this.perfTier = 2,
    required this.accentColor, required this.accentHighlight, this.tonearmPulse = 0.0, this.groovePulse = 0.0,
    this.beatPulse = 0.0, this.cueLift = 1.0,
    this.strobeRingImage = null,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final effectiveProgress = (armProgressOverride ?? progress).clamp(0.0, 1.0);
    final tier = perfTier.clamp(0, 2);
    final minimal = tier >= 1;
    final full = tier >= 2 && !lowPerformanceMode;
    final isWindows = Platform.isWindows;
    final dpr = ui.PlatformDispatcher.instance.views.isNotEmpty ? ui.PlatformDispatcher.instance.views.first.devicePixelRatio : 1.0;
    final hq = isWindows && full;
    final blurMul = hq ? (0.80 / max(1.0, dpr)).clamp(0.55, 0.90) : 1.0;
    final platterRadius = w * 0.33;
    final platterCenter = Offset(w * 0.42, h * 0.45);

    canvas.save();
    canvas.translate(platterCenter.dx, platterCenter.dy);
    canvas.rotate(discAngle);
    canvas.translate(-platterCenter.dx, -platterCenter.dy);

    final platterR = platterRadius * 0.99;
    final matR = platterRadius * 0.93;
    final recordR = platterRadius * 0.90;

    canvas.drawCircle(platterCenter, platterR, Paint()..shader = ui.Gradient.radial(platterCenter, platterR, [Color.lerp(const Color(0xFF1A1A1A), accentColor, 0.22)!, Color.lerp(const Color(0xFF0C0C0C), accentColor, 0.16)!, Color.lerp(const Color(0xFF191919), accentColor, 0.20)!], [0.0, 0.72, 1.0]));
    canvas.drawCircle(platterCenter, platterR, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.010..shader = ui.Gradient.linear(platterCenter.translate(-platterR, -platterR), platterCenter.translate(platterR, platterR), [Colors.white.withValues(alpha: 0.045), Colors.transparent, Colors.black.withValues(alpha: 0.22)], [0.0, 0.55, 1.0]));
    canvas.drawCircle(platterCenter, matR, Paint()..shader = ui.Gradient.radial(platterCenter, matR, [Color.lerp(const Color(0xFF121212), accentColor, 0.18)!, Color.lerp(const Color(0xFF0B0B0B), accentColor, 0.12)!], [0.0, 1.0]));
    canvas.drawCircle(platterCenter, matR, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.006..color = Colors.white.withValues(alpha: 0.018));
    canvas.drawCircle(platterCenter.translate(0, w * 0.0015), recordR, Paint()..color = Colors.black.withValues(alpha: 0.26)..maskFilter = full ? MaskFilter.blur(BlurStyle.normal, w * 0.006 * blurMul) : null);
    canvas.drawCircle(platterCenter, recordR, Paint()..shader = ui.Gradient.radial(platterCenter, recordR, const [Color(0xFF0B0B0B), Color(0xFF050505), Color(0xFF0A0A0A)], [0.0, 0.72, 1.0]));
    canvas.drawCircle(platterCenter, recordR, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.008..shader = ui.Gradient.linear(platterCenter.translate(-recordR, -recordR), platterCenter.translate(recordR, recordR), [Colors.white.withValues(alpha: 0.03), Colors.transparent, Colors.black.withValues(alpha: 0.20)], [0.0, 0.6, 1.0]));

    // Accent rim highlight (shares user accent color)
    canvas.drawCircle(platterCenter, platterR, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.004
      ..color = accentHighlight.withValues(alpha: 0.45));

    if (full) {
      final grRange = recordR * 0.95 - recordR * 0.35;
      final grStep = hq ? 1.25 : 2.0;
      final grSteps = (grRange / grStep).floor();
      for (int i = 0; i < grSteps; i++) {
        canvas.drawCircle(platterCenter, recordR * 0.35 + i * grStep, Paint()..style = PaintingStyle.stroke..strokeWidth = (hq ? 0.22 : 0.35) + groovePulse * (hq ? 0.16 : 0.25)..color = Colors.white.withValues(alpha: ((hq ? 0.013 : 0.02) + groovePulse * (hq ? 0.04 : 0.05) * (1 - i / max(1, grSteps))) * 0.55));
      }
    }

    if (hq) {
      final rand = Random(421);
      final sp = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
      for (int i = 0; i < 56; i++) {
        sp..strokeWidth = w * (0.00055 + rand.nextDouble() * 0.00070)..color = Colors.white.withValues(alpha: 0.010 + rand.nextDouble() * 0.014);
        canvas.drawArc(Rect.fromCircle(center: platterCenter, radius: recordR * (0.44 + rand.nextDouble() * 0.50)), rand.nextDouble() * pi * 2, (0.05 + rand.nextDouble() * 0.14) * (rand.nextBool() ? 1.0 : -1.0), false, sp);
      }
    }

    if (dustImage != null && full) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: platterCenter, radius: recordR)));
      canvas.drawImageRect(dustImage!, Rect.fromLTWH(0, 0, dustImage!.width.toDouble(), dustImage!.height.toDouble()), Rect.fromCircle(center: platterCenter, radius: recordR), Paint()..filterQuality = hq ? FilterQuality.high : FilterQuality.low..colorFilter = ColorFilter.mode(Colors.white.withValues(alpha: 0.10), BlendMode.modulate));
      canvas.restore();
    }

    final labelR = recordR * 0.34;
    canvas.drawCircle(platterCenter, labelR, Paint()..color = HSLColor.fromColor(accentColor).withLightness(0.4).withSaturation(0.2).toColor());

    if (minimal && !lowPerformanceMode) {
      canvas.drawCircle(platterCenter, labelR, Paint()..shader = ui.Gradient.linear(platterCenter.translate(-labelR, -labelR), platterCenter.translate(labelR, labelR), [Colors.white.withValues(alpha: 0.06), Colors.transparent, Colors.black.withValues(alpha: 0.06)], [0.0, 0.6, 1.0]));
      if (full) {
        final fr = Random(9901);
        for (int i = 0; i < 260; i++) {
          final ra = labelR * sqrt(fr.nextDouble()); final an = fr.nextDouble() * 2 * pi;
          canvas.drawCircle(platterCenter + Offset(cos(an) * ra, sin(an) * ra), 0.35 + fr.nextDouble() * 0.45, Paint()..color = Color.lerp(Colors.white, accentColor, fr.nextDouble())!.withValues(alpha: 0.05));
        }
      }
    }

    if (labelImage != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: platterCenter, radius: labelR)));
      final iw = labelImage!.width.toDouble(); final ih = labelImage!.height.toDouble();
      final sw = min(iw, ih);
      canvas.drawImageRect(labelImage!, Rect.fromLTWH((iw - sw) / 2, (ih - sw) / 2, sw, sw), Rect.fromCircle(center: platterCenter, radius: labelR), Paint()..isAntiAlias = true..filterQuality = FilterQuality.high);
      canvas.restore();
    }
    canvas.drawCircle(platterCenter, labelR * 0.15, Paint()..color = const Color(0xFF050505));
    canvas.restore();

    if (minimal && !lowPerformanceMode) {
      final shimmer = (0.5 + 0.5 * sin(discAngle * 1.4)) * 0.04 * velocity.clamp(0.0, 1.0);
      final wedge = Path()..moveTo(platterCenter.dx, platterCenter.dy)..arcTo(Rect.fromCircle(center: platterCenter, radius: recordR), -0.85 - 0.28, 0.56, false)..close();
      canvas.drawPath(Path.combine(PathOperation.difference, wedge, Path()..addOval(Rect.fromCircle(center: platterCenter, radius: labelR))), Paint()..shader = ui.Gradient.linear(platterCenter.translate(cos(-0.85) * recordR, sin(-0.85) * recordR), platterCenter.translate(-cos(-0.85) * recordR, -sin(-0.85) * recordR), [Colors.white.withValues(alpha: 0.10 + shimmer), Colors.transparent], [0.0, 1.0])..blendMode = BlendMode.plus);
      canvas.drawCircle(platterCenter, recordR, Paint()..shader = ui.Gradient.radial(platterCenter, recordR, [Colors.transparent, Colors.black.withValues(alpha: 0.12)], [0.75, 1.0])..blendMode = BlendMode.multiply);
    }

    final spindleR = platterRadius * 0.025;
    canvas.drawCircle(platterCenter, spindleR, Paint()..shader = ui.Gradient.linear(platterCenter.translate(-spindleR, -spindleR), platterCenter.translate(spindleR, spindleR), [const Color(0xFF888888), Colors.white, const Color(0xFF888888)], [0.0, 0.5, 1.0]));
    canvas.drawCircle(platterCenter.translate(-spindleR * 0.3, -spindleR * 0.3), spindleR * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.65));

    final knobCenter = Offset(w * 0.12, h * 0.88); final knobR = w * 0.07;
    canvas.drawCircle(knobCenter.translate(2, 2), knobR, Paint()..color = Colors.black.withValues(alpha: 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(knobCenter, knobR, Paint()..shader = ui.Gradient.radial(knobCenter, knobR, [const Color(0xFF222222), const Color(0xFF000000)]));
    canvas.drawLine(knobCenter, knobCenter + Offset.fromDirection(-pi / 4 + knobAngle, knobR * 0.8), Paint()..color = accentHighlight..strokeWidth = 2..strokeCap = StrokeCap.round);

    final lbCenter = Offset(w * 0.24, h * 0.88); final lhRect = Rect.fromCenter(center: lbCenter.translate(0, isPlaying ? w * 0.02 : -w * 0.02), width: w * 0.04, height: w * 0.02);
    canvas.drawRect(Rect.fromCenter(center: lbCenter, width: w * 0.01, height: h * 0.06), Paint()..color = const Color(0xFF111111));
    canvas.drawRRect(RRect.fromRectAndRadius(lhRect, const Radius.circular(2)), Paint()..shader = ui.Gradient.linear(lhRect.topLeft, lhRect.bottomRight, [const Color(0xFFFFFFFF), const Color(0xFFAAAAAA), const Color(0xFF555555)], [0.0, 0.5, 1.0]));

    final rbCenter = Offset(w * 0.60, h * 0.88); final rhRect = Rect.fromCenter(center: rbCenter.translate(is33RPM ? -w * 0.02 : w * 0.02, 0), width: w * 0.02, height: w * 0.04);
    canvas.drawRRect(RRect.fromRectAndRadius(rhRect, const Radius.circular(2)), Paint()..color = const Color(0xFFCCCCCC));

    final plPos = Offset(w * 0.08, h * 0.08); final inte = velocity.clamp(0.0, 1.0);
    if (inte > 0.01) {
      final gc = Color.lerp(const Color(0xFF003300), const Color(0xFF00FF00), inte)!;
      if (!lowPerformanceMode) canvas.drawCircle(plPos, w * 0.025 * inte, Paint()..shader = ui.Gradient.radial(plPos, w * 0.03, [gc.withValues(alpha: 0.8 * inte), Colors.transparent])..blendMode = BlendMode.plus);
      canvas.drawCircle(plPos, w * 0.015, Paint()..color = gc.withValues(alpha: inte));
    }

    final pivot = Offset(w * 0.84, h * 0.38); final pivotToSpindle = (platterCenter - pivot).distance; final armLength = pivotToSpindle + (w * 0.04);
    final ra = atan2(platterCenter.dy - pivot.dy, platterCenter.dx - pivot.dx) - 0.4; final rs = pivot + Offset.fromDirection(ra, armLength);
    final ar = recordR * ui.lerpDouble(0.92, 0.35, effectiveProgress)!;
    Offset sty;
    if (cueLift >= 0.95 && armProgressOverride == null) sty = rs;
    else if (pivotToSpindle > armLength + ar || pivotToSpindle < (armLength - ar).abs()) sty = rs;
    else {
      final a_ = (pivotToSpindle * pivotToSpindle - ar * ar + armLength * armLength) / (2 * pivotToSpindle);
      final h_ = sqrt(max(0, armLength * armLength - a_ * a_)); final p2_ = pivot + (platterCenter - pivot) * (a_ / pivotToSpindle);
      sty = Offset(p2_.dx + h_ * (platterCenter.dy - pivot.dy) / pivotToSpindle, p2_.dy - h_ * (platterCenter.dx - pivot.dx) / pivotToSpindle);
    }
    Offset rot(Offset p, Offset c, double a) { final dx = p.dx - c.dx; final dy = p.dy - c.dy; return Offset(c.dx + (dx * cos(a) - dy * sin(a)), c.dy + (dx * sin(a) + dy * cos(a))); }
    var adj = rot(sty, pivot, tonearmPulse * 0.25); final aAng = atan2(adj.dy - pivot.dy, adj.dx - pivot.dx);
    final lif = cueLift.clamp(0.0, 1.0); final lo = Offset(0, -lif * 10 - tonearmPulse * 3);
    if (lif <= 0.15 && isPlaying && effectiveProgress < 0.995 && !lowPerformanceMode) adj += Offset(-sin(aAng), cos(aAng)) * ((sin(discAngle * 23.0) + sin(discAngle * 47.0)) * (w * 0.00022));

    canvas.drawLine(pivot.translate(4 + lif * 10, 4 + lif * 10), adj.translate(4 + lif * 10, 4 + lif * 10), Paint()..color = Colors.black.withValues(alpha: 0.3)..strokeWidth = w * 0.0135..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    if (full) {
      canvas.save(); canvas.clipPath(Path()..addOval(Rect.fromCircle(center: platterCenter, radius: recordR)));
      canvas.drawLine(pivot, adj, Paint()..color = Colors.white.withValues(alpha: 0.05)..strokeWidth = w * 0.0135..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.restore();
    }

    canvas.drawCircle(pivot, w * 0.05, Paint()..shader = ui.Gradient.linear(pivot.translate(-10, -10), pivot.translate(10, 10), [Color.lerp(const Color(0xFF333333), accentColor, 0.22)!, Color.lerp(const Color(0xFF111111), accentColor, 0.15)!]));
    canvas.drawCircle(pivot.translate(w * 0.06, w * 0.02), w * 0.015, Paint()..color = Color.lerp(const Color(0xFF222222), accentColor, 0.18)!);
    canvas.save(); canvas.translate(pivot.dx, pivot.dy); canvas.rotate(aAng);
    canvas.drawRect(Rect.fromLTWH(-w * 0.12, -4, w * 0.12, 8), Paint()..color = Color.lerp(const Color(0xFF222222), accentColor, 0.20)!);
    final cw = Rect.fromCenter(center: Offset(-w * 0.1, 0), width: w * 0.08, height: w * 0.08);
    canvas.drawRRect(RRect.fromRectAndRadius(cw, const Radius.circular(4)), Paint()..shader = ui.Gradient.linear(cw.topLeft, cw.bottomRight, [Color.lerp(const Color(0xFF444444), accentColor, 0.25)!, Color.lerp(const Color(0xFF111111), accentColor, 0.18)!]));
    canvas.restore();

    canvas.drawLine(pivot, adj.translate(lo.dx, lo.dy), Paint()..shader = ui.Gradient.linear(pivot, adj, [const Color(0xFFCCCCCC), const Color(0xFFEEEEEE), const Color(0xFFCCCCCC)], [0.0, 0.5, 1.0])..strokeWidth = w * 0.0135);

    canvas.save(); canvas.translate(adj.dx + lo.dx, adj.dy + lo.dy); canvas.rotate(aAng + 0.4);
    canvas.drawPath(Path()..moveTo(-w * 0.012, -w * 0.018)..lineTo(w * 0.07, -w * 0.013)..lineTo(w * 0.07, w * 0.013)..lineTo(-w * 0.012, w * 0.018)..close(), Paint()..color = Color.lerp(const Color(0xFF111111), accentColor, 0.22)!);
    canvas.drawRect(Rect.fromLTWH(w * 0.018, -w * 0.0085, w * 0.035, w * 0.018), Paint()..color = Color.lerp(const Color(0xFF333333), accentColor, 0.18)!);
    canvas.drawCircle(Offset(w * 0.045, 0), w * 0.004, Paint()..color = Colors.red);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TurntableSpinnerPainter oldDelegate) => true;
}

/// Extremely cheap painter that just draws a pre-rendered static base image.
/// This replaces the heavy _TurntableBasePainter on every frame after first generation.
class _CachedStaticBasePainter extends CustomPainter {
  final ui.Image image;

  _CachedStaticBasePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the cached image to fill the canvas exactly
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _CachedStaticBasePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
