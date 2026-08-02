# Superfícies

As telas que existem, como se navega entre elas, e os componentes que as
compõem. Atualize quando nascer tela ou componente — não registre histórico
aqui.

## Navegação

Três rotas no `go_router`, e o resto vive dentro do shell:

```
/sign-in       LoginPage          — sem sessão
/apresentacao  OnboardingPage     — sessão nova, ainda não apresentada
/              AppShell           — o app
```

O guard tem ordem obrigatória: **autenticar primeiro, apresentar depois**. A
apresentação termina abrindo o registro rápido, que precisa de espaço ativo, e
espaço só existe depois do login.

Dentro do `AppShell`, quatro abas em `IndexedStack` mais a ação central:

```
[ Início ]  [ Espaços ]  [ + ]  [ Poupança ]  [ Perfil ]
```

A aba **Social** do PRD ainda não existe; Poupança ocupa o lugar dela.

## Telas

### Início — `space_home_page.dart`

Visão do espaço ativo: saldo gastável, entradas e saídas do mês, orçamento por
categoria com alerta em 80% e 100%, atividade recente com "Ver tudo".

- **Lista do mês** — `transactions_page.dart`: lançamentos agrupados por dia,
  com total do dia e cabeçalho de saldo. O valor da linha é sempre o **total**,
  nunca a parte de quem olha — mudar isso faria o saldo do mês não fechar.
- **Editar lançamento** — `transaction_edit_sheet.dart`: recusa editar o que
  pertence a uma meta, e abre em leitura com caminho para ela.
- **Dividir despesa** — `split_section.dart`, no fim da folha de edição.
  **"Quem pagou"** (pílula por membro ativo) vem antes de **"Dividido entre"**:
  o rateio só significa algo depois de se saber quem adiantou. Depois, um botão
  de rateio igual, uma linha por membro, e a soma das partes. A seção inteira
  aparece **só** em despesa de espaço `group`; nas outras situações ela não
  existe, em vez de existir desabilitada. O pagador não grava ao toque — é campo
  do formulário e sobe no "Salvar".
- **Orçamentos** — `budgets_page.dart` + `budget_form_sheet.dart`.

### Espaços — `spaces_page.dart`

Lista de espaços. O toque abre o espaço; o círculo à direita troca o espaço
ativo num toque.

- **Detalhe** — `space_detail_page.dart`: membros, papéis, convite por código,
  renomear, arquivar, sair. O dono não vê "Sair do espaço" — vê a frase que
  explica por quê. A linha de membro lidera com o **nome** (definido no Perfil)
  e cai no texto antigo — "Você" / "No espaço desde …" — enquanto não houver
  nome. Com nome, a data de entrada some: ela era muleta de desempate.
- **Acertar contas** — `settlement_section.dart`, abaixo dos membros e **só** em
  espaço `group`. O cabeçalho responde "e eu?" antes da lista; cada linha é uma
  transferência que zera parte do grupo. **Quem olha se acha pelo peso da
  palavra "Você"**, não por fundo colorido — em grupo de três quase toda
  transferência envolve você. Só a linha que envolve você tem chevron, e tocá-la
  abre o diálogo que registra o acerto. Três vazios, três frases: nada dividido
  ensina onde dividir, tudo quite é resultado, moeda divergente recusa somar.
- **Ações de membro** — `member_actions_sheet.dart`: trocar papel, remover.
- **Criar / entrar** — `space_form_sheet.dart`, `join_space_sheet.dart`,
  `space_rename_sheet.dart`.

### `+` — `quick_entry_sheet.dart`

O fluxo dos 30 segundos: valor no teclado próprio, categoria, conta. É a única
superfície que **não pode ganhar passo** sem revisar a promessa de entrada.

A regra já custou uma decisão: a fatia `dividir-despesa` (2026-08-01) queria um
interruptor "Dividir" aqui, e ele foi para a folha de edição em vez disso.
Dividir virou um segundo gesto — pior para quem mora em república, que é o caso
comum de grupo. Se doer no uso, a saída é **revisar esta promessa de propósito**,
numa fatia que discuta o que o `+` passa a ser, e não deixar um campo vazar para
cá sem ninguém decidir.

### Poupança — `savings_page.dart`

Metas ativas e pausadas, sequência semanal com melhor marca, e sete conquistas
— a bloqueada diz o que falta, em vez de exibir cadeado.

- **Detalhe de meta** — `goal_detail_page.dart`: progresso, contribuições,
  aportes detectados a confirmar. Meta pausada cala o que cobra ritmo.
- **Criar / editar meta** — `goal_form_sheet.dart` (pausar é campo do
  formulário, não ação própria).
- **Guardei um valor** — `contribution_sheet.dart`, com o campo "Saiu de".

### Perfil — `profile_page.dart`

"Você", contas bancárias, "Suas categorias", conexões de Open Finance.

- **Você** — `profile_name_sheet.dart`. O **único** lugar que escreve
  `profiles.display_name`; o cadastro não pergunta o nome. Antes de a linha de
  `profiles` sincronizar a seção não é tocável: `UPDATE` sem linha afeta zero e
  não dá erro.
- **Conta** — `account_form_sheet.dart`. "Excluir conta" só aparece em conta não
  importada.
- **Categoria** — `category_form_sheet.dart`.
- **Conectar banco** — `connect_bank_page.dart` (widget Connect internalizado) +
  `connection_sheet.dart` (desconectar).

### Fora do shell

- **Login** — `login_page.dart`. Mensagens de erro em português.
- **Apresentação** — `onboarding_page.dart`: três telas, uma por pilar. Comunica
  a ambição inteira, exige só a ação mínima.

## Componentes base — `packages/design_system`

| Componente | Para quê |
|---|---|
| `AmountDisplay` · `AmountKeypad` | entrada de valor (com `FittedBox`: cinco dígitos não cabem em 40px mono) |
| `MoneyText` | exibição de valor, com `tabularFigures` |
| `BalanceHeader` | cabeçalho de saldo |
| `TransactionTile` | linha de lançamento |
| `BudgetProgress` · `SavingsProgress` | barras de progresso — **mesma forma, significados opostos** |
| `CategoryChip` · `CategorySwatch` | categoria (cor é índice de paleta) |
| `AppButton` · `AppTextField` · `AppSegmentedControl` | controles |
| `AppEmptyState` | vazio (usa `mainAxisSize.min` — sem isso vira moldura de tela cheia) |
| `AppBottomNav` · `SheetGrabHandle` · `ScrollEdgeFade` | chrome |

## Regras visuais que não se negociam

- **Despesa é o estado neutro.** A espinha do sistema visual; a doc está em
  `app_tokens.dart`.
- **Barra de meta e barra de orçamento têm a mesma forma e significados
  opostos.** Encher a de meta é bom; encher a de orçamento é alerta. O que as
  separa está documentado em `savings_progress.dart` — leia antes de mexer em
  qualquer UI de progresso.
- O app é **só em português** (`pt_BR` como único locale declarado). Sem
  `localizationsDelegates`, todo widget do Material sai em inglês — e isso não
  aparece em revisão de código, só rodando.
