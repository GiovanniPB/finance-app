# Estado

> Documento **vivo**: reescrito a cada fatia, nunca acumulado.
> O `git log` é o arquivo morto — não duplique histórico aqui.
> Confortável até 180 linhas; o CI falha acima de 240.

## Onde estamos

O app roda em iOS e macOS contra Supabase e PowerSync na nuvem, com **2.083
lançamentos de banco real** ingeridos. Funciona de ponta a ponta: registrar
gasto, ver o mês, orçamento com alerta, contas, conectar e desconectar banco,
metas de poupança com progresso, sequência e conquistas, e espaços
compartilhados com convite por código, gestão de papéis e pessoas identificadas
pelo nome.

Falta da Fase 1 apenas a **categorização por IA**, adiada por decisão. A Fase 2
fechou o ciclo do dinheiro compartilhado: dividir a despesa, dizer quem pagou,
ver quem deve a quem, e registrar o acerto.

## Antes de abrir o app

**A migration `20260801224605` não foi aplicada.** Sem `supabase db push` a
coluna `paid_by` não existe no servidor, e o sintoma é o pior deste repo: o
upload da edição é recusado, o `SupabaseConnector` descarta o batch em silêncio,
e a troca de pagador aparece aplicada até o checkpoint seguinte.

A republicação das **sync rules** continua pendente desde `dividir-despesa` — por
causa da tabela `expense_splits`, não desta fatia. Sem ela as partes não chegam
ao outro aparelho, e a seção "Acertar contas" fica vazia sem erro nenhum.

## Última fatia

`acertar-contas` — o detalhe de um espaço `group` mostra a menor lista de
transferências que zera o grupo, e registrar o acerto zera o par.

Duas decisões caras viraram ADR. A [0012](adr/0012-saldo-liquido-com-guloso.md)
responde a questão #2 do PRD, aberta desde a fundação: saldo **líquido** com
casamento guloso, no máximo `n−1` transferências, aceitando de propósito que o
app possa mandar você pagar alguém com quem não gastou. A
[0013](adr/0013-o-acerto-e-um-transfer-dividido.md) é o que barateou a fatia: o
acerto **não tem tabela**, é um `transfer` com `paid_by` e uma parte só, e a
fórmula `pagou − deve` o absorve sozinha.

**A fatia foi grande: 3.696 linhas e 30 arquivos, o dobro do teto.** Desta vez a
causa está registrada e não é acidente. A decomposição foi proposta
(`pagador-explicito` ~700 linhas, depois `acertar-contas` ~1.500) e recusada: o
usuário escolheu o escopo inteiro em 2026-08-01 aceitando o tamanho. O que
manteve a fatia em 3.696 e não em 6.000 foi a ADR 0013 — tabela nova custou
2.455 linhas na fatia anterior.

O que o mockup pegou antes do código, e teria custado retrabalho depois: a
premissa de que quem lança é quem paga (rejeitada, virou coluna `paid_by`), e um
saldo que nada zera (rejeitado, virou o acerto). Nenhuma das duas apareceria num
teste.

## Próximas fatias

1. **rateio-percentual** *(feature)* — usa o `share_percentage` que
   `space_members` já tem, caindo no igualitário quando é nulo.
   `Money.allocate(ratios)` já resolve a matemática. Exige tela para declarar a
   cota, que é o que a manteve fora de `dividir-despesa`.
2. **nome-no-cadastro** *(feature, pequena)* — hoje quem se cadastra passa por
   toda a primeira sessão sem nome, e só descobre a seção "Você" se abrir o
   Perfil. Um campo no `signUp` (metadata → `handle_new_user`) fecha isso. Ganhou
   peso: sem nome, a linha de acerto diz "Membro sem nome".
3. **acerto-parcial** *(feature, pequena)* — hoje o acerto é o valor inteiro da
   transferência proposta. Pagar metade exige uma tela de valor.

## Não visto rodando

Escrito, testado e mergeado — mas nunca exercitado num aparelho. Vale mais que
teste verde, e é o primeiro lugar onde procurar quando algo surpreender.

- **Toda a fatia `acertar-contas`.** Escolher o pagador, ver o saldo, registrar
  o acerto. Depende da migration acima; sem ela, escolher pagador é a operação
  que falha em silêncio.
- **A divisão de despesa inteira**, da fatia anterior, pelo mesmo motivo das
  sync rules.
- **Gestão de membro com um segundo login** — trocar papel do convidado,
  removê-lo, vê-lo sair da lista.
- **A propagação do nome para o peer.** Os dois triggers da `20260801205317`
  rodam no Postgres, e nenhum teste alcança o servidor. Se falhar, o sintoma é o
  peer continuar vendo o nome antigo — a linha nunca fica vazia, porque o
  fallback assume.
- **Detecção de poupança** — precisa do worker deployado
  (`supabase functions deploy pluggy-sync-worker`, passo do usuário) e de uma
  conta marcada como alvo com meta ativa apontando para ela. Só **extrato novo**
  é proposto: "nada apareceu" sobre dado antigo é o esperado, não defeito.
- **Sequência e conquistas** — não dependem de deploy nenhum, basta abrir a aba
  Poupança. A tela com "12 semanas seguidas" nunca foi renderizada.

## Débitos conhecidos

