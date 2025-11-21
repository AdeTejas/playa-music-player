import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../services/player_controller.dart';
import '../services/database_service.dart';
import '../models/song_metadata.dart';
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

class _TurntableDeckState extends State<TurntableDeck> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  
  // Physics state
  double _discAngle = 0.0;
  double _angularVelocity = 0.0; // 0.0 to 1.0 (1.0 = 33.3 RPM)
  double _targetVelocity = 0.0;
  
  // Interaction state
  double _dragVelocity = 0.0;
  bool _isDragging = false;
  double? _lastDragAngle;
  Duration? _dragPosition;
  
  // Pitch Control State
  bool _isTurningKnob = false;
  double _pitchValue = 1.0; // 1.0 = normal speed
  double? _lastKnobAngle;
  
  // RPM State
  bool _is33RPM = true;

  // Strobe Light State
  final bool _strobeEnabled = true;

  // Label Image State
  ui.Image? _labelImage;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  // Constants
  static const double _kMaxRPM = 33.3333;
  static const double _kRadPerSecond = (_kMaxRPM * 2 * pi) / 60.0; // real angular speed per second

  Duration? _lastTickTime;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.isVisible) {
      _ticker.start();
    }
    
    // Listen to playback state for motor control
    widget.ctrl.player.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() {
        _targetVelocity = playing ? 1.0 : 0.0;
        if (playing) {
           HapticFeedback.selectionClick(); // Tactile "Click" on start
        } else {
           HapticFeedback.lightImpact(); // Subtle thud on stop
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
    }
    
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        if (!_ticker.isActive) _ticker.start();
      } else {
        if (_ticker.isActive) _ticker.stop();
      }
    }
  }

  Future<void> _updateLabelImage() async {
    final item = widget.item;
    
    // Target size for the label (optimization)
    const int targetSize = 300; 

    // 1. Try to get image from song ID (Android MediaStore)
    if (item?.extras != null && item!.extras!.containsKey('songId')) {
      try {
        final songId = item.extras!['songId'] as int;
        final bytes = await oaq.OnAudioQuery().queryArtwork(
          songId,
          oaq.ArtworkType.AUDIO,
          format: oaq.ArtworkFormat.JPEG,
          size: 1000,
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
          
          if (mounted) setState(() => _labelImage = frame.image);
          return;
        }
      } catch (e) {
        print('Error loading artwork from ID: $e');
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
        _imageStream = provider.resolve(createLocalImageConfiguration(context));
        
        if (_imageStream!.key != oldStream?.key) {
          final listener = ImageStreamListener(
            (info, _) {
              if (mounted) setState(() => _labelImage = info.image);
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
    if (_labelImage != null) setState(() => _labelImage = null);
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
    
    // Update progress for smooth animation
    final p = widget.ctrl.player;
    if (p.duration != null && p.duration!.inMilliseconds > 0) {
      _progress = (p.position.inMilliseconds / p.duration!.inMilliseconds).clamp(0.0, 1.0);
      
      // Auto-stop at end of record
      if (_progress >= 1.0 && widget.ctrl.player.playing) {
        widget.ctrl.player.pause();
        widget.ctrl.player.seek(Duration.zero);
        _progress = 0.0;
        _targetVelocity = 0.0;
        HapticFeedback.mediumImpact();
      }
    } else {
      _progress = 0.0;
    }

    if (_isDragging && !_isTurningKnob) {
      // While dragging, velocity is determined by gesture
      _angularVelocity = _dragVelocity;
      // Apply drag rotation
      setState(() {
        _discAngle += _dragVelocity * dt * 6.0; // scaled for time delta
        if (_discAngle > 2 * pi) _discAngle -= 2 * pi;
        if (_discAngle < 0) _discAngle += 2 * pi;
      });
      // Decay drag velocity slightly
      _dragVelocity *= 0.9;
    } else {
      // 1. Physics Simulation (Inertia)
      // Smoothly interpolate current velocity towards target velocity
      // Adjust target velocity based on pitch and RPM!
      final rpmMult = _is33RPM ? 1.0 : 1.35;
      final target = _targetVelocity * _pitchValue * rpmMult;
      
      // Time-corrected inertia for smooth acceleration/deceleration independent of frame rate
      // Using a decay factor: velocity approaches target exponentially
      final decay = 2.0; // Responsiveness factor
      final factor = 1.0 - exp(-decay * dt);
      
      if ((_angularVelocity - target).abs() > 0.001) {
        _angularVelocity += (target - _angularVelocity) * factor;
      } else {
        _angularVelocity = target;
      }

      // 2. Apply rotation
      if (_angularVelocity.abs() > 0.001 || widget.ctrl.player.playing) {
        setState(() {
          _discAngle += _kRadPerSecond * _angularVelocity * 1.5 * dt; // 1.5x speed factor for visual flair
          if (_discAngle > 2 * pi) _discAngle -= 2 * pi;
          if (_discAngle < 0) _discAngle += 2 * pi;
        });
      } else if (_progress > 0) {
         // Ensure we still repaint for progress updates even if stopped (e.g. seeking while paused)
         setState(() {});
      }
    }
  }

  void _handlePanStart(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final w = box.size.width;
    final h = box.size.height;
    final local = box.globalToLocal(details.globalPosition);
    
    // Check if touching Knob (Updated for new layout)
    final knobCenter = Offset(w * 0.12, h * 0.88);
    final knobR = w * 0.07;
    final knobRect = Rect.fromCircle(center: knobCenter, radius: knobR * 1.5); // Larger hit area
    
    if (knobRect.contains(local)) {
      _isTurningKnob = true;
      _lastKnobAngle = atan2(local.dy - knobCenter.dy, local.dx - knobCenter.dx);
      HapticFeedback.selectionClick();
      return;
    }

    _isDragging = true;
    _dragVelocity = 0;
    _dragPosition = widget.ctrl.player.position;
    
    // Calculate initial angle relative to center
    final center = box.size.center(Offset.zero);
    _lastDragAngle = atan2(local.dy - center.dy, local.dx - center.dy);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    
    if (_isTurningKnob) {
      final w = box.size.width;
      final h = box.size.height;
      final knobCenter = Offset(w * 0.12, h * 0.88);
      
      final currentAngle = atan2(local.dy - knobCenter.dy, local.dx - knobCenter.dx);
      if (_lastKnobAngle != null) {
        var delta = currentAngle - _lastKnobAngle!;
        if (delta > pi) delta -= 2 * pi;
        if (delta < -pi) delta += 2 * pi;
        
        // Update pitch
        setState(() {
          // Map rotation to pitch (0.8 to 1.2)
          // Sensitivity: 1 full rotation = 0.4 change?
          _pitchValue = (_pitchValue + delta * 0.2).clamp(0.8, 1.2);
        });
        widget.ctrl.setSpeed(_pitchValue);
      }
      _lastKnobAngle = currentAngle;
      return;
    }
    
    final center = box.size.center(Offset.zero);
    final currentAngle = atan2(local.dy - center.dy, local.dx - center.dy);
    
    if (_lastDragAngle != null) {
      var delta = currentAngle - _lastDragAngle!;
      if (delta > pi) delta -= 2 * pi;
      if (delta < -pi) delta += 2 * pi;
      
      _dragVelocity = delta * 5.0; // Boost for feel
      
      // Seek audio!
      final p = widget.ctrl.player;
      if (p.duration != null && _dragPosition != null) {
        final seekDelta = Duration(milliseconds: (delta * 1000).toInt()); // 1 rad = 1 sec
        final newPos = _dragPosition! + seekDelta;
        if (newPos >= Duration.zero && newPos <= p.duration!) {
           _dragPosition = newPos;
           p.seek(newPos);
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
    final box = context.findRenderObject() as RenderBox;
    final w = box.size.width;
    final h = box.size.height;
    final local = box.globalToLocal(details.globalPosition);

    // Lever Hitbox (Moved to Bottom Left, right of Knob)
    final leverRect = Rect.fromCenter(center: Offset(w * 0.24, h * 0.88), width: w * 0.12, height: w * 0.12);
    if (leverRect.contains(local)) {
      if (widget.ctrl.player.playing) {
        widget.ctrl.player.pause();
      } else {
        widget.ctrl.player.play();
      }
      HapticFeedback.mediumImpact();
      return;
    }

    // RPM Hitbox (Moved further left)
    final rpmRect = Rect.fromCenter(center: Offset(w * 0.60, h * 0.88), width: w * 0.12, height: w * 0.08);
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
    if (_imageListener != null && _imageStream != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.ctrl.player;
    // Generate a unique color for this track
    final baseHue = widget.item != null 
        ? (widget.item!.title.hashCode % 360).toDouble()
        : 120.0;
    // Cycle through colors based on disc rotation for more dynamic range
    final hueShift = (_discAngle * 180 / pi) % 360;
    final trackColor = HSVColor.fromAHSV(1.0, (baseHue + hueShift) % 360, 0.85, 1.0).toColor();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight) * 0.95;
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
                        // Fetch BPM if available
                        return FutureBuilder<SongMetadata?>(
                          future: widget.item != null 
                              ? DatabaseService.instance.getSongMetadata(widget.item!.id)
                              : Future.value(null),
                          builder: (context, metaSnap) {
                            final bpm = metaSnap.data?.bpm;
                            
                            return StreamBuilder<double>(
                              stream: player.volumeStream,
                              builder: (context, volSnap) {
                                final volume = volSnap.data ?? 1.0;
                                return HighTechSpeaker(
                                  isPlaying: isPlaying,
                                  bpm: bpm,
                                  volume: volume,
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
                        final pos = _dragPosition ?? posSnap.data ?? Duration.zero;
                        final dur = player.duration ?? const Duration(milliseconds: 1);
                        final progress = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;

                        return CustomPaint(
                          size: Size(size, size),
                          painter: _TurntableSpinnerPainter(
                            progress: progress.clamp(0.0, 1.0),
                            discAngle: _discAngle,
                            velocity: _angularVelocity,
                            strobeColor: trackColor,
                            knobAngle: (_pitchValue - 1.0) * 5.0,
                            labelImage: _labelImage,
                            strobeEnabled: _strobeEnabled,
                            is33RPM: _is33RPM,
                            isPlaying: player.playing,
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
}

class _TurntableBasePainter extends CustomPainter {
  final bool strobeEnabled;
  final Color strobeColor;

  _TurntableBasePainter({required this.strobeEnabled, required this.strobeColor});

  @override
  bool shouldRepaint(covariant _TurntableBasePainter oldDelegate) =>
      oldDelegate.strobeEnabled != strobeEnabled || oldDelegate.strobeColor != strobeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. PLINTH (Main Chassis)
    final plinthRect = Rect.fromLTWH(w * 0.02, h * 0.02, w * 0.96, h * 0.96);
    final plinthRRect = RRect.fromRectAndRadius(plinthRect, Radius.circular(w * 0.04));

    // Layout Constants - REFINED SCALES
    final platterRadius = w * 0.36;
    final platterCenter = Offset(w * 0.42, h * 0.45); // Slightly up-left to make room
    
    // Wood Texture
    final plinthPaint = Paint()
      ..shader = ui.Gradient.linear(
        plinthRect.topLeft,
        plinthRect.bottomRight,
        [const Color(0xFF8D5524), const Color(0xFF5D3A1A)], // Richer Walnut
      );
    canvas.drawRRect(plinthRRect, plinthPaint);

    // Wood Grain
    canvas.save();
    canvas.clipRRect(plinthRRect);
    final grainPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    final rand = Random(42);
    for (double i = 0; i < w * 1.5; i += w * 0.02) {
      final path = Path();
      path.moveTo(i, 0);
      path.cubicTo(
        i + (rand.nextDouble() - 0.5) * w * 0.1, h * 0.33,
        i + (rand.nextDouble() - 0.5) * w * 0.1, h * 0.66,
        i + (rand.nextDouble() - 0.5) * w * 0.05, h
      );
      canvas.drawPath(path, grainPaint);
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
      RRect.fromRectAndRadius(speakerRect.deflate(w * 0.01), Radius.circular(w * 0.01)),
      Paint()..color = const Color(0xFF000000),
    );
    
    // 3. TONEARM BASE PLATE (Right Side)
    final basePlateRect = Rect.fromCenter(
      center: Offset(w * 0.84, h * 0.38),
      width: w * 0.2,
      height: h * 0.55,
    );
    
    final basePlatePath = Path();
    basePlatePath.addRRect(RRect.fromRectAndRadius(basePlateRect, Radius.circular(w * 0.08)));
    
    // Shadow
    canvas.drawPath(
      basePlatePath.shift(Offset(w * 0.01, w * 0.01)),
      Paint()..color = Colors.black.withValues(alpha: 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    
    // Plate
    canvas.drawPath(
      basePlatePath,
      Paint()..shader = ui.Gradient.linear(
        basePlateRect.topLeft,
        basePlateRect.bottomRight,
        [const Color(0xFF2A2A2A), const Color(0xFF111111)],
      ),
    );
    
    // Screws
    final screwR = w * 0.01;
    final screwP = Paint()..color = const Color(0xFF444444);
    canvas.drawCircle(basePlateRect.topCenter.translate(0, w * 0.04), screwR, screwP);
    canvas.drawCircle(basePlateRect.bottomCenter.translate(0, -w * 0.04), screwR, screwP);

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
    final hingeL = Rect.fromCenter(center: Offset(w * 0.25, h * 0.03), width: w * 0.08, height: h * 0.04);
    canvas.drawRRect(RRect.fromRectAndRadius(hingeL, const Radius.circular(2)), hingePaint);
    canvas.drawRect(Rect.fromCenter(center: hingeL.center, width: w * 0.06, height: h * 0.01), hingeDetailPaint);

    // Right Hinge
    final hingeR = Rect.fromCenter(center: Offset(w * 0.75, h * 0.03), width: w * 0.08, height: h * 0.04);
    canvas.drawRRect(RRect.fromRectAndRadius(hingeR, const Radius.circular(2)), hingePaint);
    canvas.drawRect(Rect.fromCenter(center: hingeR.center, width: w * 0.06, height: h * 0.01), hingeDetailPaint);

    // 6. START/STOP LEVER BASE (Moved to Bottom Left, right of Knob)
    final leverBaseRect = Rect.fromCenter(center: Offset(w * 0.24, h * 0.88), width: w * 0.06, height: w * 0.1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(leverBaseRect, Radius.circular(w * 0.01)),
      Paint()..color = const Color(0xFF111111),
    );
    // Slot
    canvas.drawRRect(
      RRect.fromRectAndRadius(leverBaseRect.deflate(w * 0.015), Radius.circular(w * 0.005)),
      Paint()..color = const Color(0xFF000000),
    );

    // 7. RPM SWITCH BASE (Moved further left of Speaker)
    final rpmBaseRect = Rect.fromCenter(center: Offset(w * 0.60, h * 0.88), width: w * 0.08, height: w * 0.05);
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
      textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
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
    canvas.drawCircle(powerLightPos, w * 0.025, Paint()..color = const Color(0xFF000000));
    // Metal Ring
    canvas.drawCircle(powerLightPos, w * 0.02, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF444444));
    // Bulb (Off state)
    canvas.drawCircle(powerLightPos, w * 0.015, Paint()..color = const Color(0xFF002200)); 
  }
}

class _TurntableSpinnerPainter extends CustomPainter {
  final double progress;
  final double discAngle;
  final double velocity; // 0.0 to 1.0
  final Color strobeColor;
  final double knobAngle;
  final ui.Image? labelImage;
  final bool strobeEnabled;
  final bool is33RPM;
  final bool isPlaying;

  _TurntableSpinnerPainter({
    required this.progress, 
    required this.discAngle,
    this.velocity = 1.0,
    this.strobeColor = const Color(0xFF00FF00),
    this.knobAngle = 0.0,
    this.labelImage,
    this.strobeEnabled = true,
    this.is33RPM = true,
    this.isPlaying = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Layout Constants - MUST MATCH BASE PAINTER
    final platterRadius = w * 0.36;
    final platterCenter = Offset(w * 0.42, h * 0.45);
    
    // SPINNING PLATTER & VINYL
    canvas.save();
    canvas.translate(platterCenter.dx, platterCenter.dy);
    canvas.rotate(discAngle);
    canvas.translate(-platterCenter.dx, -platterCenter.dy);

    // 0. Strobe Dots (On the Platter Rim)
    // Drawn before vinyl so they are on the metal platter
    if (strobeEnabled) {
      final dotCount = 60; // 60Hz strobe
      final dotRadius = w * 0.004;
      final dotPaint = Paint()..color = const Color(0xFFCCCCCC);
      
      for (int i = 0; i < dotCount; i++) {
        final angle = (i / dotCount) * 2 * pi;
        final dx = platterCenter.dx + cos(angle) * (platterRadius * 0.98);
        final dy = platterCenter.dy + sin(angle) * (platterRadius * 0.98);
        canvas.drawCircle(Offset(dx, dy), dotRadius, dotPaint);
      }
    }

    final recordR = platterRadius * 0.96; // Full size
    
    // Authentic Vinyl Color
    final vinylColor = const Color(0xFF0A0A0A);
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

    // LABEL
    final labelR = platterRadius * 0.32; 
    final labelColor = const Color(0xFFDDDDDD); // Silver/Grey
    canvas.drawCircle(platterCenter, labelR, Paint()..color = labelColor);

    if (labelImage != null) {
      canvas.save();
      final labelPath = Path()..addOval(Rect.fromCircle(center: platterCenter, radius: labelR));
      canvas.clipPath(labelPath);
      
      final imgSize = Size(labelImage!.width.toDouble(), labelImage!.height.toDouble());
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
    canvas.drawCircle(platterCenter, labelR * 0.15, Paint()..color = const Color(0xFF050505));

    canvas.restore(); // Restore from spinning vinyl rotation

    // Specular highlight - Anisotropic "V" shape reflection
    // Drawn AFTER restore so it doesn't rotate with the record
    final lightAngle = -0.8; 
    final shimmerCount = 2;
    
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
      
      // Exclude label from the vinyl specular highlight (Label is matte paper)
      final labelPath = Path()..addOval(Rect.fromCircle(center: platterCenter, radius: labelR));
      final vinylHighlightPath = Path.combine(PathOperation.difference, path, labelPath);

      canvas.drawPath(
        vinylHighlightPath,
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
      Paint()..color = Colors.black.withValues(alpha: 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    
    // Knob Body (Knurled texture hint)
    canvas.drawCircle(
      knobCenter,
      knobR,
      Paint()..shader = ui.Gradient.radial(
        knobCenter,
        knobR,
        [const Color(0xFF222222), const Color(0xFF000000)],
      ),
    );
    
    // Knob Indicator
    final kAngle = -pi / 4 + knobAngle; // Start at 7 o'clock ish
    canvas.drawLine(
      knobCenter,
      knobCenter + Offset(cos(kAngle) * knobR * 0.8, sin(kAngle) * knobR * 0.8),
      Paint()..color = Colors.white..strokeWidth = 2..strokeCap = StrokeCap.round,
    );

    // START/STOP LEVER HANDLE (Moved to Bottom Left, right of Knob)
    final leverBaseCenter = Offset(w * 0.24, h * 0.88);
    final leverOffset = isPlaying ? w * 0.02 : -w * 0.02; // Down = Play, Up = Stop
    final leverHandleRect = Rect.fromCenter(
      center: leverBaseCenter.translate(0, leverOffset),
      width: w * 0.04,
      height: w * 0.02,
    );
    
    // Lever Shaft
    canvas.drawRect(
      Rect.fromCenter(center: leverBaseCenter, width: w * 0.01, height: w * 0.06),
      Paint()..color = const Color(0xFF111111),
    );
    
    // Lever Knob (Chrome)
    canvas.drawRRect(
      RRect.fromRectAndRadius(leverHandleRect, const Radius.circular(2)),
      Paint()..shader = ui.Gradient.linear(
        leverHandleRect.topLeft,
        leverHandleRect.bottomRight,
        [const Color(0xFFFFFFFF), const Color(0xFFAAAAAA), const Color(0xFF555555)],
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
       final glowColor = Color.lerp(const Color(0xFF003300), const Color(0xFF00FF00), intensity)!;
       
       // Glow
       canvas.drawCircle(
        powerLightPos,
        w * 0.025 * intensity, 
        Paint()
          ..shader = ui.Gradient.radial(
            powerLightPos,
            w * 0.03,
            [glowColor.withValues(alpha: 0.8 * intensity), Colors.transparent],
          )
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
    final animatedRadius = ui.lerpDouble(restingRadius, finalRadius, progress.clamp(0.0, 1.0))!;

    final d = pivotToSpindle;
    Offset stylusPos;

    if (d > armLength + animatedRadius || d < (armLength - animatedRadius).abs()) {
      // Resting position
      final restingAngle = atan2(platterCenter.dy - pivot.dy, platterCenter.dx - pivot.dx) - 0.4;
      stylusPos = pivot + Offset.fromDirection(restingAngle, armLength);
    } else {
      // Intersection
      final a = (d * d - animatedRadius * animatedRadius + armLength * armLength) / (2 * d);
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
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: platterCenter, radius: recordR)));
    
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
    canvas.drawCircle(antiSkatePos, w * 0.015, Paint()..color = const Color(0xFF222222));
    canvas.drawLine(antiSkatePos, antiSkatePos.translate(0, -w * 0.01), Paint()..color = Colors.white..strokeWidth = 1);

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
    final cwRect = Rect.fromCenter(center: Offset(-w * 0.1, 0), width: w * 0.08, height: w * 0.08);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cwRect, const Radius.circular(4)),
      Paint()..shader = ui.Gradient.linear(
        cwRect.topLeft,
        cwRect.bottomRight,
        [const Color(0xFF444444), const Color(0xFF111111)],
      ),
    );
    // Counterweight Dial Markings
    canvas.drawLine(Offset(-w * 0.1, -w * 0.03), Offset(-w * 0.1, w * 0.03), Paint()..color = Colors.white.withValues(alpha: 0.5)..strokeWidth = 1);

    canvas.restore();

    // ARM TUBE (Straight Silver)
    canvas.drawLine(
      pivot,
      stylusPos.translate(liftOffset.dx, liftOffset.dy),
      Paint()
        ..shader = ui.Gradient.linear(
          pivot,
          stylusPos,
          [const Color(0xFFCCCCCC), const Color(0xFFEEEEEE), const Color(0xFFCCCCCC)],
          [0.0, 0.5, 1.0],
        )
        ..strokeWidth = w * 0.015
        ..strokeCap = StrokeCap.butt,
    );

    // HEADSHELL (Angled)
    canvas.save();
    canvas.translate(stylusPos.dx + liftOffset.dx, stylusPos.dy + liftOffset.dy);
    canvas.rotate(armAngle + 0.4); // Offset angle for headshell
    
    // Headshell shape
    final headshellPath = Path()
      ..moveTo(-w * 0.015, -w * 0.02)
      ..lineTo(w * 0.08, -w * 0.015)
      ..lineTo(w * 0.08, w * 0.015)
      ..lineTo(-w * 0.015, w * 0.02)
      ..close();
      
    canvas.drawPath(
      headshellPath,
      Paint()..color = const Color(0xFF111111),
    );
    
    // Finger lift
    canvas.drawPath(
      Path()..moveTo(w * 0.05, 0)..quadraticBezierTo(w * 0.1, w * 0.02, w * 0.12, -w * 0.04),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0xFF111111),
    );
    
    // Cartridge (Red tip)
    canvas.drawRect(
      Rect.fromLTWH(w * 0.02, -w * 0.01, w * 0.04, w * 0.02),
      Paint()..color = const Color(0xFF333333),
    );
    canvas.drawCircle(Offset(w * 0.05, 0), w * 0.005, Paint()..color = Colors.red);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TurntableSpinnerPainter oldDelegate) =>
      discAngle != oldDelegate.discAngle ||
      isPlaying != oldDelegate.isPlaying ||
      is33RPM != oldDelegate.is33RPM ||
      progress != oldDelegate.progress;
}

