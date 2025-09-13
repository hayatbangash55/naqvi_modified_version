// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
//
// import 'package:get/get.dart';
// import 'package:just_audio/just_audio.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:record/record.dart' as record;
//
// /// Recording states for VSP voice message flow
// enum VspRecordingState { notStarted, started, ended }
//
// class VspVoiceMsgController extends GetxController {
//   // State
//   final recordingState = VspRecordingState.notStarted.obs;
//   final recordingDuration = 0.obs; // seconds
//   final time = '00.00'.obs;
//   final lastTime = '00.00'.obs;
//   final isPlaying = false.obs;
//
//   // Timers & subscriptions
//   Timer? _timer;
//   StreamSubscription<Duration>? _positionSub;
//   StreamSubscription<PlayerState>? _playerStateSub;
//
//   // Audio (record v4.4.4)
//   final record.Record _rec = record.Record();
//   final AudioPlayer _audioPlayer = AudioPlayer();
//
//   String? filePath;
//
//   @override
//   void onClose() {
//     _timer?.cancel();
//     _positionSub?.cancel();
//     _playerStateSub?.cancel();
//     // record v4 has no dispose
//     _audioPlayer.dispose();
//     super.onClose();
//   }
//
//   Future<void> onPressMicBtn() async {
//     switch (recordingState.value) {
//       case VspRecordingState.notStarted:
//         await startRecording();
//         recordingState.value = VspRecordingState.started;
//         break;
//       case VspRecordingState.started:
//         await stopRecordingTimer();
//         recordingState.value = VspRecordingState.ended;
//         break;
//       case VspRecordingState.ended:
//         // Reset to initial state to allow a new recording
//         recordingState.value = VspRecordingState.notStarted;
//         time.value = '00.00';
//         lastTime.value = '00.00';
//         recordingDuration.value = 0;
//         break;
//     }
//   }
//
//   Future<void> startRecording() async {
//     filePath = await getFilePath();
//     try {
//       final hasPerm = await _rec.hasPermission();
//       if (!hasPerm) {
//         Get.snackbar(
//           'Permission Required',
//           'Please grant microphone permission to record audio.',
//           snackPosition: SnackPosition.BOTTOM,
//         );
//         return;
//       }
//
//       final isRec = await _rec.isRecording();
//       if (!isRec) {
//         await _rec.start(
//           path: filePath,
//           encoder: record.AudioEncoder.aacLc,
//           bitRate: 128000,
//           samplingRate: 44100,
//         );
//         startRecordingTimer();
//       }
//     } catch (e) {
//       Get.log('Error recording: $e');
//     }
//   }
//
//   void startRecordingTimer() {
//     lastTime.value = '00.00';
//     recordingDuration.value = 0;
//
//     _timer?.cancel();
//     _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
//       if (recordingDuration.value >= 300) {
//         timer.cancel();
//       } else {
//         recordingDuration.value++;
//         time.value =
//             '${(recordingDuration.value ~/ 60).toString().padLeft(2, '0')}.${(recordingDuration.value % 60).toString().padLeft(2, '0')}';
//       }
//     });
//   }
//
//   Future<void> stopRecordingTimer() async {
//     try {
//       final recordedPath = await _rec.stop(); // returns String?
//       if (recordedPath != null) {
//         filePath = recordedPath;
//         lastTime.value = time.value;
//         time.value = '00.00';
//       } else {
//         Get.log('No recording file returned.');
//       }
//     } catch (e) {
//       Get.log('Error stopping recording: $e');
//     } finally {
//       _timer?.cancel();
//       _timer = null;
//     }
//   }
//
//   Future<void> playTheAudio() async {
//     try {
//       if (!_audioPlayer.playing) {
//         if (filePath == null || !(await File(filePath!).exists())) return;
//
//         await _audioPlayer.setFilePath(filePath!);
//         isPlaying.value = true;
//         await _audioPlayer.play();
//
//         _positionSub?.cancel();
//         _positionSub = _audioPlayer.positionStream.listen((d) {
//           final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
//           final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
//           lastTime.value = '$minutes:$seconds';
//         });
//
//         _playerStateSub?.cancel();
//         _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
//           if (state.processingState == ProcessingState.completed) {
//             isPlaying.value = false;
//             _audioPlayer.stop();
//           }
//         });
//       } else {
//         await _audioPlayer.stop();
//         isPlaying.value = false;
//         await _positionSub?.cancel();
//         await _playerStateSub?.cancel();
//       }
//     } catch (e) {
//       Get.log('Error playing audio: $e');
//     }
//   }
//
//   Future<String> getFilePath() async {
//     final dir = await getTemporaryDirectory();
//     return '${dir.path}/voice_message.m4a';
//   }
//
//   Future<void> convertToBase64() async {
//     if (filePath == null || !(await File(filePath!).exists())) return;
//     final fileBytes = await File(filePath!).readAsBytes();
//     final base64String = base64Encode(fileBytes);
//     Get.log('Base64 String: ${base64String.substring(0, base64String.length > 64 ? 64 : base64String.length)}...');
//   }
//
//   Future<void> saveTheFile() async {
//     // In this repo, we don't have navigation routes; show a snackbar and encode.
//     Get.snackbar('Saved', 'Voice message saved', snackPosition: SnackPosition.BOTTOM);
//     await convertToBase64();
//   }
// }
