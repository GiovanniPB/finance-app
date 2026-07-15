import 'package:powersync/powersync.dart';

/// Schema do banco SQLite local gerenciado pelo PowerSync.
///
/// Espelha as tabelas sincronizáveis do Postgres (ver `supabase/migrations`).
/// A coluna `id` (text, PK) é implícita no PowerSync e NÃO deve ser declarada.
/// Datas são armazenadas como texto ISO-8601 (o PowerSync não tem tipo date).
const appSchema = Schema([
  Table('profiles', [
    Column.text('display_name'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
  Table(
    'accounts',
    [
      Column.text('owner_id'),
      Column.text('name'),
      Column.text('currency'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('owner', [IndexedColumn('owner_id')]),
    ],
  ),
]);
