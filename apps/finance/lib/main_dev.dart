import 'package:core/core.dart';

import 'bootstrap.dart';

/// Entrypoint do flavor `dev`.
/// Rode: flutter run --dart-define-from-file=env/dev.json -t lib/main_dev.dart
Future<void> main() => bootstrap(AppEnv.fromEnvironment());
