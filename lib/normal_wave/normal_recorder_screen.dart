import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:io';

// Video visualization styles - moved outside class to fix scope issues
enum VideoVisualStyle { waveformLine, waveformBars, spectrum }

// Helper immutable config
class _WaveStyleConfig {
  final Color color;
  final double spacing;
  final double thickness;
  final double scale;
  final bool showMiddleLine;
  const _WaveStyleConfig({
    required this.color,
    required this.spacing,
    required this.thickness,
    required this.scale,
    required this.showMiddleLine,
  });
}

class NormalRecorderScreen extends StatefulWidget {
  const NormalRecorderScreen({super.key});

  @override
  State<NormalRecorderScreen> createState() => _NormalRecorderScreenState();
}

class _NormalRecorderScreenState extends State<NormalRecorderScreen> {
  late final RecorderController _recordController;
  late final PlayerController _playerController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _filePath;
  String? _videoPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isGeneratingVideo = false;
  StreamSubscription? _playerSubscription;
  StreamSubscription? _durationSubscription;
  int _currentDuration = 0;

  VideoVisualStyle _videoVisualStyle = VideoVisualStyle.spectrum;

  // In-app recorder/player waveform style index
  int _waveStyleIndex = 0;

  // Predefined style configs ensuring waveThickness < spacing
  static const List<_WaveStyleConfig> _recorderStyles = [
    _WaveStyleConfig(color: Colors.green, spacing: 6, thickness: 2, scale: 90, showMiddleLine: false),
    _WaveStyleConfig(color: Colors.cyan, spacing: 5, thickness: 2, scale: 80, showMiddleLine: true),
    _WaveStyleConfig(color: Colors.deepPurpleAccent, spacing: 4, thickness: 2, scale: 110, showMiddleLine: false),
    _WaveStyleConfig(color: Colors.orangeAccent, spacing: 7, thickness: 3, scale: 95, showMiddleLine: true),
  ];

  static const List<_WaveStyleConfig> _playerStyles = [
    _WaveStyleConfig(color: Colors.green, spacing: 6, thickness: 2, scale: 100, showMiddleLine: false),
    _WaveStyleConfig(color: Colors.cyan, spacing: 5, thickness: 2, scale: 90, showMiddleLine: false),
    _WaveStyleConfig(color: Colors.deepPurpleAccent, spacing: 4, thickness: 2, scale: 120, showMiddleLine: false),
    _WaveStyleConfig(color: Colors.orangeAccent, spacing: 7, thickness: 3, scale: 105, showMiddleLine: false),
  ];

  void _cycleWaveStyle() {
    setState(() => _waveStyleIndex = (_waveStyleIndex + 1) % _recorderStyles.length);
  }

  void _cycleVideoVisualStyle() {
    setState(() {
      switch (_videoVisualStyle) {
        case VideoVisualStyle.waveformLine:
          _videoVisualStyle = VideoVisualStyle.waveformBars;
          break;
        case VideoVisualStyle.waveformBars:
          _videoVisualStyle = VideoVisualStyle.spectrum;
          break;
        case VideoVisualStyle.spectrum:
          _videoVisualStyle = VideoVisualStyle.waveformLine;
          break;
      }
    });
  }

  String _videoStyleLabel() {
    switch (_videoVisualStyle) {
      case VideoVisualStyle.waveformLine:
        return 'Line';
      case VideoVisualStyle.waveformBars:
        return 'Bars';
      case VideoVisualStyle.spectrum:
        return 'Spectrum';
    }
  }

  WaveStyle _currentRecorderWaveStyle() {
    final cfg = _recorderStyles[_waveStyleIndex];
    return WaveStyle(
      waveColor: cfg.color,
      extendWaveform: true,
      showMiddleLine: cfg.showMiddleLine,
      middleLineColor: cfg.showMiddleLine ? cfg.color.withValues(alpha: 0.4) : Colors.white,
      spacing: cfg.spacing,
      waveThickness: cfg.thickness,
      waveCap: StrokeCap.round,
      scaleFactor: cfg.scale,
    );
  }

