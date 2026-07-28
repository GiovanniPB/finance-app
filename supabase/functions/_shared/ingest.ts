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

// -------------------------------------------------------------------------
// Detecção de poupança (RN-3.2, caminho 2)
// -------------------------------------------------------------------------

/// Uma meta ativa que aponta para a conta que recebeu o dinheiro.
///
/// A moeda vem junto porque é critério de decisão, não detalhe de escrita:
/// `GoalProgress` **descarta em silêncio** aporte em moeda diferente da meta, e
/// propor uma contribuição que o progresso vai ignorar seria oferecer um sim que
/// não muda nada.
export interface LinkedGoal {
  readonly id: string;
  readonly currency: string;
}

/// O que a detecção decidiu sobre uma linha importada.
///
/// Os motivos de recusa são nomeados um a um, e não colapsados num `false`,
/// porque cada um é gravado no `payload` do evento: "não propôs" e "propôs
/// errado" precisam ser distinguíveis por SQL, que é a lição do item 4 do
/// cabeçalho do worker.
export type SavingsVerdict =
  /// Propor contribuição pendente.
  | 'aporte'
  /// Dinheiro não entrou nesta conta (saída, ou abatimento de fatura).
  | 'naoEhEntrada'
  /// A conta não está marcada como alvo de poupança.
  | 'contaNaoEhAlvo'
  /// Conta alvo, e nenhuma meta ativa do espaço aponta para ela.
  | 'semMeta'
  /// Mais de uma meta ativa disputa a conta — a detecção se recusa a escolher.
  | 'metaAmbigua'
  /// A única meta candidata está em outra moeda.
  | 'moedaDivergente';

export interface SavingsDetection {
  readonly verdict: SavingsVerdict;
  /// Preenchido só quando [verdict] é `aporte`.
  readonly goalId: string | null;
}

/**
 * Decide se uma linha importada deve virar contribuição **pendente**.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * O SINAL É UNILATERAL, DE PROPÓSITO
 *
 * A RN-3.2 fala em "transferência para conta marcada como `is_savings_target`".
 * Uma transferência entre contas próprias chega em **duas** linhas — a saída na
 * corrente e a entrada na poupança — e casar as duas exigiria heurística de
 * valor-e-data que a questão #5 do PRD deixa em aberto.
 *
 * Aqui só a **entrada na conta alvo** é considerada. Ela basta: é a linha que
 * diz que o dinheiro chegou onde a meta guarda, e não depende de a conta de
 * origem estar conectada. Custo aceito: se só a corrente estiver conectada, a
 * transferência não é detectada — não há linha na conta alvo para detectar.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * POR QUE A REGRA PODE SER GENEROSA
 *
 * Rendimento da poupança também chega como entrada, e vira proposta. Isso é
 * **intencional**: a contribuição nasce `confirmed=false`, e é o sim do usuário
 * que a faz contar (RN-3.3). O falso-positivo que a questão #5 teme custa um
 * toque em "não", não dinheiro errado no progresso — o que dispensa acertar a
 * heurística antes de ter dado real para calibrá-la.
 *
 * O que a regra **não** pode fazer é escolher entre metas. Confirmar move o
 * valor para a meta que a detecção apontou, e a UI não oferece trocá-la: com
 * duas metas ativas na mesma conta, propor seria adivinhar em nome do usuário.
 * Daí `metaAmbigua` recusar em vez de desempatar.
 *
 * Cartão de crédito nunca chega aqui como entrada: `resolveDirection` devolve
 * `transfer` para o abatimento de fatura, nunca `income`. A checagem de
 * [accountIsSavingsTarget] cobre o resto por totalidade.
 */
export function detectSavingsContribution(args: {
  readonly direction: Direction;
  readonly accountIsSavingsTarget: boolean;
  readonly currency: string;
  readonly goals: readonly LinkedGoal[];
}): SavingsDetection {
  const { direction, accountIsSavingsTarget, currency, goals } = args;

  if (!accountIsSavingsTarget) {
    return { verdict: 'contaNaoEhAlvo', goalId: null };
  }
  if (direction !== 'income') {
    return { verdict: 'naoEhEntrada', goalId: null };
  }
  if (goals.length === 0) return { verdict: 'semMeta', goalId: null };
  if (goals.length > 1) return { verdict: 'metaAmbigua', goalId: null };

  const goal = goals[0];
  if (goal.currency !== currency) {
    return { verdict: 'moedaDivergente', goalId: null };
  }

  return { verdict: 'aporte', goalId: goal.id };
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
