// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'vsp_voice_msg_controller.dart';
//
// class VspVoiceMsgScreen extends GetView<VspVoiceMsgController> {
//   const VspVoiceMsgScreen({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFF01004E),
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
//           child: Column(
//             children: [
//               Align(
//                 alignment: Alignment.centerRight,
//                 child: IconButton(
//                   onPressed: () {
//                     Get.back();
//                   },
//                   icon: const Icon(Icons.close, color: Colors.white),
//                 ),
//               ),
//               Obx(
//                 () => Padding(
//                   padding: const EdgeInsets.only(top: 15, bottom: 10),
//                   child: Text(
//                     getTitle(),
//                     textAlign: TextAlign.center,
//                     style: const TextStyle(
//                       fontSize: 24,
//                       fontWeight: FontWeight.w500,
//                       color: Colors.white,
//                       height: 1.0,
//                     ),
//                   ),
//                 ),
//               ),
//               Obx(
//                 () => Text(
//                   getDesc(),
//                   textAlign: TextAlign.center,
//                   style: const TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.w400,
//                     color: Colors.white70,
//                   ),
//                 ),
//               ),
//               Obx(
//                 () => controller.recordingDuration.value == 270 &&
//                         controller.recordingState.value == VspRecordingState.started
//                     ? const Padding(
//                         padding: EdgeInsets.only(top: 8.0),
//                         child: Text(
//                           'Finalize your message',
//                           style: TextStyle(fontSize: 12, color: Colors.white70),
//                         ),
//                       )
//                     : const SizedBox(),
//               ),
//               Obx(
//                 () => Expanded(
//                   child: controller.recordingState.value == VspRecordingState.started
//                       ? const SizedBox()
//                       : Center(
//                           child: Image.asset(
//                             'assets/images/logo.png',
//                             width: 160,
//                             fit: BoxFit.contain,
//                           ),
//                         ),
//                 ),
//               ),
//               Obx(
//                 () => controller.recordingState.value == VspRecordingState.ended
//                     ? GestureDetector(
//                         onTap: () {
//                           controller.onPressMicBtn();
//                         },
//                         child: const Text(
//                           'Record again',
//                           style: TextStyle(
//                             fontSize: 14,
//                             fontWeight: FontWeight.w500,
//                             color: Colors.white70,
//                             decoration: TextDecoration.underline,
//                             decorationColor: Colors.white70,
//                           ),
//                         ),
//                       )
//                     : const SizedBox(),
//               ),
//               bottomBtn(),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget bottomBtn() {
//     return Obx(
//       () => Align(
//         alignment: Alignment.bottomCenter,
//         child: Padding(
//           padding: const EdgeInsets.only(bottom: 15, top: 30),
//           child: controller.recordingState.value == VspRecordingState.ended
//               ? Row(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Obx(
//                       () => customFloatingBtn(
//                         onPressed: () {
//                           controller.playTheAudio();
//                         },
//                         icon: controller.isPlaying.value ? Icons.stop : Icons.play_arrow,
//                       ),
//                     ),
//                     const SizedBox(width: 35),
//                     customFloatingBtn(
//                       onPressed: () {
//                         controller.saveTheFile();
//                       },
//                       icon: Icons.check,
//                     ),
//                   ],
//                 )
//               : customFloatingBtn(
//                   onPressed: () {
//                     controller.onPressMicBtn();
//                   },
//                   icon: getMicIcon(),
//                 ),
//         ),
//       ),
//     );
//   }
//
//   Widget customFloatingBtn({
//     required void Function()? onPressed,
//     required IconData icon,
//   }) {
//     return SizedBox(
//       height: 50,
//       width: 50,
//       child: FloatingActionButton(
//         heroTag: null,
//         backgroundColor: const Color(0xFF00D084),
//         onPressed: onPressed,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(14),
//         ),
//         child: Icon(icon, color: const Color(0xFF01004E)),
//       ),
//     );
//   }
//
//   String getTitle() {
//     switch (controller.recordingState.value) {
//       case VspRecordingState.notStarted:
//         return 'Leave a message for tomorrow';
//       case VspRecordingState.started:
//         return 'Speak now';
//       case VspRecordingState.ended:
//         return 'Listen and confirm';
//     }
//   }
//
//   String getDesc() {
//     switch (controller.recordingState.value) {
//       case VspRecordingState.notStarted:
//         return 'Tap the mic to record your voice message.';
//       case VspRecordingState.started:
//         return controller.time.value;
//       case VspRecordingState.ended:
//         return controller.lastTime.value;
//     }
//   }
//
//   IconData getMicIcon() {
//     switch (controller.recordingState.value) {
//       case VspRecordingState.notStarted:
//         return Icons.mic;
//       default:
//         return Icons.stop;
//     }
//   }
// }
