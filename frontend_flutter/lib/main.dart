import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app/app.dart';

List<CameraDescription> gCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(); // ✅ no firebase_options.dart needed

  gCameras = await availableCameras();
  runApp(const DPPAApp());
}