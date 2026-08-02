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
está pela metade: a despesa de grupo já se divide em partes iguais, mas o saldo
"quem deve a quem" depende da questão #2 do PRD.

## Última fatia

`dividir-despesa` — abrir uma despesa de espaço `group` oferece "Dividir
igualmente", e o rateio vira uma linha por membro em `expense_splits`.

Duas decisões de produto que o repo não respondia, e que agora moram no lugar
que elas mordem. **A marcação é no sheet de edição, não no `+`**: o
`surfaces.md` protege o fluxo dos 30 segundos de ganhar passo, e o custo — em
república, dividir passou a ser dois gestos — está registrado lá com o caminho
de reverter. **Só rateio igual**: percentual e exato pedem tela de configuração.

**A fatia foi grande de novo** (2.455 linhas, 27 arquivos), e desta vez sem
decisão que a justifique: tabela nova arrasta migration, sync rules, schema
local, entidade, três métodos de repositório, seção de UI e seis fakes de teste
que implementam a interface. É o piso de uma tabela nova neste projeto, e vale
saber disso ao dimensionar a próxima.

Dois defeitos apareceram no teste de integração e nenhum mock os pegaria: apagar
o lançamento deixava partes órfãs (view não tem chave estrangeira, então o
`on delete cascade` do Postgres não existe no aparelho), e `is_shared` vinha da
entidade que a folha carregou ao abrir — dividir e salvar apagava a marca.

## Próximas fatias

1. **quem-deve-a-quem** *(feature)* — **bloqueada** pela questão #2 do PRD
   (algoritmo de minimização de transferências, RN-2.2). As partes já existem;
   falta decidir como o saldo vira o menor número de transferências.
2. **rateio-percentual** *(feature)* — usa o `share_percentage` que
   `space_members` já tem, caindo no igualitário quando é nulo.
   `Money.allocate(ratios)` já resolve a matemática. Exige tela para declarar a
   cota, que é o que a manteve fora de `dividir-despesa`.
3. **nome-no-cadastro** *(feature, pequena)* — hoje quem se cadastra passa por
   toda a primeira sessão sem nome, e só descobre a seção "Você" se abrir o
   Perfil. Um campo no `signUp` (metadata → `handle_new_user`) fecha isso.

## Não visto rodando

Escrito, testado e mergeado — mas nunca exercitado num aparelho. Vale mais que
teste verde, e é o primeiro lugar onde procurar quando algo surpreender.

- **Gestão de membro com um segundo login** — trocar papel do convidado,
  removê-lo, vê-lo sair da lista. Este caminho nunca foi percorrido.
- **A divisão de despesa inteira.** Nada dela foi exercitado num aparelho, e ela
  é a primeira fatia desde `espacos-compartilhados` a **exigir republicar as
  sync rules à mão**. Se as partes não aparecerem para o outro membro e não
  houver erro nenhum, a causa é essa, não o código.
- **A propagação do nome para o peer.** Os dois triggers da
  `20260801205317` rodam no Postgres, e nenhum teste alcança o servidor. O que
  está provado é a escrita local e a leitura da coluna; que trocar o nome
  reescreve a membership **do outro aparelho** só se vê com dois logins. Se algo
  aqui falhar, o sintoma é o peer continuar vendo o nome antigo — a linha nunca
  fica vazia, porque o fallback assume.
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
- **Golden test: descartado, não postergado.** Decidido em 2026-08-01. Era a
  fatia `andaime-de-golden`, e não vai acontecer: exigiria empacotar Inter e IBM
  Plex Mono (sem elas o golden renderiza caixinha) e manter baseline de imagem,
  e isso não se paga aqui. A consequência é permanente e virou regra de trabalho
  na `AGENTS.md`: **toda iteração de layout termina no usuário olhando a tela**,
  e o que substitui o degrau é o mockup aprovado antes do código mais teste de
  widget para o que se verifica sem olhar. Reabrir isto só faria sentido se a UI
  passasse a ser mexida por várias pessoas ao mesmo tempo.
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
- **Teste que lê `DateTime.now()` passa por coincidência de calendário.** Em 1º
  de agosto de 2026 a `main` ficou vermelha sozinha: `FocusedMonth` era a única
  leitura de "hoje" na apresentação que escapava do `clockProvider`, e casava
  com helpers ancorados no relógio real. Dado de teste ancora em `testNow`;
  provider lê o `clockProvider`. As duas pontas, ou nenhuma.
