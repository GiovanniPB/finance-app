# Fatia: nome-de-membro

tipo: feature

## Pronto quando

A lista de membros de um espaço identifica cada pessoa pelo nome que ela mesma
definiu no Perfil.

> **Esta fatia fura a regra do "e", por decisão do usuário em 2026-08-01.** São
> dois resultados — *eu defino meu nome* e *eu vejo o nome do outro* — e o teste
> do "e" pediria duas fatias. Vão juntas porque separadas nenhuma demonstra:
> hoje `profiles.display_name` é **nulo para todo usuário que existe**. O
> `signUp` não envia metadata, o onboarding não pergunta e a feature `profile`
> só tem `presentation/`. Entregar só a leitura deixaria a lista exibindo o
> texto de hoje, e a demonstração dependeria de semear `display_name` por SQL à
> mão.

## Superfícies

- **Perfil** — `profile_page.dart` ganha uma seção **"Você"** no topo, antes de
  "Contas", com o nome. Tocar abre `profile_name_sheet.dart` para editar.
  Nenhuma tela nova: é seção numa aba que já existe.
- **Detalhe do espaço** — `space_detail_page.dart`, a linha de membro. A
  primeira linha passa a ser o **nome**; o que hoje é a identidade
  ("Você" / "Quem criou o espaço") vira qualificador depois do nome. Sem nome,
  a linha fica **exatamente** como está hoje.

Mockup: `docs/slices/nome-de-membro.mockup.html` — pendente

> O mockup mora no repo, não na conversa. Se ele existe só no histórico da
> sessão, a próxima sessão perde o alvo visual e a fatia recomeça do zero.

## Decisões de desenho

Três, e todas mudam o que o código faz. Ficam aqui porque foram tomadas antes de
existir arquivo para receber o cabeçalho — na execução, cada uma vai para o
cabeçalho do arquivo que ela morde.

### 1. O nome viaja em `space_members.display_name`, não num bucket novo

O caminho mapeado em `docs/state.md` era um bucket `space_peers` com parameter
query juntando `space_members` consigo mesma. **Não é viável:** a doc do
PowerSync é explícita para Sync Rules — *"Not supported: subqueries, JOINs,
CTEs, aggregation, sorting, or set operations"* — e vale para parameter query e
data query. O próprio `powersync/sync_rules.yaml` deste repo já registra o
motivo, na linha de `savings_contributions`: "sync rule não faz join".

Sem join, `profiles` é inalcançável por espaço: a tabela não tem `space_id`.
Fazê-la alcançável exigiria uma tabela nova de pares — mais trabalho que uma
coluna, e **tabela nova exige republicar as sync rules**.

Denormalizar tem três consequências boas:

- **Zero republicação manual.** Coluna nova em tabela que já está no `by_space`
  não exige republicar (`AGENTS.md`), e `by_space` lê `select *`. Isso remove da
  fatia a armadilha nº 1 do repo — "tela vazia, sem erro nenhum".
- **Zero policy nova em `profiles`.** A visibilidade passa a ser a do bucket
  `by_space`: membros ativos dos meus espaços, exatamente o alvo. Nada é
  concedido a `anon` nem a autenticado de fora.
- **Precedente no repo.** `savings_contributions.space_id` é denormalizado pela
  mesma razão, com trigger no Postgres mantendo o valor.

O custo é dado duplicado, mantido por trigger. Aceito.

### 2. O meu nome vem de `profiles`; o dos outros, de `space_members`

A propagação do meu nome para os peers é servidor → trigger → replicação. Se a
minha própria linha lesse só `space_members`, eu definiria meu nome no Perfil e
veria a linha velha até o round-trip completar — offline, indefinidamente. Então
`_MemberRow` recebe o meu nome de `profiles` (que é escrita local, instantânea)
e usa `space_members.display_name` para as outras linhas.

### 3. `UPDATE`, nunca `UPSERT`

A linha de `profiles` já existe quando o usuário chega ao Perfil: o trigger
`handle_new_user` a cria no cadastro. E as tabelas locais do PowerSync são views
com triggers `INSTEAD OF` — o SQLite **recusa** `UPSERT` (armadilha registrada).
Escrita é `update profiles set display_name = ? where id = ?`, provada por teste
que executa SQL de verdade, não por mock.

## Arquivos que mudam

Backend e schema

1. `supabase/migrations/<ts>_nome_de_membro.sql` — **novo**: coluna
   `display_name` em `space_members`; backfill a partir de `profiles`; trigger
   `before insert` em `space_members` que herda o nome; trigger
   `after update of display_name` em `profiles` que propaga para toda membership
   do usuário. As duas funções em `public`, com `revoke execute … from anon,
   authenticated, public` e `set search_path = ''`.
2. `packages/database/lib/src/schema.dart` — `Column.text('display_name')` em
   `space_members`.

Domínio

