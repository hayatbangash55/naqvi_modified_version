import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  late final AudioRecorder _audioRecorder;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _filePath;
  String? _videoPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isGeneratingVideo = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
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
    final path = await _getFilePath();
    try {
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc, // Changed from wav to aacLc for better compatibility
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _filePath = path;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
    } catch (e) {
      debugPrint('Error recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _videoPath = null; // Reset video path when new recording is made
      });
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  Future<void> _playRecording() async {
    if (_filePath == null || !(await File(_filePath!).exists())) return;

    print('Path : $_filePath');
    try {
      await _audioPlayer.setFilePath(_filePath!);
      setState(() {
        _isPlaying = true;
      });
      await _audioPlayer.play();
    } finally {
      setState(() {
        _isPlaying = false;
      });
    }
  }

  Future<void> _startPlaying() async {
    if (_filePath == null) return;

    try {
      await _audioPlayer.setFilePath(_filePath!);
      await _audioPlayer.play();
      setState(() {
        _isPlaying = true;
      });

      // Reset playing state when audio completes
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlaying = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error playing recording: $e');
    }
  }

  Future<void> _stopPlaying() async {
    try {
      await _audioPlayer.stop();
      setState(() {
        _isPlaying = false;
      });
    } catch (e) {
      debugPrint('Error stopping playback: $e');
    }
  }

  Future<void> _generateVideo() async {
    if (_filePath == null) return;

    setState(() {
      _isGeneratingVideo = true;
    });

    final videoPath = await _getVideoPath();
    _videoPath = videoPath;

    // FFmpeg command to generate video with waveform
    final command =
        '-i $_filePath -filter_complex "[0:a]showwaves=s=1280x720:mode=line:colors=cyan,format=yuv420p[v]" -map "[v]" -map 0:a -c:v libx264 -c:a aac -b:a 192k -shortest -y $videoPath';

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

  Future<void> _shareVideo() async {
    if (_videoPath == null) return;
    await Share.shareXFiles(
        [XFile(_videoPath!)], text: 'Check out my audio visualization!');
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recorder'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            const SizedBox(height: 16),
            if (_filePath != null) ...[
              ElevatedButton(
                onPressed: _isPlaying ? _stopPlaying : _startPlaying,
                child: Text(_isPlaying ? 'Stop Playing' : 'Play Recording'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isGeneratingVideo ? null : _generateVideo,
                child: _isGeneratingVideo
                    ? const CircularProgressIndicator()
                    : const Text('Generate Video'),
              ),
              if (_videoPath != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _shareVideo,
                  child: const Text('Share Video'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
