import 'package:core/core.dart';

import 'bootstrap.dart';

/// Entrypoint do flavor `prod`.
/// Rode: flutter run --dart-define-from-file=env/prod.json -t lib/main_prod.dart
Future<void> main() => bootstrap(AppEnv.fromEnvironment());
