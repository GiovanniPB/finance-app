# ADR 0009 — Conquista é derivada até ser anunciada

- Status: aceito
- Data: 2026-07-28

## Contexto

O PRD (§5.2, §8.2) modela duas entidades para a gamificação do Pilar 3:

- `achievements (user_id, badge_key, earned_at)` — badges desbloqueados;
- streaks, que a RN-3.4 descreve como sequências de contribuições regulares, sem
  dizer onde vivem.

Nenhuma das duas existe no schema. A fatia de streaks e badges precisava decidir
se cria as tabelas ou deriva os dois do histórico de `savings_contributions`.

O [ADR 0007](0007-agregado-derivado-vs-coluna.md) já respondeu a pergunta geral
com um teste: **se duas réplicas offline podem chegar a valores diferentes para a
mesma verdade, não é coluna.** Streak e badge passam nesse teste com folga — dois
aparelhos com as mesmas contribuições calculam a mesma sequência e desbloqueiam
as mesmas conquistas, porque ambos são função pura do histórico mais a data.

O que complica é que `achievements` tem `earned_at`, e uma data de desbloqueio
*parece* fato informado — a categoria que o ADR 0007 admite como coluna.

## Decisão

**Streak e conquista são derivados. Nenhuma tabela nesta fatia.**

- `SavingsStreak.from(contributions, now)` — sequência corrente, melhor marca e
  o estado "em risco".
- `deriveBadges(...)` — a lista inteira, com desbloqueadas primeiro e as demais
  ordenadas pela proximidade.

`earned_at` **não** é derivado nem persistido: a conquista responde "está
desbloqueada?", não "quando foi". Uma data que se recalcula a cada leitura seria
o pior dos dois mundos — parece registro histórico e não é.

### O que muda na Fase 3

`achievements` passa a ser necessária, e por um motivo diferente do que o PRD
sugere. Não é cache do que se calcula: é o registro de que a conquista **foi
anunciada** no feed.

A diferença importa porque o feed publica um evento para outras pessoas. Evento
publicado é fato — não dá para despublicar, e não pode depender de uma
derivação que o próximo `DELETE` desfaz. Nesse momento a tabela guarda
`badge_key` + `earned_at` + o id da atividade de feed, e a derivação continua
sendo quem **decide** o desbloqueio; a tabela só registra que ele foi contado ao
mundo.

## Consequências

- **Zero migration, zero sync.** A fatia inteira é Dart puro mais UI, testável
  sem banco. Um limiar novo ou uma conquista nova não pedem schema.
- **Conquista pode ser perdida.** Excluir a contribuição que cruzou o limiar
  bloqueia a conquista de novo. É coerente — o dinheiro não foi guardado — e é
  aceitável enquanto a conquista vive só dentro do app. Deixa de ser na Fase 3,
  que é exatamente onde a tabela entra.
- **O streak nunca "quebra" retroativamente por causa do relógio.** Como a
  semana corrente só entra na contagem quando tem aporte, virar a segunda-feira
  não zera nada. Isso é regra de domínio, não de UI, e tem teste.
- **A melhor marca (`bestWeeks`) é o insumo dos badges de sequência**, não a
  sequência corrente. Quem fez 12 semanas e quebrou não perde a conquista — o
  que se perde é a sequência, não o histórico dela.
- **Chave estável separada do nome Dart.** `SavingsBadge.key` existe para o dia
  em que `achievements.badge_key` for gravada: renomear a constante é
  refatoração, renomear a chave seria perder conquista de quem já a tem.

## Alternativas descartadas

- **Criar `achievements` agora, escrita pelo cliente.** É o cenário que o
  ADR 0007 descreve: dois aparelhos offline cruzando o mesmo limiar gravariam a
  mesma conquista duas vezes, ou com datas diferentes, e o last-write-wins
  escolheria uma sem que ninguém soubesse. Precisaria de uma `unique
  (user_id, badge_key)` e ainda assim daria duas datas plausíveis para o mesmo
  evento.
- **Criar `achievements`, escrita por trigger no Postgres.** Consistente, e o
  cliente offline só veria a conquista depois do sync — justamente no momento em
  que ele acabou de guardar o dinheiro que a desbloqueou. Celebrar com atraso de
  rede é pior do que não celebrar.
- **Streak como coluna em `profiles`.** Precisaria ser recalculada por alguém a
  cada virada de semana, para todos os usuários, inclusive os que não abriram o
  app. Um cron para manter um número que o cliente calcula em microssegundos.
- **Derivar `earned_at` junto.** Tecnicamente possível (é a data da contribuição
  que cruzou o limiar), e enganoso: exibir "desbloqueado em 3 de julho" para um
  valor que muda se o usuário editar uma contribuição antiga é afirmar
  permanência onde não há.