3. `apps/finance/lib/features/spaces/domain/space_member.dart` — campo
   `String? displayName`, em `fromRow` e `toColumns`.
4. `apps/finance/lib/features/profile/domain/profile.dart` — **novo**: entidade
   `Profile(id, displayName)` com `fromRow`.
5. `apps/finance/lib/features/profile/domain/profile_repository.dart` —
   **novo**: `watchMine()` e `updateDisplayName(String)`.

Dados

6. `apps/finance/lib/features/profile/data/profile_repository_impl.dart` —
   **novo**.

Apresentação

7. `apps/finance/lib/features/profile/presentation/profile_providers.dart` —
   **novo**.
8. `apps/finance/lib/features/profile/presentation/profile_name_sheet.dart` —
   **novo**, espelhando `space_rename_sheet.dart`.
9. `apps/finance/lib/features/profile/presentation/profile_page.dart` — seção
   "Você".
10. `apps/finance/lib/features/spaces/presentation/member_copy.dart` — nome com
    fallback.
11. `apps/finance/lib/features/spaces/presentation/space_detail_page.dart` —
    `_MemberRow` recebe o meu nome.
12. `apps/finance/lib/di/providers.dart` — `profileRepositoryProvider`.

Testes

13. `apps/finance/test/features/profile/profile_repository_impl_test.dart` —
    **novo**.
14. `apps/finance/test/features/profile/profile_page_test.dart` — **novo**.
15. `apps/finance/test/features/spaces/member_copy_test.dart` — **novo**.
16. `apps/finance/test/features/spaces/space_detail_page_test.dart` — atualizar.
17. `apps/finance/test_integration/profile_persistence_test.dart` — **novo**: o
    `UPDATE` rodando contra PowerSync local de verdade.

Gerados (`melos run gen`, não versionados): `space_member.freezed.dart`,
`profile.freezed.dart`, `profile_providers.g.dart`.

Fechamento: `docs/surfaces.md`, `docs/state.md`.

## Casos

**Definir o nome**

- Perfil sem nome → a seção "Você" convida a definir, não mostra vazio mudo.
- Nome definido → aparece no Perfil sem recarregar (`watch`).
- Nome com espaço nas pontas → gravado sem as pontas.
- Nome só de espaços → recusado, sheet não fecha.
- Nome de 1 caractere → aceito. De 121 → recusado (mesmo limite 1–120 que o
  `check` de `spaces.name`).
- Nome com emoji e acento → gravado inteiro, sem mojibake.
- Trocar o nome duas vezes → a segunda vence; nenhuma linha órfã.
- Offline → grava local, aparece na tela, sobe quando a conexão volta.
- Linha de `profiles` ainda não sincronizada → o campo não finge que salvou: a
  seção mostra estado de carregando e o sheet não abre.

**Ver o nome na lista de membros**

- Nenhum membro com nome → a lista fica **idêntica** à de hoje (é o teste que
  protege o fallback).
- Só eu tenho nome → a minha linha mostra o nome; as outras, o texto de hoje.
- Três membros, todos com nome → três nomes distintos, nenhuma data de entrada.
- Dois membros com o **mesmo** nome → as linhas continuam distinguíveis, porque
  o qualificador de papel e a ação não mudaram.
- Eu, que criei o espaço, com nome → nome mais qualificador de dono, uma linha.
- Membro removido (`status = 'left'`) → não aparece na lista; a coluna guardar o
  nome dele não o ressuscita.
- Espaço pessoal (um membro só) → a seção de membros segue como está.

**Propagação**

- Troco meu nome → minha linha muda na hora (vem de `profiles`).
- Troco meu nome → a linha que o peer vê muda depois do round-trip, sem ele
  republicar nada.
- Entro num espaço novo já tendo nome → a linha nasce com o nome (trigger de
  `before insert`).
- Usuário criado antes desta fatia → o backfill dá conta; nenhuma linha fica com
  `display_name` nulo tendo perfil com nome.

## Fora de escopo

- **Campo de nome no cadastro.** `signUp` continua sem enviar metadata: quem se
  cadastra define o nome no Perfil depois. Mexer no cadastro é tela fora do
  shell e ampliaria a fatia que já está no teto.
- **Foto de perfil / avatar.** A linha continua com `CategorySwatch.brand`.
- **E-mail do outro membro.** Só o nome atravessa. E-mail é dado de contato e não
  cabe no bucket por decisão de privacidade — pediria ADR.
- **Nome por espaço** (apelido diferente na república e no household). A coluna
  em `space_members` tecnicamente permitiria, mas a fonte da verdade é
  `profiles`; divergir exigiria decidir quem ganha.
- **Sync Streams.** Elas suportam `INNER JOIN` e resolveriam sem denormalizar,
  mas trocar Sync Rules por Sync Streams é migração de toda a configuração de
  sync — fatia própria, com ADR.
- **Rate limit de `join_space_by_code`** e os outros débitos de `state.md`.
