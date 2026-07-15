import 'package:core/core.dart';

import 'bootstrap.dart';

/// Entrypoint do flavor `staging`.
/// Rode: flutter run --dart-define-from-file=env/staging.json -t lib/main_staging.dart
Future<void> main() => bootstrap(AppEnv.fromEnvironment());
