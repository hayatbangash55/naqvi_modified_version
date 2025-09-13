import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'recorder_controller.dart';

// Custom Waveform Widget (GetX-driven)
class CustomWaveformWidget extends StatefulWidget {
  final double width;
  final double height;

  const CustomWaveformWidget({super.key, required this.width, required this.height});

  @override
  State<CustomWaveformWidget> createState() => _CustomWaveformWidgetState();
}

class _CustomWaveformWidgetState extends State<CustomWaveformWidget>
    with TickerProviderStateMixin {
  late final RecorderGetxController controller = Get.find<RecorderGetxController>();

  late AnimationController _animationController;
  final List<double> _amplitudes = [];
  Timer? _amplitudeTimer;
  ui.Image? _logoImage;
  VoidCallback? _playbackListener;
  bool _lastIsRecording = false;

  // Smooth playback lerp state
  static const int _playbackLerpMs = 90;
  List<double>? _prevAmpsLerp;
  List<double>? _targetAmpsLerp;
  DateTime? _lerpStart;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    )..addListener(_onAnimTick)
     ..repeat();
    _initializeAmplitudes();
    _loadLogoImage();
    _attachPlaybackListener();
  }

  // Drive interpolation while playing for smoother column changes
  void _onAnimTick() {
    if (!mounted) return;
    if (!controller.isPlaying.value) return;
    if (_prevAmpsLerp == null || _targetAmpsLerp == null || _lerpStart == null) return;

    final elapsed = DateTime.now().difference(_lerpStart!).inMilliseconds;
    final t = (elapsed / _playbackLerpMs).clamp(0.0, 1.0);

    final prev = _prevAmpsLerp!;
    final target = _targetAmpsLerp!;
    final n = math.min(prev.length, target.length);

    final blended = List<double>.generate(
      n,
      (i) {
        final a = prev[i];
        final b = target[i];
        return (a + (b - a) * t).clamp(0.0, 1.0);
      },
      growable: false,
    );

    if (_amplitudes.length != blended.length || !_listAlmostEqual(_amplitudes, blended)) {
      setState(() {
        _amplitudes
          ..clear()
          ..addAll(blended);
      });
    }

    if (t >= 1.0) {
      _prevAmpsLerp = List<double>.from(blended);
      _lerpStart = null;
    }
  }

  bool _listAlmostEqual(List<double> a, List<double> b, {double eps = 1e-3}) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > eps) return false;
    }
    return true;
  }

  void _attachPlaybackListener() {
    _playbackListener?.call();
    _playbackListener = null;
    final srcListenable = controller.playbackAmps;
    void listener() {
      if (!mounted) return;
      final patternCount = _computeColumnCount().clamp(1, 10000);
      final src = srcListenable.value;
      List<double> tail;
      if (src.isEmpty) {
        tail = List.filled(patternCount, 0.0);
      } else {
        final start = src.length > patternCount ? src.length - patternCount : 0;
        tail = src.sublist(start);
        if (tail.length < patternCount) {
          final padCount = patternCount - tail.length;
          tail = List<double>.filled(padCount, 0.0, growable: true)..addAll(tail);
        }
      }
      final current = List<double>.generate(patternCount, (i) {
        final idx = _amplitudes.length - patternCount + i;
        final v = (idx >= 0 && idx < _amplitudes.length) ? _amplitudes[idx] : 0.0;
        return v.clamp(0.0, 1.0);
      }, growable: false);

      _prevAmpsLerp = current;
      _targetAmpsLerp = tail.map((e) => e.clamp(0.0, 1.0)).toList(growable: false);
      _lerpStart = DateTime.now();
    }

    srcListenable.addListener(listener);
    _playbackListener = () => srcListenable.removeListener(listener);
  }

  void _initializeAmplitudes() {
    final patternCount = _computeColumnCount().clamp(1, 10000);
    _amplitudes
      ..clear()
      ..addAll(List.filled(patternCount, 0.05));

    _prevAmpsLerp = null;
    _targetAmpsLerp = null;
    _lerpStart = null;

    _amplitudeTimer?.cancel();
    if (controller.isRecording.value) {
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted) return;
        final live = controller.amp.value.clamp(0.0, 1.0);
        setState(() {
          if (_amplitudes.isNotEmpty) {
            _amplitudes.removeAt(0);
            _amplitudes.add(live);
          }
        });
      });
    }
  }

  void _loadLogoImage() async {
    try {
      final data = await rootBundle.load(RecorderGetxController.kLogoAsset);
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
    if (widget.width != oldWidget.width || widget.height != oldWidget.height) {
      _initializeAmplitudes();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _amplitudeTimer?.cancel();
    _playbackListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Detect recording state change to reset amplitudes/timer
    final isRec = controller.isRecording.value;
    if (isRec != _lastIsRecording) {
      _lastIsRecording = isRec;
      _initializeAmplitudes();
    }

    return Obx(() {
      final isRecording = controller.isRecording.value;
      final isPlaying = controller.isPlaying.value;
      final currentDuration = controller.currentDuration.value;

      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          color: RecorderGetxController.kWaveBgColor,
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: CustomPaint(
            painter: WaveformLogoPainter(
              amplitudes: _amplitudes,
              isRecording: isRecording,
              isPlaying: isPlaying,
              currentDuration: currentDuration,
              maxDuration: controller.playerController.maxDuration,
              animation: (isRecording || isPlaying)
                  ? _animationController
                  : const AlwaysStoppedAnimation(0.0),
              logoImage: _logoImage,
              logoTint: RecorderGetxController.kLogoTintColor,
              maxVerticalLogos: RecorderGetxController.kMaxVerticalLogos,
              horizontalGap: RecorderGetxController.kHorizontalGap,
              verticalGap: RecorderGetxController.kVerticalGap,
              minLogoSize: RecorderGetxController.kMinLogoSize,
            ),
            size: Size(widget.width, widget.height),
          ),
        ),
      );
    });
  }

  int _computeColumnCount() {
    final rows = (((widget.height + RecorderGetxController.kVerticalGap) /
                (RecorderGetxController.kMinLogoSize + RecorderGetxController.kVerticalGap))
            .floor())
        .clamp(1, RecorderGetxController.kMaxVerticalLogos);
    final logoHeight = ((widget.height - (rows - 1) * RecorderGetxController.kVerticalGap) / rows)
        .clamp(RecorderGetxController.kMinLogoSize, widget.height);
    final perCol = logoHeight + RecorderGetxController.kHorizontalGap;
    final columnCount = perCol > 0
        ? ((widget.width + RecorderGetxController.kHorizontalGap) / perCol).floor()
        : 0;
    return columnCount;
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
  final double minLogoSize; // NEW

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
    this.minLogoSize = 16.0, // NEW
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

    // Compute an effective number of rows so each logo is at least minLogoSize tall
    final int maxRowsFitByHeight = ((size.height + verticalGap) / (minLogoSize + verticalGap)).floor().clamp(1, maxVerticalLogos);
    final int rows = maxRowsFitByHeight; // dynamic rows ensures no tiny dots

    final double logoHeight = ((size.height - (rows - 1) * verticalGap) / rows).clamp(minLogoSize, size.height);
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
          : (amplitude * rows).ceil().clamp(1, rows);

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

class CustomRecorderScreen extends GetView<RecorderGetxController> {
  const CustomRecorderScreen({super.key});

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01004E),
      appBar: AppBar(
        title: const Text('Custom Voice Recorder'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Obx(() {
        final isRecording = controller.isRecording.value;
        final isPlaying = controller.isPlaying.value;
        final frames = controller.framesCount.value;
        final elapsed = controller.recordElapsed.value;
        final isGenerating = controller.isGeneratingVideo.value;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isRecording)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
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
                      _formatDuration(elapsed),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Frames: $frames',
                      style: const TextStyle(
                        color: Color(0xB3FF0000),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

            if (isRecording)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Time ',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            if (isRecording)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _formatDuration(elapsed),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),

            Expanded(
              child: Center(
                child: RepaintBoundary(
                  key: controller.waveformKey,
                  child: Builder(
                    builder: (ctx) {
                      final screen = MediaQuery.of(ctx).size;
                      final double targetW = screen.width;
                      final double targetH = screen.height * 0.30;
                      return SizedBox(
                        width: targetW,
                        height: targetH,
                        child: CustomWaveformWidget(
                          width: targetW,
                          height: targetH,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  onPressed: isRecording ? controller.stopRecording : controller.startRecording,
                  backgroundColor: isRecording ? Colors.red : Colors.blue,
                  child: Icon(isRecording ? Icons.stop : Icons.mic),
                ),
                if (controller.filePath != null && !isRecording) ...[
                  const SizedBox(width: 20),
                  FloatingActionButton(
                    onPressed: controller.playRecording,
                    backgroundColor: isPlaying ? Colors.orange : Colors.green,
                    child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  const SizedBox(width: 20),
                  FloatingActionButton(
                    onPressed: isGenerating ? null : controller.generateWaveformVideo,
                    backgroundColor: isGenerating ? Colors.grey : Colors.purple,
                    child: isGenerating
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
                    onPressed: controller.videoPath != null ? controller.shareWaveformVideo : null,
                    backgroundColor: controller.videoPath != null ? Colors.indigo : Colors.grey,
                    child: const Icon(Icons.share),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 20),

            if (frames > 0 && !isRecording)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0x1A2196F3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x4D2196F3)),
                ),
                child: Text(
                  'Captured $frames (${(frames/30).toInt()}) frames for video generation',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 40),
          ],
        );
      }),
    );
  }
}
