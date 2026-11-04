import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:sg_vision/src/pipeline/rgb_image.dart';
import 'package:sg_vision/src/runtime/frames.dart';

/// The front camera through `package:camera`, streaming YUV (Android) or
/// BGRA (iOS) frames at 640×480-class resolution and 15 fps (ADR-0006).
///
/// Frames are copied out of the plugin's buffers once, handed to the
/// pipeline and wiped after analysis. Nothing is written to disk.
final class CameraFrameSource implements FrameSource {
  new({
    this.resolution = ResolutionPreset.medium,
    this.fps = 15,
    this.rotationOverride,
  });

  final ResolutionPreset resolution;
  final int fps;

  /// Forces the frame rotation (degrees clockwise) if a device reports its
  /// sensor orientation wrongly.
  final int? rotationOverride;

  final _frames = StreamController<RawFrame>.broadcast();
  CameraController? _controller;

  /// The running controller, for [VisionPreview].
  static final ValueNotifier<CameraController?> active = ValueNotifier(null);

  @override
  Stream<RawFrame> get frames => _frames.stream;

  @override
  Future<int> start() async {
    await stop();
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('no camera');
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      front,
      resolution,
      enableAudio: false,
      fps: fps,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    final rotation = FrameRotation.fromDegrees(
      rotationOverride ?? front.sensorOrientation,
    );
    await controller.startImageStream((img) => _onImage(img, rotation));
    _controller = controller;
    active.value = controller;
    return controller.cameraId;
  }

  void _onImage(CameraImage img, FrameRotation rotation) {
    if (_frames.isClosed || !_frames.hasListener) return;
    final at = DateTime.now();
    final frame = switch (img.format.group) {
      ImageFormatGroup.bgra8888 => Bgra8888Frame(
        at: at,
        bytes: Uint8List.fromList(img.planes[0].bytes),
        width: img.width,
        height: img.height,
        rowStride: img.planes[0].bytesPerRow,
        rotation: rotation,
      ),
      ImageFormatGroup.nv21 => Nv21Frame(
        at: at,
        bytes: Uint8List.fromList(img.planes[0].bytes),
        width: img.width,
        height: img.height,
        rowStride: img.planes[0].bytesPerRow,
        rotation: rotation,
      ),
      _ when img.planes.length == 3 => Yuv420Frame(
        at: at,
        width: img.width,
        height: img.height,
        y: Uint8List.fromList(img.planes[0].bytes),
        yRowStride: img.planes[0].bytesPerRow,
        u: Uint8List.fromList(img.planes[1].bytes),
        v: Uint8List.fromList(img.planes[2].bytes),
        uvRowStride: img.planes[1].bytesPerRow,
        uvPixelStride: img.planes[1].bytesPerPixel ?? 1,
        rotation: rotation,
      ),
      _ => null,
    };
    if (frame != null) _frames.add(frame);
  }

  @override
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    if (active.value == c) active.value = null;
    if (c == null) return;
    if (c.value.isStreamingImages) await c.stopImageStream();
    await c.dispose();
  }
}

/// The live camera preview for a texture ID returned by a vision service.
/// Uses the plugin's own preview (which handles rotation and mirroring) when
/// the camera is ours, else a plain [Texture].
class VisionPreview extends StatelessWidget {
  const new({required this.textureId, super.key});

  final int textureId;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<CameraController?>(
        valueListenable: CameraFrameSource.active,
        builder: (context, controller, _) {
          if (controller != null &&
              controller.cameraId == textureId &&
              controller.value.isInitialized) {
            return FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 480,
                height: controller.value.previewSize?.width ?? 640,
                child: controller.buildPreview(),
              ),
            );
          }
          return Texture(textureId: textureId);
        },
      );
}
