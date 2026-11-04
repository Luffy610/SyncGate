/// Camera and face pipeline. The UI only ever sees a texture ID and small
/// events (ADR-0002); images and face vectors stay inside this package.
library;

export 'src/enrolment.dart';
export 'src/gate_vision_service.dart';
export 'src/pipeline/enrolment_engine.dart';
export 'src/pipeline/face_detector.dart';
export 'src/pipeline/face_embedder.dart';
export 'src/pipeline/face_pipeline.dart';
export 'src/pipeline/gate_engine.dart';
export 'src/pipeline/geometry.dart';
export 'src/pipeline/matcher.dart';
export 'src/pipeline/model_manifest.dart';
export 'src/pipeline/quality.dart';
export 'src/pipeline/rgb_image.dart';
export 'src/pipeline/templates.dart';
export 'src/pipeline/tensor_model.dart';
export 'src/runtime/camera_source.dart';
export 'src/runtime/frames.dart';
export 'src/runtime/model_assets.dart';
export 'src/runtime/scripted_source.dart';
export 'src/runtime/services.dart';
export 'src/runtime/vision_runner.dart';
export 'src/vision_event.dart';
