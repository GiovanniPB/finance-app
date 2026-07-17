import 'package:powersync/powersync.dart';

/// Schema do banco SQLite local gerenciado pelo PowerSync.
///
/// Espelha as tabelas sincronizáveis do Postgres (ver `supabase/migrations`).
/// A coluna `id` (text, PK) é implícita no PowerSync e NÃO deve ser declarada.
/// Datas são armazenadas como texto ISO-8601 (o PowerSync não tem tipo date).
/// Dinheiro é sempre inteiro em unidades mínimas (ADR 0006) — `Column.integer`.
const appSchema = Schema([
  Table('profiles', [
    Column.text('display_name'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
  // Espaço (personal | household | group). Ver ADR 0004.
  Table('spaces', [
    Column.text('space_type'),
    Column.text('name'),
    Column.text('owner_id'),
    Column.text('privacy_policy'),
    Column.text('status'),
    Column.text('settlement_currency'),
    Column.text('archived_at'),
    Column.text('created_at'),
    Column.text('updated_at'),
  ]),
  // Pertencimento de um usuário a um espaço, com papel.
  Table(
    'space_members',
    [
      Column.text('space_id'),
      Column.text('user_id'),
      Column.text('role'),
      Column.text('share_percentage'),
      Column.text('status'),
      Column.text('joined_at'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('space', [IndexedColumn('space_id')]),
      Index('user', [IndexedColumn('user_id')]),
    ],
  ),
  Table(
    'accounts',
    [
      Column.text('owner_id'),
      Column.text('linked_space_id'),
      Column.text('name'),
      Column.text('currency'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('owner', [IndexedColumn('owner_id')]),
      Index('linked_space', [IndexedColumn('linked_space_id')]),
    ],
  ),
]);
