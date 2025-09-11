import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:io';

enum VideoStyle {
  waveform,
  circularWaveform,
  bars,
  spectrum
}

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  late final RecorderController _recordController;
  late final PlayerController _playerController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _filePath;
  String? _videoPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isGeneratingVideo = false;
  VideoStyle _selectedStyle = VideoStyle.waveform;
  StreamSubscription? _playerSubscription;
  int _currentDuration = 0;
  StreamSubscription? _durationSubscription;
  late ScrollController _scrollController;

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
    return '${dir.path}/output.mp4';
  }

  Future<void> _startRecording() async {
    // Stop any ongoing playback
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
      });
    } catch (e) {
      debugPrint('Error recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recordController.stop();
      setState(() {
        _isRecording = false;
        _filePath = path;
        _videoPath = null;
        _currentDuration = 0;
      });

      // Reset player and prepare with new recording
      if (path != null) {
        await _playerController.stopPlayer();
        await Future.delayed(const Duration(milliseconds: 200));
        await _playerController.preparePlayer(
          path: path,
          noOfSamples: MediaQuery.of(context).size.width.toInt() * 2, // Increased samples for better visualization
          shouldExtractWaveform: true,
        );
        _scrollController.jumpTo(0);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
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

  String _getFFmpegCommand(VideoStyle style, String inputPath, String outputPath) {
    switch (style) {
      case VideoStyle.waveform:
        return '-i $inputPath -filter_complex "[0:a]showwaves=s=1280x720:mode=line:colors=cyan,format=yuv420p[v]" -map "[v]" -map 0:a -c:v libx264 -c:a aac -b:a 192k -shortest -y $outputPath';

      case VideoStyle.circularWaveform:
        return '-i $inputPath -filter_complex "[0:a]aformat=channel_layouts=mono,showwaves=s=300x300:mode=cline:draw=full:colors=cyan[wave];color=s=1280x720:c=black[bg];[bg][wave]overlay=x=(W-w)/2:y=(H-h)/2,format=yuv420p[v]" -map "[v]" -map 0:a -c:v libx264 -c:a aac -b:a 192k -shortest -y $outputPath';

      case VideoStyle.bars:
        return '-i $inputPath -filter_complex "[0:a]showspectrum=s=1280x720:mode=bars:color=intensity:scale=cbrt:slide=scroll:saturation=0.5,format=yuv420p[v]" -map "[v]" -map 0:a -c:v libx264 -c:a aac -b:a 192k -shortest -y $outputPath';

      case VideoStyle.spectrum:
        return '-i $inputPath -filter_complex "[0:a]showspectrum=s=1280x720:mode=combined:color=rainbow:scale=lin:slide=scroll:saturation=4,format=yuv420p[v]" -map "[v]" -map 0:a -c:v libx264 -c:a aac -b:a 192k -shortest -y $outputPath';
    }
  }

  Future<void> _generateVideo() async {
    if (_filePath == null) return;

    setState(() {
      _isGeneratingVideo = true;
    });

    final videoPath = await _getVideoPath();
    _videoPath = videoPath;

    final command = _getFFmpegCommand(_selectedStyle, _filePath!, videoPath);

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video generated successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate video')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isGeneratingVideo = false;
      });
    }
  }

  Future<void> _shareContent() async {
    if (_videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate a video first')),
      );
      return;
    }

    await Share.shareXFiles(
      [XFile(_videoPath!)],
      text: 'Check out my audio visualization!',
      subject: 'Audio Visualization',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: _isRecording
                ? AudioWaveforms(
                    enableGesture: false, // Disable gestures
                    size: Size(MediaQuery.of(context).size.width * 0.8, 100), // Smaller height
                    recorderController: _recordController,
                    waveStyle: const WaveStyle(
                      waveColor: Colors.blue,
                      extendWaveform: false, // Do not extend waveform
                      middleLineColor: Colors.transparent,
                      showMiddleLine: false,
                      waveCap: StrokeCap.round,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      color: const Color(0xFF1E1B26),
                    ),
                    padding: const EdgeInsets.only(left: 18, right: 18),
                  )
                : AudioFileWaveforms(
                    size: Size(MediaQuery.of(context).size.width * 0.8, 100), // Smaller height
                    playerController: _playerController,
                    enableSeekGesture: false, // Disable seek gesture
                    waveformType: WaveformType.fitWidth, // Fit waveform within the width
                    playerWaveStyle: const PlayerWaveStyle(
                      fixedWaveColor: Colors.grey,
                      liveWaveColor: Colors.blue,
                      seekLineColor: Colors.transparent, // Hide the seek line
                      spacing: 4, // Adjust spacing for compact view
                      waveCap: StrokeCap.round,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      color: const Color(0xFF1E1B26),
                    ),
                    padding: const EdgeInsets.only(left: 18, right: 18),
                  ),
            ),
          ),
          if (!_isRecording && _filePath != null) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Text('Select Video Style:', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: VideoStyle.values.map((style) {
                      return ChoiceChip(
                        label: Text(style.name),
                        selected: _selectedStyle == style,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedStyle = style);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FloatingActionButton(
                onPressed: _isRecording ? _stopRecording : _startRecording,
                child: Icon(_isRecording ? Icons.stop : Icons.mic),
              ),
              if (_filePath != null && !_isRecording) ...[
                const SizedBox(width: 20),
                FloatingActionButton(
                  onPressed: _playRecording,
                  child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 20),
                FloatingActionButton(
                  onPressed: _isGeneratingVideo ? null : _generateVideo,
                  child: _isGeneratingVideo
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.video_library),
                ),
                const SizedBox(width: 20),
                FloatingActionButton(
                  onPressed: _shareContent,
                  child: const Icon(Icons.share),
                ),
              ],
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
