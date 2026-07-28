// =========================================================================
// As decisões puras da ingestão — sem rede, sem Deno, sem Supabase.
//
// Vive aqui porque este é o código que **erra em silêncio**: direção de
// lançamento e chave de dedup não estouram, viram dinheiro errado no extrato de
// alguém. Duas vezes em 2026-07-28 uma regra de direção foi trocada sem teste
// nenhum, e as duas vezes o erro foi descoberto conferindo fatura à mão.
//
// Nada aqui importa `pluggy.ts` de propósito: as assinaturas são de primitivos,
// então o arquivo roda tanto no Deno da Edge Function quanto no `node --test`
// que exercita a tabela-verdade (ver `ingest.test.ts`).
// =========================================================================

/// Direção do lançamento na nossa tabela.
///
/// `transfer` existe porque pagar a fatura do cartão **não é receita**: é
/// dinheiro trocando de bolso. Ele não entra em `inflow` nem em `outflow` do
/// `MonthSummary`, que é exatamente o comportamento desejado — o gasto já foi
/// contado quando a compra entrou.
export type Direction = 'expense' | 'income' | 'transfer';

/// Se a convenção de sinal desta conta é a de cartão (invertida).
export function isCreditCard(accountType: string): boolean {
  return accountType === 'credit_card';
}

/**
 * Direção a partir do **sinal**, interpretado pelo tipo de conta.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * A CONVENÇÃO, MEDIDA EM DOIS CONECTORES (2026-07-28)
 *
 * | Conector | Conta    | Compra chega como | Crédito chega como        |
 * |----------|----------|-------------------|---------------------------|
 * | sandbox  | corrente | `DEBIT -100`      | `CREDIT +x`               |
 * | sandbox  | cartão   | `CREDIT -89,90`   | (não houve)               |
 * | Nubank   | corrente | `DEBIT -200`      | `CREDIT +399,30`          |
 * | Nubank   | cartão   | `DEBIT +55,99`    | `CREDIT -10.139,02`       |
 *
 * Três das quatro linhas concordam com a doc oficial, que diz do `amount`:
 * *"For credit cards, it will be positive (debit) when its an expense (adds to
 * the balance), while it will be negative (credit) when the person pays the
 * bill."* A exceção é o **cartão do sandbox**, que inverte os dois campos ao
 * mesmo tempo — é fixture defeituosa, não convenção alternativa.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * POR QUE A REGRA É ESTA, E NÃO "O SINAL MANDA"
 *
 * A tentativa anterior tirou a regra só do sandbox e concluiu que negativo é
 * sempre saída. Contra conta real isso gravou **305 compras de cartão como
 * receita**: no cartão do Nubank compra é positiva. Uma medição em um conector
 * só não é uma convenção — é uma amostra de tamanho um.
 *
 * O que o sandbox custa: a compra dele (`CREDIT` negativo) tem exatamente a
 * assinatura de um pagamento de fatura, então cai em `transfer`. Nenhuma regra
 * derivada da doc acerta esse caso, e nenhum cruzamento o detecta — os dois
 * campos mentem juntos. É dado falso; conta real é o que precisa estar certo.
 *
 * `amount` ausente ou zero não chega aqui: `toMinor` recusa antes (a coluna é
 * positiva por constraint). O `>= 0` cobre o caso por totalidade, não por
 * expectativa.
 */
export function resolveDirection(
  amount: number | undefined,
  accountType: string,
): Direction {
  const positive = typeof amount !== 'number' || amount >= 0;

  if (isCreditCard(accountType)) {
    // Cartão: positivo aumenta a fatura (gasto); negativo a abate (pagamento).
    return positive ? 'expense' : 'transfer';
  }
  return positive ? 'income' : 'expense';
}

/**
 * Direção a partir do `type` declarado — usada só para **cruzar** com o sinal.
 *
 * `DEBIT` é saída e `CREDIT` é entrada pela doc; num cartão a "entrada" é o
 * abatimento da fatura, que é `transfer` pelo mesmo motivo de [resolveDirection].
 *
 * Devolve `null` quando a Pluggy não mandou `type`, para "não deu para cruzar"
 * não se confundir com "cruzou e concordou".
 */
export function directionByType(
  type: string | undefined,
  accountType: string,
): Direction | null {
  if (type !== 'DEBIT' && type !== 'CREDIT') return null;
  if (type === 'DEBIT') return 'expense';
  return isCreditCard(accountType) ? 'transfer' : 'income';
}

/// Uma linha da Pluggy reduzida ao que a dedup precisa.
export interface Keyed<T> {
  readonly externalId: string;
  readonly value: T;
}

/// O que a dedup de lote encontrou.
export interface DedupeResult<T> {
  /// Uma entrada por `external_id`, na ordem de chegada.
  readonly unique: Keyed<T>[];
  /// Quantas entradas foram descartadas por repetir um `external_id` da
  /// **mesma página**.
  readonly collided: number;
}

/**
 * Colapsa `external_id` repetido dentro do lote, mantendo o primeiro.
 *
 * Existe porque um `INSERT` de várias linhas é **atômico**: uma única colisão
 * com a `unique (account_id, external_id)` derruba as outras 499 da página. Foi
 * o que aconteceu na primeira ingestão real — três páginas de um cartão
 * desapareceram inteiras e o evento foi marcado como processado com sucesso,
 * porque o código tratava `23505` como benigno e não conferia quantas linhas
 * entraram.
 *
 * A contagem `collided` é o que diz se a chave de dedup escolhida pelo ADR 0005
 * (`providerId` quando existe) é única de verdade por transação. Se ela subir,
 * a chave está colapsando lançamentos distintos — parcela de compra é o
 * suspeito — e aí o remédio é a chave, não o insert.
 */
/**
 * Fatia uma lista em pedaços de no máximo [size].
 *
 * Existe porque o INSERT de uma página não pode ser um lote só: ele é atômico,
 * e uma colisão de `external_id` derrubaria as outras 499. Em pedaços, o estrago
 * de uma colisão fica no pedaço — e o pedaço que falhar é reinserido linha por
 * linha, que é o que permite **contar** as colisões em vez de perder a página.
 *
 * `ON CONFLICT DO NOTHING` resolveria isso em uma ida, e não serve aqui: a
 * `unique (account_id, external_id)` é **parcial** (`where external_id is not
 * null`), e o Postgres não infere índice parcial sem repetir o predicado no
 * `ON CONFLICT` — coisa que o PostgREST não expressa. Medido na nuvem:
 * *"there is no unique or exclusion constraint matching the ON CONFLICT
 * specification"*.
 */
export function chunk<T>(items: T[], size: number): T[][] {
  if (size < 1) throw new RangeError('size precisa ser >= 1');
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

export function dedupeByExternalId<T>(entries: Keyed<T>[]): DedupeResult<T> {
  const seen = new Set<string>();
  const unique: Keyed<T>[] = [];
  let collided = 0;

  for (const entry of entries) {
    if (seen.has(entry.externalId)) {
      collided += 1;
      continue;
    }
    seen.add(entry.externalId);
    unique.push(entry);
  }

  return { unique, collided };
}
