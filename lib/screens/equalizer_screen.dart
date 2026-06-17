import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/equalizer_service.dart';
import '../design/design_system.dart';

class EqualizerScreen extends StatefulWidget {
  final int sessionId;
  const EqualizerScreen({super.key, required this.sessionId});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen>
    with SingleTickerProviderStateMixin {
  bool _isInitialized = false;
  bool _isEnabled = false;
  int _bands = 0;
  List<int> _levelRange = [0, 0];
  List<int> _bandLevels = [];
  List<int> _bandCenters = [];
  List<String> _presetNames = [];
  int _currentPreset = 0;
  int? _lastTouchedBand;
  int? _sliderTouchedBand;

  late AnimationController _animController;
  List<int> _animFrom = [];
  List<int> _animTo = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() => setState(() {}));
    _initializeEqualizer();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  List<int> get _displayLevels {
    if (!_animController.isAnimating) return _bandLevels;
    final t = _animController.value;
    return List<int>.generate(
      _animTo.length,
      (i) => (_animFrom[i] + (_animTo[i] - _animFrom[i]) * t).round(),
    );
  }

  Future<void> _initializeEqualizer() async {
    if (widget.sessionId == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio session not ready. Play a song first.'),
          ),
        );
      }
      return;
    }

    try {
      await EqualizerService.initializeEqualizer(widget.sessionId);
      _bandCenters = await EqualizerService.getBandCenterFrequencies();
      _bandLevels = await EqualizerService.getAllBandLevels();
      _bands =
          _bandCenters.isNotEmpty ? _bandCenters.length : _bandLevels.length;

      if (_bandLevels.length < _bands) {
        _bandLevels = List.filled(_bands, 0);
      }

      _levelRange = await EqualizerService.getBandLevelRange();
      _presetNames = await EqualizerService.getPresetNames();
      _currentPreset = await EqualizerService.getCurrentPreset();
      _isEnabled = await EqualizerService.isEnabled();

      _animFrom = List.from(_bandLevels);
      _animTo = List.from(_bandLevels);

      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Equalizer init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize equalizer: $e')),
        );
      }
    }
  }

  Future<void> _setBandLevel(int band, int level) async {
    if (_animController.isAnimating) _animController.stop();
    try {
      await EqualizerService.setBandLevel(band, level);
      _bandLevels[band] = level;
      _currentPreset = -1;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('EQ Error: $e');
    }
  }

  Future<void> _resetFlat() async {
    if (_bands == 0) return;
    try {
      for (int i = 0; i < _bands; i++) {
        await EqualizerService.setBandLevel(i, 0);
      }
      _animateToLevels(List<int>.filled(_bands, 0));
      _currentPreset = -1;
    } catch (e) {
      debugPrint('EQ Error: $e');
    }
  }

  void _animateToLevels(List<int> target) {
    if (_animController.isAnimating) _animController.stop();
    if (_bandLevels.length != target.length || _bandLevels.isEmpty) {
      _bandLevels = List.from(target);
      setState(() {});
      return;
    }
    _animFrom = List.from(_bandLevels);
    _animTo = List.from(target);
    _bandLevels = List.from(target);
    _animController.forward(from: 0.0);
  }

  Future<void> _usePreset(int preset) async {
    try {
      await EqualizerService.usePreset(preset);
      final newLevels = <int>[];
      for (int i = 0; i < _bands; i++) {
        newLevels.add(await EqualizerService.getBandLevel(i));
      }
      _currentPreset = preset;
      _animateToLevels(newLevels);
    } catch (e) {
      debugPrint('EQ Error: $e');
    }
  }

  Future<void> _toggleEnabled() async {
    try {
      await EqualizerService.setEnabled(!_isEnabled);
      _isEnabled = !_isEnabled;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('EQ Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final c = Theme.of(context).extension<PlayaColorsExtension>()!;
    final presetLabel =
        _currentPreset >= 0 && _currentPreset < _presetNames.length
            ? _presetNames[_currentPreset]
            : 'Custom';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Equalizer'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reset to flat',
            onPressed:
                _isInitialized && _isEnabled && _bands > 0 ? _resetFlat : null,
            icon: const PhosphorIcon(PhosphorIconsBold.arrowCounterClockwise),
          ),
          Switch(
            value: _isEnabled,
            onChanged: _isInitialized ? (_) => _toggleEnabled() : null,
            thumbColor: WidgetStateProperty.all(accentColor),
          ),
        ],
      ),
      body:
          !_isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  _buildPresetRow(accentColor, c, presetLabel),
                  _buildCurveSection(accentColor, c),
                  _buildSliderStrip(accentColor, c),
                ],
              ),
    );
  }

  Widget _buildPresetRow(
      Color accentColor, PlayaColorsExtension c, String presetLabel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                presetLabel,
                style: TextStyle(
                  color: c.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_levelRange.length >= 2 && _levelRange[1] != 0)
                Row(
                  children: [
                    Text(
                      '${_levelRange[0] / 100}',
                      style: const TextStyle(
                        color: PlayaColors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                    const Text(
                      ' – ',
                      style: TextStyle(
                        color: PlayaColors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      '${_levelRange[1] / 100} dB',
                      style: const TextStyle(
                        color: PlayaColors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_presetNames.isNotEmpty)
            SizedBox(
              height: 30,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _presetNames.length,
                itemBuilder: (context, i) {
                  final isSelected = _currentPreset == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => _usePreset(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? accentColor.withValues(alpha: 0.25)
                                  : PlayaColors.glass,
                          borderRadius: BorderRadius.circular(20),
                          border:
                              isSelected
                                  ? Border.all(
                                    color: accentColor.withValues(alpha: 0.5),
                                    width: 1,
                                  )
                                  : null,
                        ),
                        child: Text(
                          _presetNames[i],
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isSelected
                                    ? c.onSurface
                                    : c.onSurfaceVariant,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurveSection(Color accentColor, PlayaColorsExtension c) {
    return Expanded(
      flex: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: GlassPanel(
          borderRadius: BorderRadius.circular(14),
          borderColor: PlayaColors.borderSubtle,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart:
                      _isEnabled ? (d) => _handleTouch(d, constraints) : null,
                  onPanUpdate:
                      _isEnabled ? (d) => _handleTouch(d, constraints) : null,
                  onTapDown:
                      _isEnabled ? (d) => _handleTouch(d, constraints) : null,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _EQCurvePainter(
                      bands: _bands,
                      levels: _displayLevels,
                      centersHz: _bandCenters,
                      range: _levelRange,
                      color: accentColor,
                      selectedBand: _lastTouchedBand,
                      c: c,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderStrip(Color accentColor, PlayaColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: SizedBox(
        height: 72,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapDown:
                  _isEnabled
                      ? (d) => _handleSliderTouch(d, constraints)
                      : null,
              onPanStart:
                  _isEnabled
                      ? (d) => _handleSliderTouch(d, constraints)
                      : null,
              onPanUpdate:
                  _isEnabled
                      ? (d) => _handleSliderMove(d, constraints)
                      : null,
              onPanEnd: (_) {
                _sliderTouchedBand = null;
                if (mounted) setState(() {});
              },
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _EQSliderStripPainter(
                  bands: _bands,
                  levels: _bandLevels,
                  centersHz: _bandCenters,
                  range: _levelRange,
                  color: accentColor,
                  touchedBand: _sliderTouchedBand,
                  c: c,
                  onChanged: _isEnabled ? _setBandLevel : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleTouch(dynamic details, BoxConstraints constraints) {
    if (_bands == 0) return;
    final Offset localPos = details.localPosition;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final bandWidth = width / (_bands - 1);
    int band = (localPos.dx / bandWidth).round().clamp(0, _bands - 1);
    _lastTouchedBand = band;
    final t = 1.0 - (localPos.dy / height).clamp(0.0, 1.0);
    final range = _levelRange[1] - _levelRange[0];
    final newLevel = (_levelRange[0] + (t * range)).round();
    HapticFeedback.selectionClick();
    _setBandLevel(band, newLevel);
  }

  void _handleSliderTouch(dynamic details, BoxConstraints constraints) {
    if (_bands == 0) return;
    final Offset localPos = details.localPosition;
    _updateSliderBand(localPos, constraints);
    HapticFeedback.selectionClick();
  }

  void _handleSliderMove(dynamic details, BoxConstraints constraints) {
    if (_bands == 0) return;
    final Offset localPos = details.localPosition;
    _updateSliderBand(localPos, constraints);
  }

  void _updateSliderBand(Offset localPos, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final bandWidth = _bands > 1 ? width / _bands : width;
    final band = (localPos.dx / bandWidth).floor().clamp(0, _bands - 1);
    _sliderTouchedBand = band;
    final t = 1.0 - (localPos.dy / height).clamp(0.0, 1.0);
    final range = _levelRange[1] - _levelRange[0];
    final newLevel = (_levelRange[0] + (t * range)).round();
    _setBandLevel(band, newLevel);
  }
}

// ─── Curve Painter ──────────────────────────────────────────────────────────

class _EQCurvePainter extends CustomPainter {
  final int bands;
  final List<int> levels;
  final List<int> centersHz;
  final List<int> range;
  final Color color;
  final int? selectedBand;
  final PlayaColorsExtension c;

  _EQCurvePainter({
    required this.bands,
    required this.levels,
    required this.centersHz,
    required this.range,
    required this.color,
    required this.selectedBand,
    required this.c,
  });

  String _formatHz(int hz) {
    if (hz >= 1000) {
      final v = hz / 1000.0;
      return v >= 10 ? '${v.toStringAsFixed(0)}k' : '${v.toStringAsFixed(1)}k';
    }
    return hz.toString();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bands == 0) return;

    final minLvl = range[0];
    final maxLvl = range[1];
    final lvlRange = maxLvl - minLvl;

    final points = <Offset>[];
    for (int i = 0; i < bands; i++) {
      final x = i * (size.width / (bands - 1));
      final level = i < levels.length ? levels[i] : 0;
      final normalized = lvlRange == 0 ? 0.5 : (level - minLvl) / lvlRange;
      final y = size.height - (normalized * size.height);
      points.add(Offset(x, y));
    }
    if (points.isEmpty) return;

    // Smooth curve path
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[max(0, i - 1)];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[min(points.length - 1, i + 2)];
      for (double t = 0; t < 1.0; t += 0.05) {
        final pt = _catmullRom(p0, p1, p2, p3, t);
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.lineTo(points.last.dx, points.last.dy);

    // Fill path (closed to bottom)
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    // ── Grid ──
    final gridPaint =
        Paint()
          ..color = c.borderSubtle
          ..strokeWidth = 0.5;
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), gridPaint);
    for (final p in points) {
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height), gridPaint);
    }

    // ── Y-axis dB labels ──
    final dbLabelStyle = TextStyle(
      color: c.onSurfaceVariant.withValues(alpha: 0.4),
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );
    final halfDb = maxLvl / 200.0;
    if (halfDb > 0) {
      for (final dbVal in [-halfDb, 0.0, halfDb]) {
        if (dbVal == 0.0) continue;
        final norm = lvlRange == 0 ? 0.5 : ((dbVal * 100) - minLvl) / lvlRange;
        final y = size.height - (norm * size.height);
        if (y >= 0 && y <= size.height) {
          final tp = TextPainter(
            text: TextSpan(
              text: '${dbVal.toStringAsFixed(0)} dB',
              style: dbLabelStyle,
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(4, y - tp.height / 2));
        }
      }
    }

    // ── Glow layer ──
    final glowPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.30),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
          ..blendMode = BlendMode.plus;
    canvas.drawPath(fillPath, glowPaint);

    // ── Fill gradient ──
    final fillPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // ── Curve stroke ──
    final strokePaint =
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // ── Point dots ──
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isSelected = selectedBand != null && selectedBand == i;
      final level = i < levels.length ? levels[i] : 0;
      final db = level / 100.0;

      if (isSelected) {
        canvas.drawCircle(
          p,
          8.0,
          Paint()..color = Colors.white.withValues(alpha: 0.20),
        );
        canvas.drawCircle(p, 4.5, Paint()..color = color);
        canvas.drawCircle(p, 2.0, Paint()..color = Colors.white);

        final dbText = TextPainter(
          text: TextSpan(
            text: '${db.toStringAsFixed(1)} dB',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(color: Colors.black87, blurRadius: 4),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        dbText.paint(
          canvas,
          Offset(
            (p.dx - dbText.width / 2).clamp(0, size.width - dbText.width),
            (p.dy - dbText.height - 10).clamp(0, size.height - dbText.height),
          ),
        );
      } else {
        canvas.drawCircle(p, 3.0, Paint()..color = Colors.white70);
      }
    }

    // ── Frequency labels ──
    if (centersHz.length == bands) {
      final freqStyle = TextStyle(
        color: c.onSurfaceVariant.withValues(alpha: 0.5),
        fontSize: 9,
        fontWeight: FontWeight.w500,
      );
      for (int i = 0; i < bands; i++) {
        final x = i * (size.width / (bands - 1));
        final tp = TextPainter(
          text: TextSpan(text: _formatHz(centersHz[i]), style: freqStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x - tp.width / 2, size.height - tp.height - 2),
        );
      }
    }
  }

  Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    final v0 = (p2 - p0) * 0.5;
    final v1 = (p3 - p1) * 0.5;
    return (p1 * (2 * t3 - 3 * t2 + 1)) +
        (p2 * (-2 * t3 + 3 * t2)) +
        (v0 * (t3 - 2 * t2 + t)) +
        (v1 * (t3 - t2));
  }

  @override
  bool shouldRepaint(covariant _EQCurvePainter oldDelegate) => true;
}

// ─── Slider Strip Painter ───────────────────────────────────────────────────

class _EQSliderStripPainter extends CustomPainter {
  final int bands;
  final List<int> levels;
  final List<int> centersHz;
  final List<int> range;
  final Color color;
  final int? touchedBand;
  final PlayaColorsExtension c;
  final void Function(int band, int level)? onChanged;

  _EQSliderStripPainter({
    required this.bands,
    required this.levels,
    required this.centersHz,
    required this.range,
    required this.color,
    required this.touchedBand,
    required this.c,
    this.onChanged,
  });

  String _formatHz(int hz) {
    if (hz >= 1000) {
      final v = hz / 1000.0;
      return v >= 10 ? '${v.toStringAsFixed(0)}k' : '${v.toStringAsFixed(1)}k';
    }
    return hz.toString();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bands == 0) return;

    final minLvl = range[0];
    final maxLvl = range[1];
    final lvlRange = maxLvl - minLvl;
    final bandWidth = size.width / bands;
    final trackLeft = bandWidth * 0.42;
    final trackRight = bandWidth * 0.58;
    final trackW = trackRight - trackLeft;
    final thumbR = 5.0;
    final topPad = 12.0;
    const bottomPad = 16.0;
    final drawH = size.height - topPad - bottomPad;

    for (int i = 0; i < bands; i++) {
      final cx = bandWidth * i + bandWidth / 2;
      final level = i < levels.length ? levels[i] : 0;
      final normalized = lvlRange == 0 ? 0.5 : (level - minLvl) / lvlRange;
      final thumbY = topPad + drawH - (normalized * drawH);
      final isTouched = touchedBand == i;
      final db = level / 100.0;

      // Track background
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cx - trackW / 2,
            topPad,
            trackW,
            drawH,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = c.glassStrong,
      );

      // Filled track (from bottom up to thumb)
      if (thumbY < topPad + drawH) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              cx - trackW / 2,
              thumbY,
              trackW,
              topPad + drawH - thumbY,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = color.withValues(alpha: 0.7),
        );
      }

      // Thumb glow
      if (isTouched) {
        canvas.drawCircle(
          Offset(cx, thumbY),
          thumbR + 6,
          Paint()
            ..color = color.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      // Thumb
      canvas.drawCircle(
        Offset(cx, thumbY),
        thumbR,
        Paint()..color = isTouched ? Colors.white : color,
      );

      // dB label
      final dbStyle = TextStyle(
        color: color.withValues(alpha: 0.85),
        fontSize: 9,
        fontWeight: FontWeight.w700,
      );
      final dbTp = TextPainter(
        text: TextSpan(text: db.toStringAsFixed(1), style: dbStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      dbTp.paint(
        canvas,
        Offset(cx - dbTp.width / 2, thumbY - dbTp.height - 4),
      );

      // Frequency label
      if (i < centersHz.length) {
        final freqStyle = TextStyle(
          color: c.onSurfaceVariant.withValues(alpha: 0.5),
          fontSize: 8,
          fontWeight: FontWeight.w500,
        );
        final freqTp = TextPainter(
          text: TextSpan(text: _formatHz(centersHz[i]), style: freqStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        freqTp.paint(
          canvas,
          Offset(cx - freqTp.width / 2, size.height - bottomPad + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EQSliderStripPainter oldDelegate) => true;
}
