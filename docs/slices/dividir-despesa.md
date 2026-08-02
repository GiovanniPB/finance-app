# Fatia: dividir-despesa

tipo: feature

## Pronto quando

Uma despesa de espaço `group` marcada como dividida passa a ter uma parte igual
por membro ativo, visível ao abrir o lançamento.

## Superfícies

- **Editar lançamento** — `transaction_edit_sheet.dart` ganha a seção
  **"Dividido entre"**: sem divisão, um botão "Dividir igualmente"; com divisão,
  uma linha por membro com o nome e a parte, mais "Desfazer a divisão".
- **Lista do mês** — `transaction_list.dart`: a linha de um lançamento dividido
  ganha "Dividida" no `meta` que ela já compõe. **Zero mudança no design
  system** — `TransactionTile.meta` é uma string montada pelo chamador.

Mockup: `docs/slices/dividir-despesa.mockup.html` — pendente

> O mockup mora no repo, não na conversa. Se ele existe só no histórico da
> sessão, a próxima sessão perde o alvo visual e a fatia recomeça do zero.

## Decisões de desenho

### 1. Marcar a divisão é no sheet de edição, não no `+`

Decidido em 2026-08-01. O `docs/surfaces.md` protege a entrada: *"o fluxo dos 30
segundos… é a única superfície que **não pode ganhar passo** sem revisar a
promessa de entrada."* Registrar segue idêntico; dividir é um segundo gesto, no
lançamento que já existe.

O custo é real e assumido: em república, dividir é o caso comum, e dois gestos é
pior que um. Se doer no uso, a resposta é revisar a promessa de entrada de
propósito — numa fatia própria, com essa discussão explícita — e não deixar um
campo vazar para o `+` sem ninguém decidir.

### 2. Só rateio igual, e só em espaço `group`

Decidido em 2026-08-01. `Money.split(n)` resolve a matemática sem perder centavo
(método do maior resto). Percentual usando `space_members.share_percentage` e
valor exato ficam para fatia própria, porque as duas **exigem tela de
configuração** — e uma tela dessas dentro de um sheet que já avisa no cabeçalho
que "seis campos e um teclado não cabem numa tela pequena" é fatia inteira.

`household` fica fora: ele é transparência total (PRD §4.2), onde o dinheiro é
comum e "quem deve a quem" não é a pergunta. `personal` não tem outro membro.

### 3. `expense_splits.space_id` é denormalizado

Aplicação direta do [ADR 0011](../adr/0011-dado-de-outro-membro-viaja-na-linha.md):
a parte pertence ao lançamento, e o espaço estaria a um join de distância — que
Sync Rules não fazem. A coluna carrega o próprio espaço, como
`savings_contributions.space_id` já faz.

**Tabela nova exige republicar as sync rules à mão.** Esta fatia atravessa a
armadilha nº 1 do repo, ao contrário da anterior. O sintoma de esquecer é tela
vazia sem erro nenhum: a seção mostraria "Dividir igualmente" para um lançamento
que já está dividido.

### 4. Marcar e ratear são uma transação, não duas

`is_shared = 1` e as N linhas de parte sobem juntas num `writeTransaction`. Um
lançamento marcado como dividido sem partes é um estado que a UI leria como
"dividido entre ninguém"; e as partes sem a marca não apareceriam na lista. É o
mesmo argumento que já obriga espaço e membership a nascerem juntos.

O repositório lê `space_members` para saber entre quem ratear, em vez de receber
a lista da apresentação: a atomicidade exige que a leitura aconteça dentro da
mesma transação de escrita.

## Arquivos que mudam

Backend e schema

1. `supabase/migrations/<ts>_dividir_despesa.sql` — **novo**: tabela
   `expense_splits` (PK `id`, `transaction_id`, `space_id`, `user_id`,
   `amount_minor`, `currency`, timestamps, `unique (transaction_id, user_id)`),
   RLS com `private.is_space_member` e `private.has_space_role`, trigger de
   `updated_at`, `replica identity full`, e trigger `before insert or update of
   transaction_id` que herda `space_id` do lançamento.
2. `powersync/sync_rules.yaml` — `expense_splits` em `by_space.data`.
3. `packages/database/lib/src/schema.dart` — tabela local `expense_splits`.