  PlayerWaveStyle _currentPlayerWaveStyle() {
    final cfg = _playerStyles[_waveStyleIndex];
    return PlayerWaveStyle(
      fixedWaveColor: const Color(0xFF2F2B38),
      liveWaveColor: cfg.color,
      spacing: cfg.spacing,
      waveThickness: cfg.thickness,
      waveCap: StrokeCap.round,
      scaleFactor: cfg.scale,
      showSeekLine: true,
      seekLineThickness: 2,
      seekLineColor: cfg.color.withValues(alpha: 0.9),
    );
  }

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initPlayer();
  }

  void _initRecorder() {
    _recordController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 44100
      ..bitRate = 128000;
  }

  void _initPlayer() {
    _playerController = PlayerController();

    _playerSubscription = _playerController.onPlayerStateChanged.listen((state) {
      setState(() => _isPlaying = state.isPlaying);
      if (state.isStopped) {
        setState(() => _currentDuration = 0);
      }
    });

    _durationSubscription = _playerController.onCurrentDurationChanged.listen((d) {
      setState(() => _currentDuration = d);
      if (_playerController.maxDuration > 0 && d >= _playerController.maxDuration) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _recordController.dispose();
    _playerController.dispose();
    _audioPlayer.dispose();
    _playerSubscription?.cancel();
    _durationSubscription?.cancel();
    super.dispose();
  }

  Future<String> _getFilePath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_message.m4a';
  }

  Future<String> _getVideoPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/waveform_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  Future<void> _startRecording() async {
    if (_isPlaying) {
      await _playerController.pausePlayer();
      setState(() => _isPlaying = false);
    }
    final path = await _getFilePath();
    try {
      await _recordController.record(path: path);
      setState(() {
        _isRecording = true;
        _filePath = path;
        _videoPath = null;
        _currentDuration = 0;
      });
    } catch (e) {
      debugPrint('Record start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recordController.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        _filePath = path;
        await _preparePlayer(path);
      }
    } catch (e) {
      debugPrint('Record stop error: $e');
    }
  }

  Future<void> _preparePlayer(String path) async {
    try {
      await _playerController.preparePlayer(
        path: path,
        shouldExtractWaveform: true,
        noOfSamples: 1200, // high resolution for smooth playback waveform
      );
    } catch (e) {
      debugPrint('Prepare player error: $e');
    }
  }

  Future<void> _playRecording() async {
    if (_filePath == null) return;
    try {
      if (_isPlaying) {
        await _playerController.pausePlayer();
        setState(() => _isPlaying = false);
      } else {
        if (_currentDuration >= _playerController.maxDuration) {
          await _playerController.seekTo(0);
        }
        await _playerController.startPlayer();
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Playback error: $e');
    }
  }

  Future<void> _generateWaveformVideo() async {
    if (_filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record audio first')));
      return;
    }
    setState(() => _isGeneratingVideo = true);
    try {
      final videoPath = await _getVideoPath();
      await _audioPlayer.setFilePath(_filePath!);
      final durMs = _audioPlayer.duration?.inMilliseconds ?? 0;
      final seconds = (durMs / 1000).clamp(0.1, 9999).toDouble();
      final fps = seconds < 1 ? 15 : 30;

      // Choose filter based on desired style
      String filter;
      switch (_videoVisualStyle) {
        case VideoVisualStyle.waveformLine:
          filter = '[0:a]aformat=channel_layouts=mono,showwaves=s=720x160:mode=p2p:rate=$fps:colors=0x00FF7F,format=yuv420p[v]';
          break;
        case VideoVisualStyle.waveformBars:
          // Fixed bars mode: use cline mode with proper format conversion
          filter = '[0:a]aformat=channel_layouts=mono,showwaves=s=720x200:mode=cline:rate=$fps:colors=0xFF7F00,format=yuv420p[v]';
          break;
        case VideoVisualStyle.spectrum:
          filter = '[0:a]aformat=channel_layouts=mono,showspectrum=s=720x360:mode=combined:color=rainbow:scale=log:slide=scroll,format=yuv420p[v]';
          break;
      }

      final cmd = [
        '-y','-i',_filePath!,
        '-filter_complex',filter,
        '-map','[v]','-map','0:a',
        '-c:v','libx264','-preset','medium','-crf','23','-pix_fmt','yuv420p',
        '-c:a','aac','-b:a','128k','-shortest','-movflags','+faststart',
        videoPath
      ].join(' ');

      debugPrint('FFmpeg command: $cmd');

      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      final logs = await session.getLogsAsString();

      debugPrint('FFmpeg return code: $rc');
      debugPrint('FFmpeg logs: $logs');

      if (ReturnCode.isSuccess(rc)) {
        setState(() => _videoPath = videoPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video generated'), backgroundColor: Colors.green));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('FFmpeg failed (code: $rc)'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      debugPrint('Video generation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingVideo = false);
    }
  }

  Future<void> _shareWaveformVideo() async {
    if (_videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generate video first')));
      return;
    }
    await Share.shareXFiles([XFile(_videoPath!)], text: 'Waveform video');
  }

  Widget _buildWaveformArea() {
    final width = MediaQuery.of(context).size.width - 32;
    const height = 140.0;

    if (_isRecording) {
      return AudioWaveforms(
        recorderController: _recordController,
        size: Size(width, height),
        enableGesture: false,
        waveStyle: _currentRecorderWaveStyle(),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B26),
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    if (_filePath != null) {
      return AudioFileWaveforms(
        playerController: _playerController,
        size: Size(width, height),
        enableSeekGesture: true,
        playerWaveStyle: _currentPlayerWaveStyle(),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B26),
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('Press mic to start recording', style: TextStyle(color: Colors.white54)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Normal Voice Recorder'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Waveform style cycler
            IconButton(
              tooltip: 'Waveform Style',
              onPressed: _cycleWaveStyle,
              icon: const Icon(Icons.auto_awesome_motion),
            ),
            // Video style cycler
            TextButton.icon(
              onPressed: _cycleVideoVisualStyle,
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              icon: const Icon(Icons.movie_filter),
              label: Text(_videoStyleLabel()),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 24),
            if (_isRecording)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x1AFF0000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x4DFF0000)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 10, height: 10, child: DecoratedBox(decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
                    SizedBox(width: 8),
                    Text('Recording...', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _buildWaveformArea(),
            const SizedBox(height: 32),
            Wrap(
              spacing: 20,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'rec',
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  backgroundColor: _isRecording ? Colors.red : Colors.blue,
                  child: Icon(_isRecording ? Icons.stop : Icons.mic),
                ),
                if (_filePath != null && !_isRecording)
                  FloatingActionButton(
                    heroTag: 'play',
                    onPressed: _playRecording,
                    backgroundColor: _isPlaying ? Colors.orange : Colors.green,
                    child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                if (_filePath != null && !_isRecording)
                  FloatingActionButton(
                    heroTag: 'video',
                    onPressed: _isGeneratingVideo ? null : _generateWaveformVideo,
                    backgroundColor: _isGeneratingVideo ? Colors.grey : Colors.purple,
                    child: _isGeneratingVideo
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Icon(Icons.video_call),
                  ),
                if (_videoPath != null)
                  FloatingActionButton(
                    heroTag: 'share',
                    onPressed: _shareWaveformVideo,
                    backgroundColor: Colors.indigo,
                    child: const Icon(Icons.share),
                  ),
              ],
            ),
            const Spacer(),
            if (_filePath != null && !_isRecording)
              Text(
                _isPlaying
                    ? 'Playing ${(Duration(milliseconds: _currentDuration)).inSeconds}s / ${(Duration(milliseconds: _playerController.maxDuration)).inSeconds}s'
                    : 'Ready (${(Duration(milliseconds: _playerController.maxDuration)).inSeconds}s)',
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      backgroundColor: const Color(0xFF121017),
    );
  }
}
