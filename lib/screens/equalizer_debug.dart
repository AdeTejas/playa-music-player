import 'package:flutter/material.dart';
import '../services/equalizer_service.dart';

class EqualizerDebugScreen extends StatefulWidget {
  const EqualizerDebugScreen({super.key});

  @override
  State<EqualizerDebugScreen> createState() => _EqualizerDebugScreenState();
}

class _EqualizerDebugScreenState extends State<EqualizerDebugScreen> {
  List<int> _centers = [];
  List<int> _levels = [];
  List<int> _range = [0, 0];
  List<String> _presets = [];
  bool _enabled = false;
  String _log = '';

  Future<void> _refresh() async {
    try {
      final centers = await EqualizerService.getBandCenterFrequencies();
      final levels = await EqualizerService.getAllBandLevels();
      final range = await EqualizerService.getBandLevelRange();
      final presets = await EqualizerService.getPresetNames();
      final enabled = await EqualizerService.isEnabled();
      // (Previously emitted debug prints here; removed for repo cleanliness.)
      setState(() {
        _centers = centers;
        _levels = levels;
        _range = range;
        _presets = presets;
        _enabled = enabled;
        _log = 'Refreshed at ${DateTime.now().toIso8601String()}';
      });
    } catch (e) {
      setState(() => _log = 'Error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer Debug'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enabled: $_enabled', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text('Band centers (Hz): ${_centers.join(', ')}', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text('Band levels: ${_levels.join(', ')}', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text('Level range: ${_range.join(' .. ')}', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text('Presets: ${_presets.join(', ')}', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await EqualizerService.setEnabled(!_enabled);
                    await _refresh();
                  } catch (e) {
                    setState(() => _log = 'Error toggling: $e');
                  }
                },
                child: Text(_enabled ? 'Disable Equalizer' : 'Enable Equalizer'),
              ),
              const SizedBox(height: 16),
              const Text('Log:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_log, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}