Domínio

4. `apps/finance/lib/features/transactions/domain/expense_split.dart` — **novo**:
   entidade `ExpenseSplit`, com `fromRow`/`toColumns`.
5. `apps/finance/lib/features/transactions/domain/transactions_repository.dart` —
   `watchSplits`, `splitEqually`, `removeSplit`.

Dados

6. `apps/finance/lib/features/transactions/data/transactions_repository_impl.dart`
   — os três métodos, com o SQL em `TransactionsSql`.

Apresentação

7. `apps/finance/lib/features/transactions/presentation/transactions_providers.dart`
   — provider das partes de um lançamento.
8. `apps/finance/lib/features/transactions/presentation/transaction_edit_sheet.dart`
   — seção "Dividido entre".
9. `apps/finance/lib/features/transactions/presentation/transaction_list.dart` —
   "Dividida" no `meta`.

Testes

10. `apps/finance/test/features/transactions/expense_split_test.dart` — **novo**.
11. `apps/finance/test/features/transactions/transactions_repository_impl_test.dart`
    — atualizar.
12. `apps/finance/test/features/transactions/transaction_edit_sheet_test.dart` —
    atualizar (ou criar, se não existir).
13. `apps/finance/test/helpers/app_harness.dart` — `testSplit`, e o fake de
    transações passa a registrar partes.
14. `apps/finance/test_integration/split_persistence_test.dart` — **novo**: o
    `writeTransaction` de marcar + ratear contra PowerSync de verdade, incluindo
    o `DELETE` do desfazer.

Fechamento: `docs/surfaces.md`, `docs/state.md`, `docs/product.md` (o fluxo 7
deixa de ser "não implementado" pela metade).

## Casos

**Rateio**

- Dois membros, R$ 10,00 → duas partes de R$ 5,00.
- Três membros, R$ 10,00 → R$ 3,34 + R$ 3,33 + R$ 3,33; a soma fecha o total.
- Um membro só (o espaço ficou com uma pessoa) → uma parte igual ao total.
- R$ 0,01 entre três → uma parte de R$ 0,01 e duas de zero. **Decidir no
  contrato:** parte de valor zero é gravada, ou o `check (amount_minor > 0)`
  recusa? → **gravada**, com o `check` em `>= 0`: omitir a pessoa mentiria sobre
  quem participou da despesa.
- Membro com `status = 'left'` → fora do rateio.

**Marcar e desfazer**

- Marcar → `is_shared` verdadeiro e N partes, numa transação só.
- Desfazer → partes apagadas e `is_shared` falso, numa transação só.
- Marcar duas vezes (toque duplo) → não duplica parte; o `unique (transaction_id,
  user_id)` é a rede, e o caminho é apagar-e-reinserir.
- Editar o valor de um lançamento já dividido → **as partes são refeitas**. Sem
  isso a soma das partes deixa de fechar o total, em silêncio.
- Lançamento que financia uma meta → a seção não aparece (o sheet já recusa
  editar).
- Tipo `income`, `transfer` ou `savings` → a seção não aparece.
- Espaço `personal` ou `household` → a seção não aparece.
- Offline → grava local e aparece na hora; sobe quando a conexão volta.

**Leitura**

- Lançamento dividido, aberto → uma linha por membro, com o nome que a fatia
  `nome-de-membro` trouxe, caindo no fallback quando não há nome.
- Lista do mês → "Dividida" no `meta` da linha, junto do que já está lá.
- Lançamento não dividido → nada muda em lugar nenhum.

## Fora de escopo

- **O saldo "quem deve a quem"**, e liquidar via Pix. Depende da questão #2 do
  PRD (algoritmo de minimização de transferências, RN-2.2), que segue sem
  resposta. É a razão de esta fatia parar nas partes.
- **Percentual e valor exato.** Ver decisão 2.
- **Escolher quem entra no rateio.** Todo membro ativo entra. Excluir alguém de
  uma despesa específica é o que percentual e exato resolvem melhor.
- **Dividir em `household`.** Ver decisão 2.
- **Marcar no `+`.** Ver decisão 1.
- **Notificar quem entrou num rateio.** Fase 3.
