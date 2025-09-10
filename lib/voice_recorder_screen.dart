import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  late final AudioRecorder _audioRecorder;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _filePath;
  bool _isRecording = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
  }

  Future<String> _getFilePath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_message.m4a';
  }

  Future<void> _startRecording() async {
    final path = await _getFilePath();
    try {

      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          RecordConfig(
            encoder: AudioEncoder.wav,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _filePath = path;
        });
      }else{
        print("Show dialog Permission Required");
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

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Recorder')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isRecording ? null : _startRecording,
              child: const Text('Start Recording'),
            ),
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : null,
              child: const Text('Stop Recording'),
            ),
            ElevatedButton(
              onPressed: (!_isRecording && _filePath != null && !_isPlaying) ? _playRecording : null,
              child: const Text('Play Recording'),
            ),
          ],
        ),
      ),
    );
  }
}
