import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart'; // for ValueListenable/ValueNotifier and compute()
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:typed_data'; // NEW for Uint8List
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/services.dart';

// Custom Waveform Widget
class CustomWaveformWidget extends StatefulWidget {
  final RecorderController? recorderController;
  final PlayerController? playerController;
  final bool isRecording;
  final bool isPlaying;
  final int currentDuration;
  final double width;
  final double height;
  final String logoAssetPath;
  final ValueListenable<double> amplitude; // NEW: live amplitude 0..1
  final Color backgroundColor; // NEW: solid bg color
  final Color? logoTint; // NEW: optional logo tint

  // NEW: controls logo size (lower => bigger logos)
  final int maxVerticalLogos;

  // NEW: spacing between columns
  final double horizontalGap;

  // NEW: spacing between stacked logos
  final double verticalGap;

  // NEW: controls number of columns in amplitude buffer
  final double amplitudeDensityDivisor;

  const CustomWaveformWidget({
    super.key,
    this.recorderController,
    this.playerController,
    required this.isRecording,
    required this.isPlaying,
    required this.currentDuration,
    required this.width,
    required this.height,
    required this.logoAssetPath,
    required this.amplitude,
    this.backgroundColor = const Color(0xFF01004E), // NEW default
    this.logoTint, // NEW
    this.maxVerticalLogos = 30, // default previous behavior
    this.horizontalGap = 10.0,
    this.verticalGap = 6.0,
    this.amplitudeDensityDivisor = 12.0,
  });

  @override
  State<CustomWaveformWidget> createState() => _CustomWaveformWidgetState();
}

class _CustomWaveformWidgetState extends State<CustomWaveformWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  final List<double> _amplitudes = [];
  Timer? _amplitudeTimer;
  ui.Image? _logoImage;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    )..repeat();
    _initializeAmplitudes();
    _loadLogoImage();
  }

  void _initializeAmplitudes() {
    final patternCount = (widget.width / widget.amplitudeDensityDivisor).ceil();
    _amplitudes
      ..clear()
      ..addAll(List.filled(patternCount, 0.05));

    // Timer to shift columns using provided amplitude
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final live = widget.amplitude.value.clamp(0.0, 1.0);
      setState(() {
        if (_amplitudes.isNotEmpty) {
          _amplitudes.removeAt(0);
          _amplitudes.add(live);
        }
      });
    });
  }

  void _loadLogoImage() async {
    try {
      final data = await rootBundle.load(widget.logoAssetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _logoImage = frame.image);
    } catch (e) {
      debugPrint('Logo load error: $e');
    }
  }

  @override
  void didUpdateWidget(CustomWaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.width != oldWidget.width) {
      _initializeAmplitudes();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _amplitudeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        color: widget.backgroundColor, // solid bg
        boxShadow: [
          BoxShadow(
            color: const Color(0x4D000000),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: CustomPaint(
          painter: WaveformLogoPainter(
            amplitudes: _amplitudes,
            isRecording: widget.isRecording,
            isPlaying: widget.isPlaying,
            currentDuration: widget.currentDuration,
            maxDuration: widget.playerController?.maxDuration ?? 1000,
            animation: (widget.isRecording || widget.isPlaying)
                ? _animationController
                : const AlwaysStoppedAnimation(0.0),
            logoImage: _logoImage,
            logoTint: widget.logoTint,
            maxVerticalLogos: widget.maxVerticalLogos, // NEW
            horizontalGap: widget.horizontalGap, // NEW
            verticalGap: widget.verticalGap, // NEW
          ),
          size: Size(widget.width, widget.height),
        ),
      ),
    );
  }
}

// NEW: Painter that draws logo in vertical wave pattern
class WaveformLogoPainter extends CustomPainter {
  final List<double> amplitudes;
  final bool isRecording;
  final bool isPlaying;
  final int currentDuration;
  final int maxDuration;
  final Animation<double> animation;
  final ui.Image? logoImage;
  final Color? logoTint;
  final int maxVerticalLogos; // NEW
  final double horizontalGap; // NEW
  final double verticalGap; // NEW

