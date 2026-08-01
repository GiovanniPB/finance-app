# Estado

> Documento **vivo**: reescrito a cada fatia, nunca acumulado.
> O `git log` é o arquivo morto — não duplique histórico aqui.
> Confortável até 180 linhas; o CI falha acima de 240.

## Onde estamos

O app roda em iOS e macOS contra Supabase e PowerSync na nuvem, com **2.083
lançamentos de banco real** ingeridos. Funciona de ponta a ponta: registrar
gasto, ver o mês, orçamento com alerta, contas, conectar e desconectar banco,
metas de poupança com progresso, sequência e conquistas, e espaços
compartilhados com convite por código e gestão de papéis.

Falta da Fase 1 apenas a **categorização por IA**, adiada por decisão. A Fase 2
está pela metade: espaços existem, `expense_splits` não.

## Última fatia

`gestao-de-membros` — trocar papel, remover, sair, arquivar e renomear espaço,
com três furos de escalonamento de privilégio medidos antes e fechados depois
(PR #36).

## Próximas fatias

1. **andaime-de-golden** *(débito)* — o degrau 1 da escada existe: um golden do
   `TransactionTile` é gerado e o agente lê o PNG sozinho. Exige empacotar Inter
   e IBM Plex Mono. **Sem isso, toda iteração de UI depende de alguém olhar a
   tela** — é a fatia que paga por si.
2. **nome-de-membro** *(feature)* — a linha de membro mostra o nome de quem é,
   em vez de "Você" / "Quem criou" / "No espaço desde 12 de julho". Caminho
   mapeado: bucket `space_peers` no `sync_rules.yaml` com parameter query
   juntando `space_members` consigo mesma, mais policy de SELECT em `profiles`.
   Exige **republicar as sync rules à mão**.
3. **dividir-despesa** *(feature)* — uma despesa marcada como dividida num
   espaço `group` gera `expense_splits`. `Money.allocate()` já resolve a
   matemática (RN-2.1). O saldo "quem deve a quem" é outra fatia, e depende da
   questão #2 do PRD.

## Não visto rodando

Escrito, testado e mergeado — mas nunca exercitado num aparelho. Vale mais que
teste verde, e é o primeiro lugar onde procurar quando algo surpreender.

- **Gestão de membro com um segundo login** — trocar papel do convidado,
  removê-lo, vê-lo sair da lista. Este caminho nunca foi percorrido.
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

- **Backfill da detecção de poupança** — a regra só olha linha recém-inserida,
  para reprocessar não ressuscitar uma proposta recusada. Os 2.083 lançamentos
  antigos nunca viram proposta. Um backfill reabriria exatamente o "não" que a
  regra protege: teria de rodar uma vez só, sobre janela escolhida. Decidido em
  2026-07-28: não fazer.
- **A cadeia de migrations nunca rodou do zero.** As 15 subiram por
  `supabase db push` sobre schema existente; `supabase db reset` num banco vazio
  exige Docker. É a diferença entre "aplica sobre o schema atual" e "o repo
  descreve o banco".
- **Categorização por IA** — adiada até a questão #4 do PRD (modelo próprio vs.
  API, e dado sensível na inferência) ter resposta.
- **Pagamento de fatura conta duas vezes.** No cartão virou `transfer`
  (correto); o débito correspondente na conta corrente segue como `expense`.
  Separar exige heurística sobre descrição — o tipo de regra que já envelheceu
  mal duas vezes aqui.
- **Estorno de cartão fica invisível no resumo.** Chega negativo, com assinatura
  idêntica à de pagamento de fatura. Não há campo que os separe sem heurística.
- **Saldo de conta não reconcilia com lançamento.** Snapshot por decisão,
  mitigado por `balance_as_of`. Sair disso é decisão de produto: reconciliar
  pelo Open Finance, ou exibir um saldo estimado ao lado do informado.
- **`join_space_by_code` sem rate limit.** O que protege são ~6,6·10¹¹ códigos e
  expiração de 7 dias. Resolver antes de a base crescer.
- **O upload ao Postgres não é testado automaticamente.** Os testes de
  integração param na camada local; provar que a linha sai da fila e chega ao
  Supabase é passo manual. Automatizar exige um projeto Supabase descartável.
- **Abas sem URL própria** — `IndexedStack`. Quando deep link virar requisito,
  trocar por `StatefulShellRoute`.
- **`pendingContributionsCount` sem tela** — quem não abre a aba Poupança não
  fica sabendo que há aporte a confirmar. O caminho é marcador na bottom nav.

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
- **A policy de SELECT governa a linha velha e a nova de todo UPDATE.** Linha
  velha invisível ⇒ 0 linhas **sem erro**; linha nova invisível ⇒ `42501`. O
  `SupabaseConnector` descarta o batch, então nada disso chega à tela: aparece
  aplicado e some no checkpoint.
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
