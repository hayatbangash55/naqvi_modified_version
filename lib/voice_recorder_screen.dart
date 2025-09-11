import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:io';
import 'dart:ui' as ui;

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  final GlobalKey _waveformKey = GlobalKey(); // Key to capture waveform widget
  late final RecorderController _recordController;
  late final PlayerController _playerController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _filePath;
  String? _videoPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isGeneratingVideo = false;
  StreamSubscription? _playerSubscription;
  int _currentDuration = 0;
  StreamSubscription? _durationSubscription;
  late ScrollController _scrollController;
  final List<String> _capturedFrames = []; // Store captured frames
  Timer? _frameCaptureTimer;
  static const int _targetFPS = 30; // Target frame rate for video
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initPlayer();
    _scrollController = ScrollController();
  }

  void _initRecorder() {
    _recordController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 44100;
  }

  void _initPlayer() {
    _playerController = PlayerController();

    // Listen to player state changes
    _playerSubscription = _playerController.onPlayerStateChanged.listen((state) {
      setState(() => _isPlaying = state.isPlaying);
      if (state.isStopped) {
        setState(() {
          _isPlaying = false;
          _currentDuration = 0;
        });
        if (_scrollController.hasClients) { // Ensure the ScrollController is attached
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });

    // Listen to progress updates
    _durationSubscription = _playerController.onCurrentDurationChanged.listen(
      (duration) {
        setState(() => _currentDuration = duration);
        if (_currentDuration >= _playerController.maxDuration) {
          setState(() => _isPlaying = false);
          if (_scrollController.hasClients) { // Ensure the ScrollController is attached
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        } else if (_isPlaying && _scrollController.hasClients) { // Ensure the ScrollController is attached
          // Calculate scroll position based on progress
          final scrollPosition = (_currentDuration / _playerController.maxDuration) *
              (_scrollController.position.maxScrollExtent);
          _scrollController.animateTo(
            scrollPosition,
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _recordController.dispose();
    _playerController.dispose();
    _audioPlayer.dispose();
    _playerSubscription?.cancel();
    _durationSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String> _getFilePath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_message.m4a';
  }

  Future<String> _getVideoPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/waveform_video_${DateTime
        .now()
        .millisecondsSinceEpoch}.mp4';
  }

  Future<String> _getFramesDirectory() async {
    final dir = await getTemporaryDirectory();
    final framesDir = Directory('${dir.path}/waveform_frames');
    if (!await framesDir.exists()) {
      await framesDir.create(recursive: true);
    }
    return framesDir.path;
  }

  Future<void> _startRecording() async {
    // Stop any ongoing playback
    if (_isPlaying) {
      await _playerController.pausePlayer();
      setState(() => _isPlaying = false);
    }

    // Clear previous frames directory
    await _clearFramesDirectory();

    final path = await _getFilePath();
    try {
      await _recordController.record(path: path);
      setState(() {
        _isRecording = true;
        _filePath = path;
        _capturedFrames.clear();
        _frameCount = 0;
      });

      // Start capturing waveform frames at consistent intervals
      _startFrameCapture();
    } catch (e) {
      debugPrint('Error recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    // Get the screen width before any async operations
    final screenWidth = 720; // Fixed even width for consistent video output

    try {
      final path = await _recordController.stop();
      setState(() {
        _isRecording = false;
        _filePath = path;
        _videoPath = null;
        _currentDuration = 0;
      });

      // Stop capturing frames
      _stopFrameCapture();

      // Reset player and prepare with new recording
      if (path != null) {
        await _playerController.stopPlayer();
        await Future.delayed(const Duration(milliseconds: 200));

        if (mounted) {
          await _playerController.preparePlayer(
            path: path,
            noOfSamples: screenWidth,
            shouldExtractWaveform: true,
          );
          _scrollController.jumpTo(0);
        }
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  void _startFrameCapture() {
    // Capture frames at consistent intervals for smooth video
    const frameDuration = Duration(milliseconds: 33); // ~30 FPS
    _frameCaptureTimer = Timer.periodic(frameDuration, (timer) {
      _captureWaveformFrame();
    });
  }

  void _stopFrameCapture() {
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = null;
  }

  Future<void> _clearFramesDirectory() async {
    try {
      final framesDir = await _getFramesDirectory();
      final dir = Directory(framesDir);
      if (await dir.exists()) {
        await for (final file in dir.list()) {
          if (file is File && file.path.endsWith('.png')) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing frames directory: $e');
    }
  }

  Future<void> _playRecording() async {
    if (_filePath == null || !(await File(_filePath!).exists())) return;

    try {
      if (_isPlaying) {
        await _playerController.pausePlayer();
        setState(() => _isPlaying = false);
      } else {
        if (_currentDuration >= _playerController.maxDuration) {
          await _playerController.seekTo(0);
          _scrollController.jumpTo(0);
        }
        await _playerController.startPlayer();
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Error playing recording: $e');
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _generateWaveformVideo() async {
    if (_filePath == null || _capturedFrames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please record audio first')),
      );
      return;
    }

    setState(() {
      _isGeneratingVideo = true;
    });

    try {
      final videoPath = await _getVideoPath();
      final framesDir = await _getFramesDirectory();

      // Get audio duration
      final audioFile = File(_filePath!);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found');
      }

      // Calculate actual frame rate based on captured frames and audio duration
      await _audioPlayer.setFilePath(_filePath!);
      final audioDuration = _audioPlayer.duration;
      final calculatedFPS = audioDuration != null
          ? (_capturedFrames.length / audioDuration.inSeconds).round()
          : _targetFPS;

      // Ensure minimum frame rate of 1 and maximum of 60 for practical video generation
      final actualFPS = calculatedFPS.clamp(1, 60);

      debugPrint(
          'Audio duration: ${audioDuration?.inSeconds}s, Frames: ${_capturedFrames.length}, Calculated FPS: $calculatedFPS, Using FPS: $actualFPS');

      // Prepare frame pattern for FFmpeg
      final framePattern = '$framesDir/frame_%05d.png';

      // Rename frames to match the expected pattern
      await _renameFramesSequentially();

      // Create video with calculated frame rate to match audio duration exactly
      final command = [
        '-y', // Overwrite output file
        '-r', '$actualFPS', // Use calculated frame rate
        '-i', framePattern, // Input frames pattern
        '-i', _filePath!, // Input audio
        '-vf', 'scale=720:120:force_original_aspect_ratio=disable', // Ensure even dimensions
        '-c:v', 'libx264', // Video codec
        '-preset', 'medium', // Encoding preset
        '-crf', '23', // Quality (lower = better quality)
        '-c:a', 'aac', // Audio codec
        '-b:a', '128k', // Audio bitrate
        '-pix_fmt', 'yuv420p', // Pixel format for compatibility
        '-shortest', // Match shortest stream duration
        '-movflags', '+faststart', // Optimize for web playback
        videoPath
      ].join(' ');

      debugPrint('FFmpeg command: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final logs = await session.getLogsAsString();

      debugPrint('FFmpeg logs: $logs');

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _videoPath = videoPath;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Waveform video generated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        debugPrint('FFmpeg failed with return code: $returnCode');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to generate waveform video'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error generating video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingVideo = false;
        });
      }
    }
  }

  Future<void> _renameFramesSequentially() async {
    try {
      final framesDir = await _getFramesDirectory();

      // Sort frames by creation time to maintain order
      _capturedFrames.sort();

      debugPrint('Renaming ${_capturedFrames.length} frames sequentially...');

      for (var i = 0; i < _capturedFrames.length; i++) {
        final oldFile = File(_capturedFrames[i]);
        final newPath = '$framesDir/frame_${(i + 1).toString().padLeft(5, '0')}.png';

        if (await oldFile.exists()) {
          await oldFile.copy(newPath);
          debugPrint('Renamed frame ${i + 1}: ${oldFile.path} -> $newPath');
        } else {
          debugPrint('Warning: Frame file not found: ${oldFile.path}');
        }
      }

      debugPrint('Frame renaming completed successfully');
    } catch (e) {
      debugPrint('Error renaming frames: $e');
      rethrow;
    }
  }

  Future<void> _shareWaveformVideo() async {
    if (_videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate a video first')),
      );
      return;
    }

    await Share.shareXFiles(
      [XFile(_videoPath!)],
      text: 'Check out my audio waveform visualization!',
      subject: 'Waveform Video',
    );
  }

  Future<void> _captureWaveformFrame() async {
    if (!_isRecording) return;

    try {
      final boundary = _waveformKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final buffer = byteData.buffer.asUint8List();
      final framesDir = await _getFramesDirectory();
      final framePath = '$framesDir/frame_${DateTime
          .now()
          .millisecondsSinceEpoch}_$_frameCount.png';
      final file = File(framePath);
      await file.writeAsBytes(buffer);

      setState(() {
        _capturedFrames.add(framePath);
        _frameCount++;
      });

      debugPrint('Captured frame $_frameCount: $framePath');
    } catch (e) {
      debugPrint('Error capturing waveform frame: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .inversePrimary,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Recording status
          if (_isRecording)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x1AFF0000),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x4DFF0000)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Recording...',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Frames: ${_capturedFrames.length}',
                    style: const TextStyle(
                      color: Color(0xB3FF0000),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: Center(
              child: RepaintBoundary(
                key: _waveformKey,
                child: Container(
                  width: 720, // Fixed even width for consistent video output
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: const Color(0xFF1E1B26),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x4D000000),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: AudioWaveforms(
                    enableGesture: false,
                    size: const Size(680, 100),
                    // Fixed size for consistency
                    recorderController: _recordController,
                    waveStyle: const WaveStyle(
                      waveColor: Colors.blue,
                      extendWaveform: false,
                      middleLineColor: Colors.transparent,
                      showMiddleLine: false,
                      waveCap: StrokeCap.round,
                      waveThickness: 3.0,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      color: const Color(0xFF1E1B26),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FloatingActionButton(
                onPressed: _isRecording ? _stopRecording : _startRecording,
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                child: Icon(_isRecording ? Icons.stop : Icons.mic),
              ),
              if (_filePath != null && !_isRecording) ...[
                const SizedBox(width: 20),
                FloatingActionButton(
                  onPressed: _playRecording,
                  backgroundColor: _isPlaying ? Colors.orange : Colors.green,
                  child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 20),
                FloatingActionButton(
                  onPressed: _isGeneratingVideo ? null : _generateWaveformVideo,
                  backgroundColor: _isGeneratingVideo ? Colors.grey : Colors.purple,
                  child: _isGeneratingVideo
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Icon(Icons.video_call),
                ),
                const SizedBox(width: 20),
                FloatingActionButton(
                  onPressed: _videoPath != null ? _shareWaveformVideo : null,
                  backgroundColor: _videoPath != null ? Colors.indigo : Colors.grey,
                  child: const Icon(Icons.share),
                ),
              ],
            ],
          ),

          const SizedBox(height: 20),

          // Status information
          if (_capturedFrames.isNotEmpty && !_isRecording)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0x1A2196F3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x4D2196F3)),
              ),
              child: Text(
                'Captured ${_capturedFrames.length} frames for video generation',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
