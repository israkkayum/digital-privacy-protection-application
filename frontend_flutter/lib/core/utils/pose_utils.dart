import 'package:camera/camera.dart';

class PoseAngles {
  final double yaw;
  final double pitch;

  const PoseAngles({required this.yaw, required this.pitch});
}

PoseAngles normalizeAngles({
  required double yaw,
  required double pitch,
  required CameraLensDirection lens,
}) {
  if (lens == CameraLensDirection.front) {
    return PoseAngles(yaw: -yaw, pitch: -pitch);
  }
  return PoseAngles(yaw: yaw, pitch: pitch);
}