Decisões conscientes de postergar, com o porquê. Débito que já está documentado
no arquivo que ele morde (cabeçalho de migration, de Edge Function ou de widget)
não se repete aqui.

- **Acerto e pagamento de fatura são o mesmo tipo.** O que os separa é ter
  partes (ADR 0013). Se a ingestão do Open Finance um dia criar `transfer` com
  partes, o saldo passa a contar dinheiro que não é dívida, e o sintoma é um
  saldo que não fecha.
- **Ninguém confirma o acerto do outro lado.** Quem registra decide sozinho que
  o dinheiro mudou de mãos. Conserto é estado de confirmação, não outra
  modelagem.
- **Backfill da detecção de poupança** — a regra só olha linha recém-inserida,
  para reprocessar não ressuscitar uma proposta recusada. Os 2.083 lançamentos
  antigos nunca viram proposta. Decidido em 2026-07-28: não fazer.
- **A cadeia de migrations nunca rodou do zero.** As 16 subiram por
  `supabase db push` sobre schema existente; `supabase db reset` num banco vazio
  exige Docker. É a diferença entre "aplica sobre o schema atual" e "o repo
  descreve o banco".
- **Golden test: descartado, não postergado.** Decidido em 2026-08-01.
  Exigiria empacotar Inter e IBM Plex Mono (sem elas o golden renderiza
  caixinha) e manter baseline de imagem, e isso não se paga aqui. A consequência
  virou regra de trabalho na `AGENTS.md`: **toda iteração de layout termina no
  usuário olhando a tela**, e o que substitui o degrau é o mockup aprovado antes
  do código mais teste de widget para o que se verifica sem olhar.
- **Categorização por IA** — adiada até a questão #4 do PRD (modelo próprio vs.
  API, e dado sensível na inferência) ter resposta.
- **Pagamento de fatura conta duas vezes.** No cartão virou `transfer`
  (correto); o débito correspondente na conta corrente segue como `expense`.
- **Estorno de cartão fica invisível no resumo.** Chega negativo, com assinatura
  idêntica à de pagamento de fatura.
- **Saldo de conta não reconcilia com lançamento.** Snapshot por decisão,
  mitigado por `balance_as_of`.
- **`join_space_by_code` sem rate limit.** O que protege são ~6,6·10¹¹ códigos e
  expiração de 7 dias. Resolver antes de a base crescer.
- **O upload ao Postgres não é testado automaticamente.** Os testes de
  integração param na camada local. Automatizar exige um projeto Supabase
  descartável.
- **Abas sem URL própria** — `IndexedStack`. Quando deep link virar requisito,
  trocar por `StatefulShellRoute`.
- **`pendingContributionsCount` sem tela** — quem não abre a aba Poupança não
  fica sabendo que há aporte a confirmar.

## Armadilhas

Já morderam, vão morder de novo.

- **Sync rules não sobem sozinhas.** `powersync/sync_rules.yaml` precisa ser
  colado no dashboard e deployado à mão. Sintoma: tela vazia, **sem erro
  nenhum**. Coluna nova não exige republicar; tabela ou bucket novo, sim.
- **Schema muda só por arquivo em `supabase/migrations/` + `supabase db push`.**
  O `apply_migration` do MCP grava um histórico que o repo não reproduz. Já
  criou quatro migrations órfãs; o conserto é `supabase migration repair`.
- **SQL novo sobre tabela do PowerSync precisa de teste que execute de verdade.**
  As tabelas locais são **views com triggers `INSTEAD OF`**: o SQLite recusa
  `UPSERT`. Mock de `SqliteConnection` não distingue SQL válido de SQL recusado.
- **`watch` descobre as tabelas por `EXPLAIN QUERY PLAN`.** Tabela que a
  detecção não vê é stream que não re-emite — tela congelada, sem erro. É por
  isso que o SQL do saldo evita CTE e usa subquery derivada.
- **A policy de SELECT governa a linha velha e a nova de todo UPDATE.** Linha
  velha invisível ⇒ 0 linhas **sem erro**; linha nova invisível ⇒ `42501`. O
  `SupabaseConnector` descarta o batch, então nada disso chega à tela: aparece
  aplicado e some no checkpoint. É a razão de `paid_by` ser nulável e de não
  haver `check` de que o pagador é membro.
- **PR empilhado não tem CI.** O workflow dispara em `pull_request` para `main`;
  PR com base noutro branch nunca é checado.
- **Teste de recorte precisa do valor de fronteira e do dado no formato de quem
  escreve.** O dia 1º de todo mês ficou invisível por meses porque o teste
  evitava a fronteira *e* criava a linha pelo próprio repositório.
- **`console.log` de Edge Function não é diagnóstico** — só o dashboard lê. Toda
  observação nova vai para o `payload` do evento no banco.
- **Uma amostra de tamanho um não é convenção.** Duas regras de direção de
  lançamento foram derivadas de um conector só, e as duas gravaram dinheiro
  errado.
- **`--dart-define-from-file` precisa de caminho absoluto**, e vale no `build`,
  não só no `run`.
- **Teste que lê `DateTime.now()` passa por coincidência de calendário.** Dado de
  teste ancora em `testNow`; provider lê o `clockProvider`. As duas pontas, ou
  nenhuma.
