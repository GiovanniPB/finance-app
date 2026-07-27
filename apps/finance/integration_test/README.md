# Testes de integração

Rodam contra um **PowerSync de verdade** — um `PowerSyncDatabase` aberto num
diretório temporário a partir do `appSchema` — e não contra dublês.

```bash
fvm dart run melos run integration --no-select
```

Não precisa de simulador, de Docker nem de rede: o SDK do PowerSync traz a
extensão nativa por plataforma, e a suíte roda na própria máquina. É por isso
que ela cabe no CI (job **Integração (PowerSync local)**).

## Por que existem

O [CLAUDE.md §7](../../../CLAUDE.md) exclui da métrica de cobertura a glue de
composição e de sync — `bootstrap.dart`, os entrypoints de flavor,
`di/providers.dart` e `powersync_service.dart` — dizendo que ela é coberta por
integração. Estes testes são essa contrapartida.

Eles também são o único lugar em que o SQL do app encontra as **views com
triggers `INSTEAD OF`** que o PowerSync cria de fato. Mock de `SqliteConnection`
compara o *texto* do SQL e não distingue SQL válido de SQL que o SQLite recusa —
foi assim que o `UPSERT` de orçamento passou meses quebrado com o teste verde.
Há um teste aqui que afirma essa recusa explicitamente, para a regra não voltar
a ser folclore.

## O que cobrem

- O schema local materializa uma tabela consultável para cada tabela do
  `appSchema`, e elas são **views**.
- `di/providers.dart` monta todos os repositories sobre o banco real.
- Categorias, lançamentos, orçamentos e contas: escrita, leitura reativa
  (`watch` emitindo após a escrita), edição e exclusão.
- Reorçar o mesmo mês substitui em vez de duplicar; mês novo cria linha nova.
- `balance_as_of` só se move quando o valor do saldo muda.
- `watchOwned` não devolve conta de outro dono (ADR 0004).
- A tabela `localOnly` de preferências, e o que `disconnectAndClear` leva junto.

## O que **não** cobrem, de propósito

**Connector, upload e Supabase.** Provar a ida ao Postgres exige rede,
credenciais e uma conta de teste — a suíte ficaria lenta e intermitente, e o CI
passaria a depender de um serviço externo. A fronteira de sessão entra como
mock; o que se prova aqui é a camada local.

A prova de que o upload chega ao Postgres continua sendo feita **à mão**, no
simulador, contra o ambiente de dev — é o passo que cada fatia registra no PR.
Automatizá-la exigiria um projeto Supabase só para teste, com dados
descartáveis; vale a pena quando houver mais de uma pessoa mexendo no repo.
