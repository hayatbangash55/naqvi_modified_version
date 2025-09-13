import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

class RecorderGetxController extends GetxController {
  // UI key to capture waveform frames
  final GlobalKey waveformKey = GlobalKey();

  // Controllers
  late final RecorderController recordController;
  late final PlayerController playerController;
  final AudioPlayer audioPlayer = AudioPlayer();
  final AudioRecorder mic = AudioRecorder();

  // State
  final isRecording = false.obs;
  final isPlaying = false.obs;
  final isGeneratingVideo = false.obs;
  final currentDuration = 0.obs;
  final recordElapsed = Rx<Duration>(Duration.zero);
  final framesCount = 0.obs; // NEW: reactive frame count

  // Paths
  String? filePath;
  String? videoPath;

  // Scrolling (kept for parity with original impl)
  final ScrollController scrollController = ScrollController();

  // Frame capture
  final List<String> capturedFrames = <String>[];
  Timer? _frameCaptureTimer;
  int _frameCount = 0;
  bool _captureBusy = false;

  // Amplitude tracking
  Timer? _ampTimer;
  final ValueNotifier<double> amp = ValueNotifier<double>(0.0);
  double _smoothedAmp = 0.0;
  final List<double> ampHistory = <double>[];
  final ValueNotifier<List<double>> playbackAmps = ValueNotifier<List<double>>([]);

  // Recording timer
  Timer? _recordTimer;
  DateTime? _recordStart;

  // Constants (mirroring original widget values)
  static const Color kWaveBgColor = Color(0xFF01004E);
  static const Color? kLogoTintColor = null;
  static const String kLogoAsset = 'assets/images/logo.png';

  static const double kNoiseFloorDb = -34.0;
  static const double kAmpAttack = 0.30;
  static const double kAmpRelease = 0.12;
  static const double kAmpGamma = 2.0;
  static const int kAmpQuantSteps = 0; // unused with smoothing

  static const int kMaxVerticalLogos = 20;
  static const double kHorizontalGap = 16.0;
  static const double kVerticalGap = 10.0;
  static const double kAmplitudeDensityDivisor = 16.0;
  static const double kMinLogoSize = 22.0;

  static const int kAmpSampleMs = 33; // ~30Hz to match capture FPS

  @override
  void onInit() {
    super.onInit();
    _initRecorder();
    _initPlayer();
  }

  @override
  void onClose() {
    recordController.dispose();
    playerController.dispose();
    audioPlayer.dispose();

    _ampTimer?.cancel();
    _frameCaptureTimer?.cancel();
    _recordTimer?.cancel();
    scrollController.dispose();
    mic.dispose();
    amp.dispose();
    playbackAmps.dispose();

    super.onClose();
  }

  void _initRecorder() {
    recordController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 48000;
  }

