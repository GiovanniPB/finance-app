// =========================================================================
// Tabela-verdade da direção, escrita a partir de dado **medido** — não da doc.
//
// Cada caso abaixo é uma linha que chegou de verdade em 2026-07-28, copiada da
// instrumentação gravada em `webhook_events.payload._convencao`. A doc oficial
// da Pluggy já se contradisse com o sandbox uma vez; o que este arquivo protege
// é o que os dois conectores realmente mandaram.
//
// Roda sem Deno e sem rede:
//
//   node --test supabase/functions/_shared/
// =========================================================================

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  chunk,
  dedupeByExternalId,
  directionByType,
  resolveDirection,
} from './ingest.ts';

describe('resolveDirection — conta corrente', () => {
  it('negativo é despesa (sandbox: DEBIT -100 "Pagamento de boleto")', () => {
    assert.equal(resolveDirection(-100, 'checking'), 'expense');
  });

  it('negativo é despesa (Nubank: DEBIT -200 "Transferência enviada")', () => {
    assert.equal(resolveDirection(-200, 'checking'), 'expense');
  });

  it('positivo é receita (Nubank: CREDIT +399,30 "Resgate de Cashback")', () => {
    assert.equal(resolveDirection(399.3, 'checking'), 'income');
  });

  it('poupança segue a mesma convenção da corrente', () => {
    assert.equal(resolveDirection(-50, 'savings'), 'expense');
    assert.equal(resolveDirection(50, 'savings'), 'income');
  });

  it('conta sem subtipo conhecido também', () => {
    assert.equal(resolveDirection(-50, 'other'), 'expense');
  });
});

describe('resolveDirection — cartão de crédito', () => {
  it('positivo é despesa (Nubank: DEBIT +55,99 "Loja Under Armour")', () => {
    assert.equal(resolveDirection(55.99, 'credit_card'), 'expense');
  });

  it('negativo é transferência (Nubank: CREDIT -10.139,02 "Pagamento '
    + 'recebido") — abater fatura não é receita', () => {
    assert.equal(resolveDirection(-10139.02, 'credit_card'), 'transfer');
  });

  it('a mesma compra numa conta corrente teria a direção oposta — é o tipo '
    + 'de conta que decide, não o sinal sozinho', () => {
    assert.equal(resolveDirection(55.99, 'credit_card'), 'expense');
    assert.equal(resolveDirection(55.99, 'checking'), 'income');
  });

  it('o cartão do sandbox é fixture defeituosa, e o resultado errado está '
    + 'documentado: CREDIT -89,90 é compra lá, e cai em transfer', () => {
    // Nenhuma regra derivada da doc acerta este caso, e o cruzamento com `type`
    // não o detecta — os dois campos mentem juntos. Está aqui para a próxima
    // pessoa não "consertar" isto e quebrar conta real de novo.
    assert.equal(resolveDirection(-89.9, 'credit_card'), 'transfer');
    assert.equal(directionByType('CREDIT', 'credit_card'), 'transfer');
  });
});

describe('resolveDirection — totalidade', () => {
  it('valor ausente não estoura (não chega aqui: toMinor recusa antes)', () => {
    assert.equal(resolveDirection(undefined, 'checking'), 'income');
    assert.equal(resolveDirection(undefined, 'credit_card'), 'expense');
  });

  it('zero cai no ramo positivo', () => {
    assert.equal(resolveDirection(0, 'checking'), 'income');
  });
});

describe('directionByType — o cruzamento', () => {
  it('concorda com o sinal em tudo que chegou de conta real', () => {
    const real = [
      { amount: -100, type: 'DEBIT', accountType: 'checking' },
      { amount: -200, type: 'DEBIT', accountType: 'checking' },
      { amount: 399.3, type: 'CREDIT', accountType: 'checking' },
      { amount: 55.99, type: 'DEBIT', accountType: 'credit_card' },
      { amount: -10139.02, type: 'CREDIT', accountType: 'credit_card' },
    ];

    for (const row of real) {
      assert.equal(
        resolveDirection(row.amount, row.accountType),
        directionByType(row.type, row.accountType),
        `sinal e type discordam em ${row.type} ${row.amount} `
          + `(${row.accountType})`,
      );
    }
  });

  it('devolve null sem type, para não confundir com concordância', () => {
    assert.equal(directionByType(undefined, 'checking'), null);
    assert.equal(directionByType('OTHER', 'checking'), null);
  });
});

describe('dedupeByExternalId', () => {
  it('mantém a primeira ocorrência e conta as colisões', () => {
    const result = dedupeByExternalId([
      { externalId: 'a', value: 1 },
      { externalId: 'b', value: 2 },
      { externalId: 'a', value: 3 },
      { externalId: 'a', value: 4 },
    ]);

    assert.equal(result.collided, 2);
    assert.deepEqual(result.unique.map((entry) => entry.value), [1, 2]);
  });

  it('lote sem repetição passa inteiro', () => {
    const result = dedupeByExternalId([
      { externalId: 'a', value: 1 },
      { externalId: 'b', value: 2 },
    ]);

    assert.equal(result.collided, 0);
    assert.equal(result.unique.length, 2);
  });

  it('lote vazio não estoura', () => {
    const result = dedupeByExternalId<number>([]);

    assert.equal(result.collided, 0);
    assert.equal(result.unique.length, 0);
  });
});

describe('chunk', () => {
  it('divide em pedaços do tamanho pedido, com resto no último', () => {
    assert.deepEqual(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  });

  it('lista menor que o pedaço vira um pedaço só', () => {
    assert.deepEqual(chunk([1, 2], 100), [[1, 2]]);
  });

  it('lista vazia vira nenhum pedaço', () => {
    assert.deepEqual(chunk([], 10), []);
  });

  it('tamanho exato não deixa pedaço vazio no fim', () => {
    assert.deepEqual(chunk([1, 2, 3, 4], 2), [[1, 2], [3, 4]]);
  });

  it('recusa tamanho inválido em vez de laçar para sempre', () => {
    assert.throws(() => chunk([1], 0), RangeError);
  });
});
