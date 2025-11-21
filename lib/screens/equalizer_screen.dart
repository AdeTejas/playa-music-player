import 'dart:math';
import 'package:flutter/material.dart';
import 'package:playa_clean/ui/tokens.dart';
import '../services/equalizer_service.dart';
import 'equalizer_debug.dart';

class EqualizerScreen extends StatefulWidget {
  final int sessionId;
  const EqualizerScreen({super.key, required this.sessionId});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  bool _isInitialized = false;
  bool _isEnabled = false;
  int _bands = 0;
  List<int> _levelRange = [0, 0];
  List<int> _bandLevels = [];
  List<int> _bandCenters = [];
  List<String> _presetNames = [];
  int _currentPreset = 0;

  @override
  void initState() {
    super.initState();
    _initializeEqualizer();
  }

  Future<void> _initializeEqualizer() async {
    try {
      // Initialize native equalizer with the provided Android audio session id
      await EqualizerService.initializeEqualizer(widget.sessionId);

      // Fetch bands, ranges and presets using bulk APIs when possible
      _bandCenters = await EqualizerService.getBandCenterFrequencies();
      _bandLevels = await EqualizerService.getAllBandLevels();
      _bands = _bandCenters.isNotEmpty ? _bandCenters.length : _bandLevels.length;

      _levelRange = await EqualizerService.getBandLevelRange();
      _presetNames = await EqualizerService.getPresetNames();
      _currentPreset = await EqualizerService.getCurrentPreset();
      _isEnabled = await EqualizerService.isEnabled();
      
      setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize equalizer: $e')),
        );
      }
    }
  }

  Future<void> _setBandLevel(int band, int level) async {
    try {
      await EqualizerService.setBandLevel(band, level);
      setState(() {
        _bandLevels[band] = level;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set band level: $e')),
        );
      }
    }
  }

  Future<void> _usePreset(int preset) async {
    try {
      await EqualizerService.usePreset(preset);
      setState(() {
        _currentPreset = preset;
      });
      // Refresh band levels
      for (int i = 0; i < _bands; i++) {
        _bandLevels[i] = await EqualizerService.getBandLevel(i);
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to use preset: $e')),
        );
      }
    }
  }

  Future<void> _toggleEnabled() async {
    try {
      await EqualizerService.setEnabled(!_isEnabled);
      setState(() {
        _isEnabled = !_isEnabled;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle equalizer: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          IconButton(
            tooltip: 'Debug Equalizer',
            icon: const Icon(Icons.bug_report),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerDebugScreen())),
          ),
          Switch(
            value: _isEnabled,
            onChanged: _isInitialized ? (_) => _toggleEnabled() : null,
            activeColor: kColorAppAccent,
          ),
        ],
      ),
        body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(kSp * 2),
            child: Column(
                children: [
                  // Preset chips (more tactile than a dropdown)
                  if (_presetNames.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Presets', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ?? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: kSp),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_presetNames.length, (i) {
                          return Padding(
                            padding: const EdgeInsets.only(right: kSp),
                                    child: ChoiceChip(
                                      avatar: const Icon(Icons.music_note, size: kSp * 2, color: kColorOn),
                                      label: Text(_presetNames[i]),
                                      selected: _currentPreset == i,
                                      onSelected: (sel) => sel ? _usePreset(i) : null,
                                      selectedColor: kColorAppAccent,
                                      backgroundColor: kColorCard,
                                      labelStyle: TextStyle(color: _currentPreset == i ? kColorOn : kColorOn2),
                                    ),
                          );
                        }),
                      ),
                    ),
                    const Divider(height: 28),
                  ],

                  // Band grid: show frequency labels and animated bars
                  const SizedBox(height: kSp),
                  Expanded(
                    child: _bands == 0
                        ? const Center(child: Text('No equalizer bands available'))
                        : LayoutBuilder(builder: (context, constraints) {
                            // Compute approximate center frequencies if we don't have them
                            List<int> freqs = _approximateFrequencies(_bands);
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(_bands, (index) {
                                final level = _bandLevels.length > index ? _bandLevels[index] : 0;
                                final normalizedLevel = (_levelRange[1] - _levelRange[0]) > 0
                                    ? (level - _levelRange[0]) / (_levelRange[1] - _levelRange[0])
                                    : 0.5;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: kSp * 0.75),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // Frequency Label
                                        Text(
                                          '${freqs[index] < 1000 ? freqs[index] : (freqs[index] / 1000).toStringAsFixed(1) + 'k'}',
                                          style: const TextStyle(fontSize: 10, color: kColorOn2),
                                        ),
                                        const SizedBox(height: 4),
                                        
                                        // Vertical Slider
                                        Expanded(
                                          child: RotatedBox(
                                            quarterTurns: 3,
                                            child: Slider(
                                              value: normalizedLevel.clamp(0.0, 1.0),
                                              onChanged: _isEnabled
                                                  ? (value) {
                                                      final newLevel = (_levelRange[0] + value * (_levelRange[1] - _levelRange[0])).round();
                                                      _setBandLevel(index, newLevel);
                                                    }
                                                  : null,
                                              activeColor: kColorAppAccent,
                                              inactiveColor: kColorCard,
                                            ),
                                          ),
                                        ),
                                        
                                        const SizedBox(height: 4),
                                        // dB Label
                                        Text(
                                          '${level > 0 ? '+' : ''}$level dB',
                                          style: const TextStyle(fontSize: 10, color: kColorOn2),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            );
                          }),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    EqualizerService.release();
    super.dispose();
  }

  List<int> _approximateFrequencies(int bands, {int low = 60, int high = 14000}) {
    if (bands <= 0) return [];
    if (bands == 1) return [(low + high) ~/ 2];
    final logLow = log(low);
    final logHigh = log(high);
    final step = (logHigh - logLow) / (bands - 1);
    return List.generate(bands, (i) => (exp(logLow + step * i)).round());
  }
}