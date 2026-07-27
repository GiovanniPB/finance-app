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
  // Conta financeira. Pertence ao dono; `linked_space_id` a torna visível para
  // os membros de um household (ADR 0004). `current_balance_minor` é sempre
  // positivo — a direção vem de `account_type`, como em `transactions` vem de
  // `type` (ver o cabeçalho da migration 20260727210000).
  Table(
    'accounts',
    [
      Column.text('owner_id'),
      Column.text('linked_space_id'),
      Column.text('name'),
      Column.text('account_type'),
      Column.text('institution'),
      Column.text('currency'),
      Column.integer('current_balance_minor'),
      // Desde quando o saldo é verdade. Só se move quando o valor muda, nunca
      // numa renomeação — por isso não é o `updated_at`.
      Column.text('balance_as_of'),
      Column.integer('is_savings_target'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('owner', [IndexedColumn('owner_id')]),
      Index('linked_space', [IndexedColumn('linked_space_id')]),
    ],
  ),
  // Categoria. `space_id` nulo = categoria de sistema (global, RN-1.2).
  // `color_index` é índice na paleta do design system, não um hex.
  Table(
    'categories',
    [
      Column.text('space_id'),
      Column.text('name'),
      Column.text('icon_key'),
      Column.integer('color_index'),
      Column.integer('is_system'),
      Column.text('parent_category_id'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('space', [IndexedColumn('space_id')]),
    ],
  ),
  // Transação. `amount_minor` é sempre positivo; a direção vem de `type`
  // (ver o cabeçalho da migration 20260727151151).
  Table(
    'transactions',
    [
      Column.text('space_id'),
      Column.text('account_id'),
      Column.text('created_by'),
      Column.text('type'),
      Column.integer('amount_minor'),
      Column.text('currency'),
      Column.text('category_id'),
      Column.text('description'),
      Column.text('occurred_at'),
      Column.text('source'),
      Column.integer('is_shared'),
      Column.integer('ai_categorized'),
      Column.text('recurrence_id'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      // Espelha o índice do Postgres: a query da lista é por espaço e data.
      Index('space_occurred', [
        IndexedColumn('space_id'),
        IndexedColumn.descending('occurred_at'),
      ]),
      Index('category', [IndexedColumn('category_id')]),
    ],
  ),
  // Orçamento por categoria e período (RN-1.3).
  Table(
    'budgets',
    [
      Column.text('space_id'),
      Column.text('category_id'),
      Column.integer('amount_minor'),
      Column.text('currency'),
      Column.text('period'),
      Column.text('starts_at'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('space', [IndexedColumn('space_id')]),
    ],
  ),
  // Preferências locais do app. **Não sincroniza** (`localOnly`): são escolhas
  // deste dispositivo, não dado do usuário — e nada aqui deve subir para o
  // Postgres. O `id` é a chave (ex.: `onboarding_seen`) e o valor vai em
  // `value`.
  //
  // Consequência conhecida: `disconnectAndClear()` no logout apaga isto junto.
  // Para uma flag de onboarding é aceitável — outra conta no mesmo aparelho vê
  // a apresentação de novo.
  Table.localOnly('app_prefs', [Column.text('value')]),
]);
