# ADR 0010 — Documentação em fatias com contrato

## Contexto

`docs/roadmap.md` chegou a **1.793 linhas** (117 KB). Ele era, ao mesmo tempo,
estado do projeto, diário de execução, inventário de 40 débitos, catálogo de
armadilhas e resposta às questões do PRD. Vinte e três seções começavam com
"Concluído na fatia …" — histórico que o `git log` já guarda melhor, porque lá
está atrelado ao diff que o produziu.

O custo era duplo e mensurável. Para uma sessão de agente, ler o roadmap inteiro
consumia orçamento de contexto antes de qualquer trabalho começar, e a instrução
"leia este arquivo até o fim" estava escrita nele. Para uma pessoa, achar o
estado atual exigia atravessar o histórico. Pior: as duas cópias divergiam — o
`README.md` ainda anunciava "fundação — sem UI de features" com treze features
implementadas.

O que **não** era problema: o conhecimento medido caro. A tabela-verdade da
direção de lançamento, a medição dos três furos de privilégio, a anatomia do
INSERT que some sem erro — tudo isso já vivia no cabeçalho do arquivo que a
regra morde, onde quem vai quebrá-la inevitavelmente passa.

## Decisão

Adotar o método de fatias com contrato. A documentação viva passa a ser quatro
arquivos com ciclo de vida declarado:

| Arquivo | Natureza | Limite |
|---|---|---|
| `docs/product.md` | domínio, invariantes, não-objetivos | muda quando o produto muda |
| `docs/surfaces.md` | telas, navegação, componentes | muda quando nasce superfície |
| `docs/state.md` | onde estamos · próximas 3 fatias · débitos · armadilhas | **reescrito** a cada fatia |
| `docs/adr/` | decisões caras de reverter | só cresce |

`AGENTS.md` descreve como trabalhar; `CLAUDE.md` aponta para ele em duas linhas.
O trabalho passa a vir em **fatias verticais com contrato**
(`tool/new-slice.sh` → `docs/slices/<nome>.md` → `tool/close-slice.sh`), e dois
guardas no CI impedem a regressão: `state.md` acima de 240 linhas falha, e
seção de histórico em documento vivo falha.

`docs/roadmap.md` é apagado. O que ele guardava se distribui: estado vai para
`state.md`, domínio para `product.md`, telas para `surfaces.md`, e o histórico
morre — continua acessível por `git show`, que é onde histórico pertence.

## Alternativas descartadas

- **Podar o roadmap e mantê-lo** — já foi tentado na prática, e ele voltou a
  crescer. Sem um guarda que falhe, a disciplina depende de força de vontade no
  pior momento: o fim da fatia, quando o que falta é abrir o PR.
- **Um `docs/debts.md` para os 40 débitos** — preservaria tudo intacto ao custo
  de um quinto documento sem limite de crescimento, que é exatamente o modo de
  falha que o método combate. Em vez disso: débito que já está documentado no
  arquivo que ele morde não se repete, e `state.md` fica só com o que é decisão
  consciente de postergar.
- **Reescrever o PRD como documento do repo** — o PRD é fonte de *o quê* e *por
  quê*, e envelhece devagar. `product.md` o destila no que muda decisão de
  código, e declara que vale sobre o PRD onde divergirem.

## Consequência

**Fica fácil** abrir sessão: três arquivos, ~250 linhas, e o contrato da fatia
diz o que fazer. Fica fácil dimensionar trabalho — o teste do "e" no "pronto
quando" quebra fatia antes de ela começar. E fica fácil confiar no documento
vivo, porque ele é curto o bastante para ser reescrito de verdade.

**Fica difícil** consultar o passado: quem quiser saber por que algo foi feito
tem que ler `git log`, não um markdown. Aceitamos esse custo de propósito — a
alternativa é a duplicação que já divergiu.

**O custo que aceitamos agora:** um degrau da escada de verificação está
faltando. O método pede um degrau 1 que o agente avalie sozinho, e para UI isso
é golden test — que não roda porque as fontes não estão empacotadas. Enquanto a
fatia `andaime-de-golden` não fechar, iteração de layout continua dependendo do
usuário olhar a tela.
