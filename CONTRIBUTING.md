# Contribuindo

O trabalho vem em **fatias verticais com contrato**. O fluxo, a arquitetura, a
escada de verificação e a Definição de Pronto estão em [`AGENTS.md`](AGENTS.md)
— este arquivo cobre só o que é específico de release.

## Fluxo, em uma linha

```bash
tool/new-slice.sh <nome>   # contrato + branch a partir de origin/main
#   preencher o contrato → executar → aprovar → gate → PR (draft até fechar)
tool/close-slice.sh        # fecha, e aí sim `gh pr ready`
```

## Commits

[Conventional Commits](https://www.conventionalcommits.org) no imperativo:
`feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`, `perf:`, `ci:`. O
corpo explica o *porquê* quando útil.

O versionamento é automatizado pelo Melos a partir deles: `fix:` → patch,
`feat:` → minor, `!`/`BREAKING CHANGE` → major. `docs:`/`chore:`/`ci:`/`test:`
não geram release.

## Releases

Preferencialmente pelo workflow **Release (version)** no GitHub Actions
(`workflow_dispatch`), que roda na `main`, versiona, gera CHANGELOGs, cria as
tags e faz push. O input `dry_run` pré-visualiza sem commitar.

Localmente, a partir da `main` atualizada:

```bash
fvm dart run melos version --all
git push --follow-tags origin main
```

> `--all` é necessário porque todos os pacotes são `publish_to: none`
> (privados) — o Melos os pularia por padrão. Nada é publicado no pub.dev.

Build e distribuição de artefatos (Android/iOS/web, lojas, OTA) são um passo
futuro, a ser adicionado quando houver app publicável.