  void _initPlayer() {
    playerController = PlayerController();

    // Listen to player state changes
    playerController.onPlayerStateChanged.listen((state) {
      isPlaying.value = state.isPlaying;
      if (state.isStopped) {
        isPlaying.value = false;
        currentDuration.value = 0;
        if (scrollController.hasClients) {
          scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
        playbackAmps.value = [];
      }
    });

    // Progress updates
    playerController.onCurrentDurationChanged.listen((duration) {
      currentDuration.value = duration;
      if (currentDuration.value >= playerController.maxDuration) {
        isPlaying.value = false;
        if (scrollController.hasClients) {
          scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      } else if (isPlaying.value && scrollController.hasClients) {
        final scrollPosition = (currentDuration.value / playerController.maxDuration) *
            (scrollController.position.maxScrollExtent);
        scrollController.animateTo(
          scrollPosition,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        );
      }

      // playback window for custom waveform
      if (isPlaying.value && ampHistory.isNotEmpty) {
        final idx = (currentDuration.value / kAmpSampleMs).floor().clamp(0, ampHistory.length);
        playbackAmps.value = List.unmodifiable(ampHistory.sublist(0, idx));
      }
    });
  }

  Future<String> _getFilePath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/voice_message.m4a';
  }

  Future<String> _getVideoPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/waveform_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  Future<String> _getFramesDirectory() async {
    final dir = await getTemporaryDirectory();
    final framesDir = Directory('${dir.path}/waveform_frames');
    if (!await framesDir.exists()) {
      await framesDir.create(recursive: true);
    }
    return framesDir.path;
  }

  Future<void> startRecording() async {
    if (isPlaying.value) {
      await playerController.pausePlayer();
      isPlaying.value = false;
    }
    await _clearFramesDirectory();

    try {
      final hasPermission = await mic.hasPermission();
      if (!hasPermission) {
        _snack('Microphone permission is required to record audio', Colors.red);
        return;
      }
    } catch (e) {
      debugPrint('Permission check failed: $e');
    }

    final path = await _getFilePath();
    try {
      await mic.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: path,
      );

      debugPrint('Recording started successfully to: $path');

      isRecording.value = true;
      filePath = path;
      capturedFrames.clear();
      _frameCount = 0;
      framesCount.value = 0; // reset
      _smoothedAmp = 0.0;
      amp.value = 0.0;
      ampHistory.clear();
      playbackAmps.value = [];
      _recordStart = DateTime.now();
      recordElapsed.value = Duration.zero;

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!isRecording.value || _recordStart == null) return;
        final now = DateTime.now();
        recordElapsed.value = now.difference(_recordStart!);
      });

      _ampTimer?.cancel();
      _ampTimer = Timer.periodic(const Duration(milliseconds: kAmpSampleMs), (_) async {
        try {
          if (await mic.isRecording()) {
            final amplitude = await mic.getAmplitude();
            final db = amplitude.current;
            final minDb = kNoiseFloorDb;
            double target = db <= minDb ? 0.0 : ((db - minDb) / (0.0 - minDb)).clamp(0.0, 1.0);

            if (target > _smoothedAmp) {
              _smoothedAmp += kAmpAttack * (target - _smoothedAmp);
            } else {
              _smoothedAmp += kAmpRelease * (target - _smoothedAmp);
            }

            double mapped = math.pow(_smoothedAmp.clamp(0.0, 1.0), kAmpGamma).toDouble();
            final clamped = mapped.clamp(0.0, 1.0);
            ampHistory.add(clamped);
            amp.value = clamped;
          }
        } catch (e) {
          debugPrint('Amplitude monitoring error: $e');
        }
      });

      _startFrameCapture();
      _snack('Recording started', Colors.green);
    } catch (e) {
      debugPrint('Recording start failed: $e');
      _snack('Failed to start recording: ${e.toString()}', Colors.red);
      isRecording.value = false;
      filePath = null;
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording.value) return;

    try {
      debugPrint('Stopping recording...');
      final path = await mic.stop();

      _stopFrameCapture();
      _ampTimer?.cancel();
      _recordTimer?.cancel();
      _recordTimer = null;
      _recordStart = null;

      isRecording.value = false;
      _smoothedAmp = 0.0;
      amp.value = 0.0;

      if (path != null && await File(path).exists()) {
        debugPrint('Recording saved to: $path');
        filePath = path;
        videoPath = null;
        currentDuration.value = 0;

        try {
          await playerController.stopPlayer();
          await Future.delayed(const Duration(milliseconds: 200));
          await playerController.preparePlayer(
            path: path,
            noOfSamples: 1200,
            shouldExtractWaveform: true,
          );
          if (scrollController.hasClients) {
            scrollController.jumpTo(0);
          }
          _snack('Recording saved successfully', Colors.green);
        } catch (e) {
          debugPrint('Error preparing player: $e');
          _snack('Recording saved, but playback preparation failed', Colors.orange);
        }
      } else {
        debugPrint('Recording file not found or invalid path: $path');
        filePath = null;
        _snack('Recording failed - no file created', Colors.red);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _stopFrameCapture();
      _ampTimer?.cancel();
      _recordTimer?.cancel();
      _recordTimer = null;
      _recordStart = null;

      isRecording.value = false;
      _smoothedAmp = 0.0;
      amp.value = 0.0;
      filePath = null;

      _snack('Failed to stop recording: ${e.toString()}', Colors.red);
    }
  }

  Future<void> playRecording() async {
    if (filePath == null || !(await File(filePath!).exists())) return;

    try {
      if (isPlaying.value) {
        await playerController.pausePlayer();
        isPlaying.value = false;
      } else {
        if (currentDuration.value >= playerController.maxDuration) {
          await playerController.seekTo(0);
          if (scrollController.hasClients) {
            scrollController.jumpTo(0);
          }
        }
        await playerController.startPlayer();
        isPlaying.value = true;
      }
    } catch (e) {
      debugPrint('Error playing recording: $e');
      isPlaying.value = false;
    }
  }

  void _startFrameCapture() {
    const frameDuration = Duration(milliseconds: 66); // ~15 FPS
    _frameCaptureTimer = Timer.periodic(frameDuration, (_) {
      _captureWaveformFrame();
    });
  }

  void _stopFrameCapture() {
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = null;
  }

  Future<void> _captureWaveformFrame() async {
    if (!isRecording.value || _captureBusy) return;
    _captureBusy = true;
    try {
      final boundary = waveformKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      await WidgetsBinding.instance.endOfFrame;

      final logicalSize = boundary.size;
      double pixelRatio = 0.8;
      if (logicalSize.width > 0 && logicalSize.height > 0) {
        final scaleW = 480.0 / logicalSize.width;
        pixelRatio = scaleW.clamp(0.5, 1.0);
      }

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;

      final buffer = byteData.buffer.asUint8List();
      final framesDir = await _getFramesDirectory();
      final framePath = '$framesDir/frame_${DateTime.now().millisecondsSinceEpoch}_$_frameCount.png';

      final file = File(framePath);
      await file.writeAsBytes(buffer, flush: false);

      capturedFrames.add(framePath);
      _frameCount++;
      framesCount.value = _frameCount; // update reactive count
    } catch (e) {
      debugPrint('Error capturing waveform frame: $e');
    } finally {
      _captureBusy = false;
    }
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

  Future<void> generateWaveformVideo() async {
    if (filePath == null || capturedFrames.isEmpty) {
      _snack('Please record audio first', Colors.orange);
      return;
    }

    isGeneratingVideo.value = true;

    try {
      final videoPathOut = await _getVideoPath();
      final framesDir = await _getFramesDirectory();

      final audioFile = File(filePath!);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found');
      }

      await audioPlayer.setFilePath(filePath!);
      final durMs = audioPlayer.duration?.inMilliseconds ?? 0;
      final audioSeconds = durMs / 1000.0;

      if (audioSeconds <= 0) {
        throw Exception('Invalid audio duration');
      }

      final actualCaptureRate = capturedFrames.length / audioSeconds;
      debugPrint('Audio duration: ${audioSeconds.toStringAsFixed(2)}s');
      debugPrint('Captured frames: ${capturedFrames.length}');
      debugPrint('Actual capture rate: ${actualCaptureRate.toStringAsFixed(2)} fps');

      const double outputFps = 15.0;
      final neededFrames = (audioSeconds * outputFps).round();
      debugPrint('Needed frames for ${outputFps}fps: $neededFrames');

      final framePattern = '$framesDir/frame_%05d.png';

      await _renameFramesSequentially();

      final renamedFramesDir = Directory(framesDir);
      final renamedFrames = await renamedFramesDir
          .list()
          .where((file) => file.path.contains('frame_') && file.path.endsWith('.png'))
          .length;

      debugPrint('Frames available after renaming: $renamedFrames');

      final inputFrameRate = renamedFrames / audioSeconds;
      final clampedInputRate = inputFrameRate.clamp(10.0, 30.0);

      debugPrint('Calculated input frame rate: ${inputFrameRate.toStringAsFixed(2)} fps');
      debugPrint('Using clamped input rate: ${clampedInputRate.toStringAsFixed(2)} fps');

      final vf = 'fps=$outputFps,scale=360:640:force_original_aspect_ratio=decrease,pad=360:640:(ow-iw)/2:(oh-ih)/2:color=0x01004E';

      final command = [
        '-y',
        '-framerate', clampedInputRate.toStringAsFixed(2),
        '-i', framePattern,
        '-i', filePath!,
        '-map', '0:v:0',
        '-map', '1:a:0',
        '-vf', vf,
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-tune', 'zerolatency',
        '-crf', '28',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-ac', '1',
        '-b:a', '64k',
        '-avoid_negative_ts', 'make_zero',
        '-fflags', '+genpts',
        '-movflags', '+faststart',
        '-threads', '0',
        videoPathOut,
      ].join(' ');

      debugPrint('FFmpeg command: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final logs = await session.getLogsAsString();
      debugPrint('FFmpeg logs: $logs');

      if (ReturnCode.isSuccess(returnCode)) {
        videoPath = videoPathOut;
        _snack('Waveform video generated successfully!', Colors.green);
      } else {
        debugPrint('FFmpeg failed with return code: $returnCode');
        throw Exception('FFmpeg failed with return code: $returnCode');
      }
    } catch (e) {
      debugPrint('Error generating video: $e');
      _snack('Error: $e', Colors.red);
    } finally {
      isGeneratingVideo.value = false;
    }
  }

  Future<void> _renameFramesSequentially() async {
    try {
      final framesDir = await _getFramesDirectory();

      capturedFrames.sort();
      debugPrint('Renaming ${capturedFrames.length} frames sequentially...');

      for (var i = 0; i < capturedFrames.length; i++) {
        final oldFile = File(capturedFrames[i]);
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

  Future<void> shareWaveformVideo() async {
    if (videoPath == null) {
      _snack('Please generate a video first', Colors.orange);
      return;
    }

    await Share.shareXFiles(
      [XFile(videoPath!)],
      text: 'Check out my audio waveform visualization!',
      subject: 'Waveform Video',
    );
  }

  void _snack(String message, Color bg) {
    Get.showSnackbar(
      GetSnackBar(
        message: message,
        backgroundColor: bg,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
      ),
    );
  }
}
