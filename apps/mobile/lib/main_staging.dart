import 'package:syncgate/bootstrap.dart';
import 'package:syncgate/src/app/app_config.dart';

Future<void> main() => bootstrap(AppConfig.resolve(Flavour.staging));
