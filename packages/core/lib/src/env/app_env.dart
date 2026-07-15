import 'package:meta/meta.dart';

/// Flavor de build da aplicação.
enum AppFlavor {
  dev,
  staging,
  prod;

  static AppFlavor fromName(String value) => switch (value.toLowerCase()) {
    'dev' || 'development' => AppFlavor.dev,
    'staging' || 'stg' => AppFlavor.staging,
    'prod' || 'production' => AppFlavor.prod,
    _ => throw ArgumentError.value(value, 'FLAVOR', 'Flavor inválido'),
  };

  bool get isProd => this == AppFlavor.prod;
}

/// Configuração de ambiente resolvida em tempo de compilação via
/// `--dart-define` / `--dart-define-from-file`.
///
/// Não contém segredos reais: URL e chave anônima do Supabase são públicas por
/// design (a segurança vem do RLS no Postgres). A service-role key NUNCA deve
/// aparecer no cliente.
@immutable
class AppEnv {
  const AppEnv({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.powersyncUrl,
  });

  /// Constrói a partir dos valores injetados no build (compile-time).
  factory AppEnv.fromEnvironment() => AppEnv.parse(const {
    _flavorKey: String.fromEnvironment(_flavorKey, defaultValue: 'dev'),
    _supabaseUrlKey: String.fromEnvironment(_supabaseUrlKey),
    _supabaseAnonKeyKey: String.fromEnvironment(_supabaseAnonKeyKey),
    _powersyncUrlKey: String.fromEnvironment(_powersyncUrlKey),
  });

  /// Constrói e valida a partir de um mapa (testável).
  ///
  /// Lança [ArgumentError] listando todas as chaves ausentes — falha rápida
  /// no boot, em vez de erros obscuros mais adiante.
  factory AppEnv.parse(Map<String, String> values) {
    final missing = <String>[
      for (final key in _requiredKeys)
        if ((values[key] ?? '').trim().isEmpty) key,
    ];
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'Configuração de ambiente ausente: ${missing.join(', ')}. '
        'Forneça via --dart-define-from-file=env/<flavor>.json',
      );
    }

    return AppEnv(
      flavor: AppFlavor.fromName(values[_flavorKey] ?? 'dev'),
      supabaseUrl: values[_supabaseUrlKey]!.trim(),
      supabaseAnonKey: values[_supabaseAnonKeyKey]!.trim(),
      powersyncUrl: values[_powersyncUrlKey]!.trim(),
    );
  }

  static const _flavorKey = 'FLAVOR';
  static const _supabaseUrlKey = 'SUPABASE_URL';
  static const _supabaseAnonKeyKey = 'SUPABASE_ANON_KEY';
  static const _powersyncUrlKey = 'POWERSYNC_URL';

  static const _requiredKeys = <String>[
    _supabaseUrlKey,
    _supabaseAnonKeyKey,
    _powersyncUrlKey,
  ];

  final AppFlavor flavor;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String powersyncUrl;

  @override
  String toString() =>
      'AppEnv(flavor: ${flavor.name}, supabaseUrl: $supabaseUrl, '
      'powersyncUrl: $powersyncUrl, supabaseAnonKey: <redacted>)';
}