  WaveformLogoPainter({
    required this.amplitudes,
    required this.isRecording,
    required this.isPlaying,
    required this.currentDuration,
    required this.maxDuration,
    required this.animation,
    required this.logoImage,
    this.logoTint,
    this.maxVerticalLogos = 30,
    this.horizontalGap = 10.0,
    this.verticalGap = 6.0,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    // No solid fill here; container already paints bg color

    // If logo not yet loaded, draw a subtle placeholder so UI isn't empty
    if (logoImage == null) {
      final placeholder = Paint()..color = const Color(0x33FFFFFF);
      final double barW = 4, gap = 6;
      for (double x = 0; x < size.width; x += (barW + gap)) {
        final h = (size.height * 0.3) + (size.height * 0.2) * math.sin(x / 20);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x, size.height / 2), width: barW, height: h),
              const Radius.circular(2)),
          placeholder,
        );
      }
      return;
    }

    // Use configurable geometry
    final double logoHeight = ((size.height - (maxVerticalLogos - 1) * verticalGap) / maxVerticalLogos)
        .clamp(2.0, size.height);
    final double logoWidth = logoHeight;
    final double perCol = logoWidth + horizontalGap;
    final int columnCount = perCol > 0 ? ((size.width + horizontalGap) / perCol).floor() : 0;
    final double contentWidth = columnCount * logoWidth + (columnCount - 1) * horizontalGap;
    final double leftPad = ((size.width - contentWidth) / 2).clamp(0.0, size.width);

    final Paint paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    if (logoTint != null) {
      paint.colorFilter = ColorFilter.mode(logoTint!, BlendMode.srcATop);
    }

    for (int col = 0; col < columnCount; col++) {
      // Read amplitude or fall back to last/zero if not enough samples
      final double baseAmp = (col < amplitudes.length)
          ? amplitudes[col]
          : (amplitudes.isNotEmpty ? amplitudes.last : 0.0);
      final double amplitude = baseAmp.clamp(0.0, 1.0);

      final double x = leftPad + col * (logoWidth + horizontalGap) + logoWidth / 2;

      // Map amplitude 0..1 to 1..maxVerticalLogos (ceil)
      final int logoCount = amplitude <= 0
          ? 1
          : (amplitude * maxVerticalLogos).ceil().clamp(1, maxVerticalLogos);

      // Compute vertical stack positioning
      final double totalStackHeight = logoCount * logoHeight + (logoCount - 1) * verticalGap;
      final double startY = (size.height - totalStackHeight) / 2.0 + logoHeight / 2.0;

      for (int i = 0; i < logoCount; i++) {
        final double y = startY + i * (logoHeight + verticalGap);
        final rect = Rect.fromCenter(
          center: Offset(x, y),
          width: logoWidth,
          height: logoHeight,
        );
        canvas.drawImageRect(
          logoImage!,
          Rect.fromLTWH(0, 0, logoImage!.width.toDouble(), logoImage!.height.toDouble()),
          rect,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(WaveformLogoPainter oldDelegate) {
    return oldDelegate.amplitudes != amplitudes ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.currentDuration != currentDuration ||
        oldDelegate.maxDuration != maxDuration ||
        oldDelegate.logoImage != logoImage;
  }
}

class CustomRecorderScreen extends StatefulWidget {
  const CustomRecorderScreen({super.key});

  @override
  State<CustomRecorderScreen> createState() => _CustomRecorderScreenState();
}

class _CustomRecorderScreenState extends State<CustomRecorderScreen> {
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
  final AudioRecorder _mic = AudioRecorder(); // use concrete AudioRecorder
  Timer? _ampTimer; // amplitude polling
  final ValueNotifier<double> _amp = ValueNotifier<double>(0); // 0..1
  bool _captureBusy = false; // throttle capture

  // NEW: easy-to-edit colors
  static const Color kWaveBgColor = Color(0xFF01004E);
  static const Color? kLogoTintColor = null; // set to a Color to tint logo
  static const String kLogoAsset = 'assets/images/logo.png'; // NEW: logo asset path

  // NEW: amplitude smoothing constants (tweak to change rigidity)
  static const double kNoiseFloorDb = -38.0; // higher gate -> less sensitivity to low noise
  static const double kAmpAttack = 0.25;     // slower rise -> feels more rigid
  static const double kAmpRelease = 0.06;    // slower fall -> avoids jitter
  static const double kAmpGamma = 2.0;       // stronger curve -> de-emphasize small signals
  static const int kAmpQuantSteps = 24;      // 0 to disable; higher -> finer steps

  // NEW: smoothed amplitude state
  double _smoothedAmp = 0.0;

  // NEW: spacing/size controls for the wave grid
  static const int kMaxVerticalLogos = 22; // fewer rows -> larger logo size
  static const double kHorizontalGap = 16.0; // slightly more distance between waves
  static const double kVerticalGap = 10.0; // slightly more distance vertically
  static const double kAmplitudeDensityDivisor = 16.0; // columns count (unchanged)

  // NEW: stopwatch-like timer for recording duration
  Timer? _recordTimer;
  DateTime? _recordStart;
  Duration _recordElapsed = Duration.zero;

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
      ..sampleRate = 48000; // increased quality
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
    _ampTimer?.cancel();
    _mic.dispose();
    _recordTimer?.cancel();
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
    if (_isPlaying) {
      await _playerController.pausePlayer();
      setState(() => _isPlaying = false);
    }
    await _clearFramesDirectory();

    final path = await _getFilePath();
    try {
      // Start mic recording with high quality
      await _mic.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 48000,
          bitRate: 128000,
        ),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _filePath = path;
        _capturedFrames.clear();
        _frameCount = 0;
        _smoothedAmp = 0.0; // reset smoothing at start
        _amp.value = 0.0;
        // start stopwatch
        _recordStart = DateTime.now();
        _recordElapsed = Duration.zero;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!_isRecording || _recordStart == null) return;
        final now = DateTime.now();
        setState(() {
          _recordElapsed = now.difference(_recordStart!);
        });
      });

      // Start amplitude polling
      _ampTimer?.cancel();
      _ampTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
        try {
          if (await _mic.isRecording()) {
            final amplitude = await _mic.getAmplitude();
            final db = amplitude.current;
            final minDb = kNoiseFloorDb;
            // Noise gate + normalization 0..1
            double target = db <= minDb ? 0.0 : ((db - minDb) / (0.0 - minDb)).clamp(0.0, 1.0);
            // Attack/Release EMA
            if (target > _smoothedAmp) {
              _smoothedAmp += kAmpAttack * (target - _smoothedAmp);
            } else {
              _smoothedAmp += kAmpRelease * (target - _smoothedAmp);
            }
            // Gamma curve, optional quantization
            double mapped = math.pow(_smoothedAmp.clamp(0.0, 1.0), kAmpGamma).toDouble();
            if (kAmpQuantSteps > 0) {
              mapped = (mapped * kAmpQuantSteps).round() / kAmpQuantSteps;
            }
            _amp.value = mapped.clamp(0.0, 1.0);
          }
        } catch (_) {}
      });

      // Start frame capture at throttled FPS
      _startFrameCapture();
    } catch (e) {
      debugPrint('Error recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _mic.stop();
      setState(() {
        _isRecording = false;
        _filePath = path;
        _videoPath = null;
        _currentDuration = 0;
      });

      // Stop capture and amplitude polling
      _stopFrameCapture();
      _ampTimer?.cancel();
      _smoothedAmp = 0.0; // reset smoothing at stop
      _amp.value = 0;

      // stop stopwatch
      _recordTimer?.cancel();
      _recordTimer = null;
      _recordStart = null;

      if (path != null) {
        await _playerController.stopPlayer();
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          await _playerController.preparePlayer(
            path: path,
            noOfSamples: 1200,
            shouldExtractWaveform: true,
          );
          _scrollController.jumpTo(0);
        }
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _startFrameCapture() {
    // Throttle to ~15 FPS to reduce main-thread load
    const frameDuration = Duration(milliseconds: 66);
    _frameCaptureTimer = Timer.periodic(frameDuration, (timer) {
      _captureWaveformFrame();
    });
  }

  void _stopFrameCapture() {
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = null;
  }

  Future<void> _captureWaveformFrame() async {
    if (!_isRecording || _captureBusy) return;
    _captureBusy = true;
    try {
      final boundary = _waveformKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      await WidgetsBinding.instance.endOfFrame;

      // Compute pixelRatio to get ~1080x1920 output based on current logical size
      final logicalSize = (boundary.size);
      double pixelRatio = 1.0;
      if (logicalSize.width > 0 && logicalSize.height > 0) {
        final scaleW = 1080.0 / logicalSize.width;
        // If aspect ratio is enforced to 9:16, scaleW ~ scaleH; choose scaleW for exact 1080 width
        pixelRatio = scaleW;
      }

      final image = await boundary.toImage(pixelRatio: pixelRatio.clamp(1.0, 4.0));
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;

      final buffer = byteData.buffer.asUint8List();
      final framesDir = await _getFramesDirectory();
      final framePath = '$framesDir/frame_${DateTime.now().millisecondsSinceEpoch}_$_frameCount.png';

      // Offload disk write to a background isolate using compute()
      await compute(_writePngToFile, _FileWritePayload(framePath, buffer));

      setState(() {
        _capturedFrames.add(framePath);
        _frameCount++;
      });
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
      final durMs = _audioPlayer.duration?.inMilliseconds ?? 0;
      int calculatedFPS;
      if (durMs > 0) {
        calculatedFPS = ((_capturedFrames.length * 1000) / durMs).round();
      } else {
        calculatedFPS = _targetFPS;
      }

      // Ensure minimum frame rate of 1 and maximum of 60 for practical video generation
      final actualFPS = calculatedFPS.clamp(1, 60);

      debugPrint(
          'Audio duration: ${(durMs / 1000).toStringAsFixed(2)}s, Frames: ${_capturedFrames.length}, Calculated FPS: $calculatedFPS, Using FPS: $actualFPS');

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
        '-vf', 'scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=0x01004E', // Ensure even dimensions
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Voice Recorder'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                  const SizedBox(width: 12),
                  Text(
                    _formatDuration(_recordElapsed),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
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

          // Optional timer above even when status hidden (only show while recording)
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Time ${_formatDuration(_recordElapsed)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),

          Expanded(
            child: Center(
              child: RepaintBoundary(
                key: _waveformKey,
                child: Builder(
                  builder: (ctx) {
                    final screen = MediaQuery.of(ctx).size;
                    // Enforce 9:16 box
                    final maxW = screen.width;
                    final maxH = screen.height * 0.9;
                    double targetW = maxW;
                    double targetH = targetW * 16.0 / 9.0;
                    if (targetH > maxH) {
                      targetH = maxH;
                      targetW = targetH * 9.0 / 16.0;
                    }
                    return SizedBox(
                      width: targetW,
                      height: targetH,
                      child: CustomWaveformWidget(
                        recorderController: null,
                        playerController: _playerController,
                        isRecording: _isRecording,
                        isPlaying: _isPlaying,
                        currentDuration: _currentDuration,
                        width: targetW,
                        height: targetH,
                        logoAssetPath: kLogoAsset,
                        amplitude: _amp,
                        backgroundColor: kWaveBgColor,
                        logoTint: kLogoTintColor,
                        maxVerticalLogos: kMaxVerticalLogos,
                        horizontalGap: kHorizontalGap,
                        verticalGap: kVerticalGap,
                        amplitudeDensityDivisor: kAmplitudeDensityDivisor,
                      ),
                    );
                  },
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
                'Captured ${_capturedFrames.length} (${(_capturedFrames.length/30).toInt()}) frames for video generation',
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

// Top-level payload and writer used by compute() to avoid unsendable closures
class _FileWritePayload {
  final String path;
  final Uint8List bytes;
  const _FileWritePayload(this.path, this.bytes);
}

Future<bool> _writePngToFile(_FileWritePayload payload) async {
  final file = File(payload.path);
  await file.writeAsBytes(payload.bytes, flush: false);
  return true;
}
