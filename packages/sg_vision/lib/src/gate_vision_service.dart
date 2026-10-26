import 'package:sg_vision/src/vision_event.dart';

/// Settings for one gate session.
final class GateVisionConfig {
  const new({this.useScreenFillLight = false});

  /// Light faces with a white screen when the gate is dark (design 07).
  final bool useScreenFillLight;
}

/// Runs the camera and face pipeline while the app is in Gate mode.
abstract interface class GateVisionService {
  /// Starts the camera and pipeline. Returns the texture ID for a
  /// `Texture` widget showing the preview.
  Future<int> start(GateVisionConfig config);

  /// Stops the camera. Called when leaving Gate mode (ADR-0004).
  Future<void> stop();

  /// Pipeline events while running.
  Stream<VisionEvent> get events;
}
