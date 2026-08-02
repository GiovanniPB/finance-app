# ADR 0011 — Dado de outro membro viaja na linha que já está no bucket

- Status: aceito
- Data: 2026-08-01

## Contexto

A lista de membros precisava mostrar o nome de cada pessoa. O nome mora em
`profiles.display_name`, e as sync rules entregam `profiles` no bucket
`user_owned` — **só o meu**. O perfil de outro membro nunca chega ao aparelho.

O caminho óbvio seria um bucket novo com um parameter query juntando
`space_members` consigo mesma para descobrir quem são os meus pares. Ele não
existe. A doc do PowerSync é explícita sobre Sync Rules:

> Not supported: subqueries, JOINs, CTEs, aggregation, sorting, or set
> operations

A restrição vale para parameter query **e** para data query. Sem join,
`profiles` é inalcançável por espaço, porque a tabela não tem `space_id` — e
uma tabela de identidade não deveria ter.

Este repo já tinha topado com a mesma parede uma vez, em
`savings_contributions`: a contribuição pertence à meta, o espaço estava a um
join de distância, e a saída foi denormalizar `space_id` na própria linha.

## Decisão

**Dado que só é alcançável por join é copiado para a linha que já está no
bucket, e a cópia é mantida por trigger no Postgres.**

Concretamente, `space_members.display_name` é cópia de `profiles.display_name`,
com dois triggers:

- `space_members_inherit_display_name` (`before insert`) — a membership nasce
  com o nome de quem entrou;
- `profiles_propagate_display_name` (`after update of display_name`) — trocar o
  nome reescreve toda membership da pessoa.

`profiles` continua sendo a **fonte da verdade**. A UI nunca escreve a cópia.

### Por que isto não contradiz o ADR 0007

O [ADR 0007](0007-agregado-derivado-vs-coluna.md) descarta explicitamente
"coluna mantida por trigger no Postgres". Ele descarta para **agregado**, e o
teste que ele mesmo define é: *se duas réplicas offline podem chegar a valores
diferentes para a mesma verdade, não é coluna.*

`display_name` passa nesse teste. Um agregado tem escritores concorrentes — dois
aparelhos somando contribuições diferentes. O nome de uma pessoa tem **um**
escritor: ela mesma, e a policy `profiles_update_own` garante isso. Não há duas
réplicas capazes de discordar sobre qual é o meu nome.

A segunda objeção do 0007 — "o cliente offline mostraria o valor velho até o
sync voltar, e o número que o usuário acabou de mover é justamente o que ele
está olhando" — é real e foi resolvida em vez de ignorada: **a minha própria
linha lê `profiles`, não a cópia** (`MemberCopy.identity` recebe
`myDisplayName`). O valor velho só existiria para os pares, que não estão
olhando enquanto eu digito.

## Consequências

- **Coluna nova não exige republicar as sync rules.** `by_space` lê
  `select * from space_members`, e a republicação manual no dashboard é a
  armadilha nº 1 deste repo — falha como tela vazia, sem erro nenhum. Um bucket
  novo teria atravessado essa armadilha; uma coluna não.
- **A visibilidade sai de graça e correta.** O nome fica visível a quem já
  enxerga a membership: membros ativos dos meus espaços. Nenhuma policy nova em
  `profiles`, que continua com as três `*_own` da `20260714153329`.
- **Dado duplicado.** Trocar o nome faz fan-out para N linhas de membership. O
  índice `space_members_user_id_idx` atende, e N é o número de espaços de uma
  pessoa — unidades, não milhares.
- **A cópia sobrevive a quem sai.** A linha com `status = 'left'` guarda o nome.
  É coerente com ela permanecer para o histórico não ficar órfão.
- **A regra generaliza.** A próxima vez que um dado de outro membro precisar
  atravessar o bucket — foto, moeda preferida —, o caminho já está escolhido, e
  o custo de decidir de novo é zero.

## Alternativas descartadas

- **Bucket `space_peers` com self-join** — era o caminho mapeado em
  `docs/state.md` antes desta fatia. Não é implementável: Sync Rules não fazem
  JOIN.
- **Tabela de pares `(user_id, peer_id, display_name)` mantida por trigger** —
  funciona sem join, mas é mais maquinário que uma coluna **e** tabela nova
  exige republicar as sync rules. Pior nos dois eixos.
- **Abrir `profiles` para SELECT de quem compartilha espaço** — resolveria a RLS,
  não o sync: sem `space_id` em `profiles`, o data query ainda não teria como
  recortar por bucket. E ampliaria a superfície de leitura sobre a tabela de
  identidade sem necessidade.
- **Sync Streams** — suportam `INNER JOIN` com restrições, e resolveriam sem
  denormalizar. Trocar Sync Rules por Sync Streams é migrar toda a configuração
  de sync do projeto: fatia própria, com ADR próprio. **É o gatilho para
  revisitar esta decisão.**
