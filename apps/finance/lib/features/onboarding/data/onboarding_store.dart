import 'package:core/core.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../domain/onboarding_preferences.dart';

/// Statements das preferências locais, em constantes para o teste de guarda
/// rodá-las contra uma view igual à que o PowerSync cria.
///
/// **Por que não há UPSERT aqui.** Tabela do PowerSync — inclusive a
/// `localOnly` — é uma view com triggers `INSTEAD OF`, e o SQLite recusa com
/// `cannot UPSERT a view`. Foi esse o bug do orçamento; aqui a gravação é
/// delete-then-insert, que uma view aceita.
abstract final class AppPrefsSql {
  static const select = 'SELECT value FROM app_prefs WHERE id = ?';
  static const delete = 'DELETE FROM app_prefs WHERE id = ?';
  static const insert = 'INSERT INTO app_prefs (id, value) VALUES (?, ?)';
}

/// Guarda se a apresentação inicial já foi vista, **neste aparelho**.
///
/// Fica no banco local (tabela `localOnly`) e não no servidor: a apresentação
/// ensina a interface, e a interface é deste aparelho. Levar isso para
/// `profiles` exigiria migration, coluna no schema do PowerSync e republicação
/// das sync rules — custo alto para uma flag booleana.
class OnboardingStore implements OnboardingPreferences {
  OnboardingStore({required this.db, AppLogger? logger})
    : _log = logger ?? AppLogger('OnboardingStore');

  static const _key = 'onboarding_seen';

  final SqliteConnection db;
  final AppLogger _log;

  /// Se a apresentação já foi concluída ou pulada.
  ///
  /// Em caso de erro devolve `false`: mostrar a apresentação de novo é bem
  /// menos grave que travar o boot por causa de uma preferência.
  @override
  Future<bool> hasSeen() async {
    try {
      final row = await db.getOptional(AppPrefsSql.select, [_key]);
      return row?['value'] == '1';
    } on Exception catch (e, st) {
      _log.severe('Falha ao ler a preferência de onboarding', e, st);
      return false;
    }
  }

  /// Marca como vista. Idempotente.
  @override
  Future<Result<void, Failure>> markSeen() async {
    try {
      await db.execute(AppPrefsSql.delete, [_key]);
      await db.execute(AppPrefsSql.insert, [_key, '1']);
      return const Ok(null);
    } on Exception catch (e, st) {
      _log.severe('Falha ao gravar a preferência de onboarding', e, st);
      return Err(
        DatabaseFailure('Não foi possível salvar sua preferência.', cause: e),
      );
    }
  }
}
