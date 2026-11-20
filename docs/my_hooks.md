# context.md: replicando os hooks Start, UserPromptSubmit e Stop

Documento escrito para outro Claude Code, em outra máquina, reproduzir a configuração de hooks desta máquina (macOS, usuário `renato.pereira`, Claude Code com modelo `sonnet[1m]`). Atualizado em 2026-11-20: todas as mensagens dos hooks (systemMessage, reason, additionalContext) e os gatilhos das skills passaram para en-US, o repositório público orenatobr/my_hooks virou a fonte dos scripts e a seção "LANGUAGE RULE" foi adicionada. Gerado em 2026-10-13 e atualizado em 2026-10-22 (hooks de Karpathy e de `/goal` mandam chamar a ferramenta `Skill`; nova skill `programming-best-practices`; juiz persiste no vault mesmo sem diff e sem goal; hook do patch do VS Code removido; ver seções 3 a 7) a partir do estado real de `~/.claude/` por um script, então os códigos do apêndice são cópias fiéis dos arquivos instalados (única alteração: travessão trocado por vírgula, por regra do usuário). Atualizado em 2026-10-25: o Stop passou a ser unificado em `quality-judge-stop.sh`, que em toda parada manda o modelo chamar as skills `/quality-gate` e `/llm-as-judge` (ver seções 1, 3, 6.1, 6.3, 6.4, 7 e o apêndice). Atualizado em 2026-10-26: novo hook `iterm-session-name.sh` no SessionStart, que define o Session Name do iTerm2 como o nome da pasta e fixa o Session Title em só Session Name pela API Python do iTerm2 (ver seções 1, 3, 4, 7, 8 e o apêndice). Atualizado em 2026-10-27: a skill `programming-best-practices` ganhou a regra 6 (logging em vez de `print`: logger por módulo, níveis, formatação lazy, `logger.exception`, nada de segredos nos logs); ver seção 4 e o apêndice. Atualizado em 2026-10-29: o nome da sessão do iTerm2 voltava errado após `/clear`; causa e correção (`set_allow_title_setting(False)` no `iterm-title-name.py`) na decisão 19 da seção 7. Atualizado em 2026-11-01: as skills passaram a ser carregadas só no `/goal` (o `karpathy-guidelines-hook.sh` saiu do UserPromptSubmit e não emite mais a instrução OBRIGATORIO no SessionStart; ver seções 1, 4, 5 e o apêndice). Atualizado em 2026-11-02: o `iterm-session-name.sh` passou a nomear a sessão pela pasta onde ela foi aberta (`CLAUDE_PROJECT_DIR`) em vez do `cwd` do payload, que seguia os `cd` do Claude e renomeava a sessão em `/clear` e `resume`; ver decisão 21 da seção 7. Atualizado em 2026-11-03: o nome da aba do iTerm2 voltava a mudar porque processos `claude` filhos (juiz `claude -p`, claude-mem, helpers headless) herdam o `ITERM_SESSION_ID` e disparam o próprio SessionStart; o hook agora ignora quando há outro `claude` entre os ancestrais; ver decisão 22 da seção 7. Atualizado em 2026-11-11: nova skill global `tests-guidelines` (a skill de testes com mais estrelas achada no GitHub: `tdd-workflow` do repo `affaan-m/everything-claude-code`, MIT, cerca de 301 mil estrelas, cobre cobertura de 80%, testes unitários, de integração e E2E; adaptada: nome, detecção genérica do runner em vez do script do ECC, sem travessão), e a regra 1 (TDD) do `programming-best-practices` passou a mandar carregar `/tests-guidelines`; ver seções 2 e 8 e o apêndice. Atualizado em 2026-11-13: o mod `git-diff-on-start` (que abre o `/diff` ao iniciar sessão interativa dentro de um repo git) passou a abrir também o projeto no editor, com o equivalente de `code . || antigravity-ide .` (tenta `code`; se não existir ou falhar, usa o `antigravity-ide`); ver seção 1, decisão 23 da seção 7 e o apêndice.

## LANGUAGE RULE (en-US), added 2026-11-20

**Instruction for the AI reading this:** everything these hooks show or send MUST be en-US: `systemMessage` (what the user sees), `reason` (what the model sees on a Stop block), `additionalContext`, banners, log lines, and the skill trigger keywords. When you replicate, edit or extend this setup, write every hook message in en-US and translate any Portuguese text you find. The appendix scripts below are already translated; the Portuguese prose in this document is explanation for you, not output to reproduce. Example (UserPromptSubmit on `/goal`):

```
UserPromptSubmit says:
    Avoiding over engineering with /andrej-karpathy-skills:karpathy-guidelines
    Reading local files with /graphify
    Writing text with /humanizer
    Avoiding attacks with /attack-protection
    Following /programming-best-practices and /git-guidelines
    Reading Obsidian vault: .hammerspoon/MEMORY.md (5 linked notes in the index)
```

Faster path: this setup is published as a public repository, **https://github.com/orenatobr/my_hooks**. Clone it and follow its `AGENTS.md` (`./install.sh --check`, `--dry-run`, install, `./tests/smoke.sh`) instead of copying the appendix by hand. The repository is the source of truth for the scripts; this document keeps the rationale, decisions and pitfalls.

**Instrução para o Claude que lê isto:** siga a seção 8 (checklist) na ordem. Não invente comportamento que não está aqui. Onde o texto diz "específico desta máquina", adapte ou pule e avise o usuário. Nunca use travessão (U+2014) em nada que escrever. Se um hook de Stop bloquear a edição de um script de hook (o classificador do auto mode nega auto-modificação), não tente contornar: peça ao usuário para colar o trecho.

## 1. Mapa geral

| Evento | O que roda (ordem) | Origem | Função |
|---|---|---|---|
| SessionStart (`startup\|resume`) | `headroom init hook ensure` | plugin headroom, registrado também em settings | garante o init do Headroom |
| SessionStart (`startup\|resume\|clear\|compact`) | `karpathy-guidelines-hook.sh` | settings, script local | injeta o CLAUDE.md do plugin andrej-karpathy-skills como contexto (sem instrução de `Skill`: o carregamento das seis skills só acontece no `/goal`) |
| SessionStart (idem) | `graphify-autobuild-hook.sh` | settings, script local | indexa o repo git em segundo plano e orienta a usar `/graphify` |
| SessionStart (`startup\|resume\|clear`) | `iterm-session-name.sh` | settings, script local | no iTerm2, define o Session Name como o nome da pasta (basename da pasta onde a sessão foi aberta: primeiro `cwd` do transcript, `CLAUDE_PROJECT_DIR` ou `cwd`; ignora `claude` aninhado, decisão 22; AppleScript) e o Session Title como só Session Name (`iterm-title-name.py`, API Python); sem `ITERM_SESSION_ID` não faz nada (específico, opcional) |
| SessionStart | `cc-status-safe.py` + `~/.config/iterm2/cc-status` | settings | barra de status no iTerm2 (específico, opcional) |
| SessionStart (mod `git-diff-on-start`) | `~/.claude/mods/git-diff-on-start/hooks/register.ts` | mod local, carregado por `CLAUDE_CODE_PLUGIN_DIRS` em `env` | em sessão interativa dentro de um repo git, no turno 0: roda `/diff` e roda `code .` com fallback para `antigravity-ide .` (decisão 23) |
| SessionStart (plugins) | superpowers `session-start`, claude-mem (contexto recente), security-guidance (`ensure_agent_sdk.py`), ponytail (modo ativo) | plugins | injetam skill `using-superpowers`, resumo de memória, lembretes de segurança, modo "lazy dev" |
| UserPromptSubmit | `goal-start-trigger.sh` | settings, script local | quando o prompt é `/goal`, reinjeta contexto (Karpathy, graphify, humanizer, attack-protection, diretrizes de código, MEMORY.md do vault) e manda o modelo chamar a `Skill` das seis skills |
| UserPromptSubmit (plugins) | claude-mem, security-guidance `security_reminder_hook.py` | plugins | observações e lembretes |
| Stop | 1. `pr-lint-stop.sh` (30s) | settings, script local | lint determinista dos PRs criados na sessão |
| Stop | 2. `quality-judge-stop.sh` (15s) | settings, script local | em TODO Stop manda o modelo chamar `/quality-gate` e depois `/llm-as-judge`; só libera com `gate.json` e `judge.json` aprovados neste turno; em tarefa de código faz 3 perguntas git (commit, branch, PR) e depois manda persistir no vault. Substitui `feedback-loop-stop.sh` e `fable-judge-stop.sh` desde 2026-10-25 |
| **Skill** `/quality-gate` | chamada pelo modelo a pedido do Stop | `~/.claude/skills/quality-gate`, script `quality-gate.sh` | checagens determinísticas: schema, lint/tipos/testes, pre-commit, segredos |
| **Skill** `/llm-as-judge` | idem, só depois do gate | `~/.claude/skills/llm-as-judge`, script `llm-judge.sh` | juiz Fable 5.1 (fallback Opus 5.5), nota 0 a 10, limiar 7 |
| Stop | `cc-status-safe.py`, `cc-status` | settings | iTerm2 (opcional) |
| Stop (plugins) | claude-mem, security-guidance | plugins | resumo da sessão e lembretes |
| **Apoio** PreToolUse | `pr-gate-pretool.py` | settings, script local | impede commit/push/PR fora do /git-guidelines (é o que faz o Stop de PR quase nunca precisar agir) |
| **Apoio** PostToolUse (`Edit\|Write\|MultiEdit`) | `feedback-loop.sh` | settings, script local | mesma checagem do loop, logo após cada edição |

O `/goal` é um recurso nativo do Claude Code: ele cria um **hook Stop da sessão, baseado em prompt**, e injeta no contexto o texto `A session-scoped Stop hook is now active with condition: "<objetivo>"`. Esse hook nativo não aparece em `settings.json`. O `fable-judge-stop.sh` depende desse texto exato (ele o procura no transcript para descobrir o objetivo).

## 2. Pré-requisitos na máquina nova

- `jq`, `python3` (3.9+), `git`, `gh` (autenticado), `bash`. Opcionais: `graphify` (CLI), `pre-commit`, `pytest`, `ruff`, `mypy`, `gitleaks` (sem ele o `quality-gate.sh` usa uma varredura por regex).
- A CLI `claude` no PATH, com acesso ao modelo `claude-fable-5-1` (usado como juiz via `claude -p`). Sem acesso ao Fable, o juiz cai no fallback `claude-opus-5-5` (mesmo CLI, sem configuração extra); só se os dois falharem libera a parada (ver 6.3).
- `timeout`: o macOS não traz. Aqui ele vem do coreutils do Homebrew (`/opt/homebrew/bin/timeout`, também `gtimeout`) e o `fable-judge-stop.sh` o chama; na máquina nova rode `brew install coreutils` e garanta `/opt/homebrew/bin` no PATH dos hooks (ou troque por `gtimeout`). O `feedback-loop-lib.sh` não depende disso: tem um `run_with_timeout` próprio (escrito quando a máquina ainda não tinha `timeout`).
- Cuidado com PATH: um `~/.zshenv` que roda antes de o PATH ser montado quebra comandos sem caminho absoluto (aqui `gh` é resolvido por `shutil.which` com fallback `/opt/homebrew/bin/gh`).
- Plugins e marketplaces (de `settings.json`):
  - marketplaces: `karpathy-skills` (github `multica-ai/andrej-karpathy-skills`), `ponytail` (`DietrichGebert/ponytail`), `thedotmack` (`thedotmack/claude-mem`), `headroom-marketplace` (`chopratejas/headroom`), além do `claude-plugins-official`.
  - plugins ativos: `andrej-karpathy-skills@karpathy-skills`, `atlassian`, `chrome-devtools-mcp`, `commit-commands`, `github`, `playwright`, `security-guidance`, `superpowers` (todos `@claude-plugins-official`), `claude-mem@thedotmack`, `headroom@headroom-marketplace`, `ponytail@ponytail`. Os plugins `@synced` estão desligados.
- Skills locais usadas pelos hooks: `git-guidelines`, `attack-protection`, `programming-best-practices`, `tests-guidelines`, `quality-gate` e `llm-as-judge` (fontes no apêndice, escritas nesta máquina), `humanizer` e `graphify` (de terceiros, instale do upstream; os hooks só mandam invocá-las).
- Vault Obsidian (convenção do `~/.claude/CLAUDE.md` do usuário): `~/Documents/Obsidian Vault/<pasta>/MEMORY.md`, com `<pasta>` = basename do diretório de trabalho (`renato` para `~`). `goal-start-trigger.sh` lê esse arquivo e o `fable-judge-stop.sh` manda gravar notas nele. Sem o vault, o primeiro apenas avisa "sem MEMORY.md" e o segundo ainda pede para persistir (adapte o caminho ou desligue essa parte).
- Itens específicos desta máquina que você deve **adaptar ou pular**: `CC_STATUS` em `cc-status-safe.py` (caminho absoluto `/Users/renato.pereira/.config/iterm2/cc-status`, exige `ITERM2_COOKIE`/`ITERM2_KEY`), e todos os caminhos `/Users/renato.pereira` em `settings.json`.

## 3. Bloco de hooks do settings.json (sanitizado, `$HOME` no lugar do caminho do usuário)

Este é o JSON atual, com `env` e `hooks`. Mescle no `~/.claude/settings.json` da máquina nova sem apagar chaves existentes. Em `hooks`, cada item de evento é um grupo `{matcher?, hooks:[{type:"command", command, timeout}]}`; todos os grupos de um evento rodam.

```json
{
  "env": {
    "ENABLE_TOOL_SEARCH": "true",
    "CLAUDE_CODE_ENABLE_FUNCTION_HOOKS": "1",
    "CLAUDE_CODE_PLUGIN_DIRS": "$HOME/.claude/mods/git-diff-on-start",
    "PLAYWRIGHT_MCP_BROWSER": "chromium",
    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
  },
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/feedback-loop.sh",
            "timeout": 180
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|mcp__plugin_github_github__create_pull_request|mcp__plugin_github_github__update_pull_request",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/pr-gate-pretool.py",
            "timeout": 30
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/headroom init hook ensure --profile init-user --marker headroom-init-claude",
            "timeout": 15
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/headroom init hook ensure --profile init-user --marker headroom-init-claude",
            "timeout": 15
          }
        ]
      },
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/karpathy-guidelines-hook.sh",
            "timeout": 15
          }
        ]
      },
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/graphify-autobuild-hook.sh",
            "timeout": 15
          }
        ]
      },
      {
        "matcher": "startup|resume|clear",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/iterm-session-name.sh",
            "timeout": 10
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/pr-lint-stop.sh",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/quality-judge-stop.sh",
            "timeout": 15
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/goal-start-trigger.sh",
            "timeout": 15
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/cc-status-safe.py",
            "timeout": 30
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/iterm2/cc-status"
          }
        ]
      }
    ]
  }
}
```

Notas: `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`, `ENABLE_TOOL_SEARCH=true`, `PLAYWRIGHT_MCP_BROWSER=chromium` (o Playwright MCP usa Chromium) e `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` (tentativa inicial da decisão 19; a correção que funciona é o `set_allow_title_setting(False)` do `iterm-title-name.py`) ficam em `env`. `CLAUDE_CODE_PLUGIN_DIRS` aponta para um mod local (`~/.claude/mods/git-diff-on-start`, fonte no apêndice), específico desta máquina. Outras chaves relevantes do settings: `attribution: {commit: "", pr: ""}` (sem coautoria do Claude em commits e PRs), `enableWorkflows: true`, `autoCompactEnabled: true`, `useAutoModeDuringPlan: false`.

## 4. SessionStart em detalhe

Semântica: o hook recebe um JSON no stdin e, para injetar contexto no modelo, imprime `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}`. `systemMessage` aparece só para o usuário.

1. **`karpathy-guidelines-hook.sh`**: acha a versão mais nova de `~/.claude/plugins/cache/karpathy-skills/andrej-karpathy-skills/*/CLAUDE.md` (`sort -V | tail -1`) e entrega o arquivo inteiro como `additionalContext` (`jq -Rs`). Se o plugin não estiver instalado, sai em silêncio. Resultado: as quatro diretrizes (pensar antes de codar, simplicidade, mudanças cirúrgicas, execução guiada por objetivo) valem desde o primeiro turno. **Desde 2026-11-01 ele roda só no SessionStart e não manda mais o modelo chamar a ferramenta `Skill`.** Antes (2026-10-22 a 2026-10-31) ele também estava registrado em UserPromptSubmit e prefixava o `additionalContext` com uma instrução OBRIGATORIO para chamar as seis skills (`andrej-karpathy-skills:karpathy-guidelines`, `graphify`, `humanizer`, `attack-protection`, `programming-best-practices`, `git-guidelines`); por isso uma mensagem comum disparava o carregamento de todas as skills, contra a intenção do usuário, que quer as skills carregadas só quando usa `/goal`. Correção: o hook saiu do UserPromptSubmit no `settings.json` e o script sai com exit 0 se `hook_event_name` for UserPromptSubmit (defesa caso alguém o registre de novo). A única instrução OBRIGATORIO que sobra está no `goal-start-trigger.sh`, que chama este script sem stdin (cai no caminho SessionStart, com `KARPATHY_NO_INSTR=1`) só para reaproveitar o contexto do CLAUDE.md. Ele lê `hook_event_name` do stdin e devolve o `hookEventName` certo; sem stdin assume SessionStart. Um hook não consegue invocar a `Skill` por conta própria: no `/goal` a chamada depende de o modelo obedecer, então confira o aviso nativo `Skill(...) Successfully loaded skill` em cada `/goal`.
2. **`graphify-autobuild-hook.sh`**: só roda se a CLI `graphify` existir e se o cwd estiver num repo git. Se já existe `graphify-out/graph.json`, orienta a usar `/graphify query` antes de grep/find. Se não existe, dispara `graphify <raiz> --code-only` em segundo plano (`nohup`, log em `.graphify-autobuild.log`, sem chave de API) e avisa que o índice pode não estar pronto neste turno.
3. **Headroom**: `headroom init hook ensure --profile init-user --marker headroom-init-claude` (timeout 15). O plugin `headroom` registra o mesmo; instalar o plugin e manter a entrada em settings reproduz o efeito.
4. **Plugins** (nada para copiar, vêm da instalação):
   - `superpowers` (`hooks/run-hook.cmd session-start`) injeta a skill `using-superpowers` (regra de invocar skills antes de agir).
   - `claude-mem` injeta "recent context" (observações de sessões passadas) e tem hooks em UserPromptSubmit/PostToolUse/Stop.
   - `security-guidance` roda `ensure_agent_sdk.py` e depois lembretes de segurança em vários eventos.
   - `ponytail` ativa o modo "lazy senior dev" (nível `full`).
5. **`iterm-session-name.sh`** (2026-10-26): só no iTerm2. Nomeia pela pasta onde a sessão foi aberta (primeiro `cwd` do transcript, depois `CLAUDE_PROJECT_DIR`, depois o `cwd` do JSON do stdin e `$PWD`; no `clear` vale o nome guardado em `~/.claude/state/iterm-names/<uuid>`; decisão 21), acha a sessão pelo UUID em `ITERM_SESSION_ID` (parte depois dos dois pontos) e faz `set name` por AppleScript com o basename da pasta. Em seguida chama `~/.claude/venvs/iterm2/bin/python ~/.claude/scripts/iterm-title-name.py <uuid>` (`timeout 8`), que põe o Title da sessão em só Session Name (decisão 18 da seção 7). Sem `ITERM_SESSION_ID` sai com 0 sem fazer nada; sem o venv ou sem a API ligada pula só o Title. Também sai sem renomear quando o próprio `claude` que disparou o hook tem outro `claude` entre os ancestrais, ou seja, é um processo filho (decisão 22); o log registra `skipped=nested-claude(N)` e agora inclui o `uuid` da aba. Verificado com sessões reais do `claude -p`: com o nome forçado para outro valor e o Title forçado para Name+Job, `startup` (pasta nova) e `resume` (`claude -p --continue`) devolveram o nome da pasta e `[SESSION_NAME]`. Cada execução do hook grava uma linha em `~/.claude/logs/iterm-session-name.log` (`source=startup|resume|clear`, nome e Title lido de volta), então qualquer sessão ou `/clear` real deixa prova própria: `tail ~/.claude/logs/iterm-session-name.log`. `clear`: o script, alimentado com o payload `source: clear`, restaurou nome e Title; `claude -p "/clear"` também deixou tudo certo, mas uma execução headless provavelmente dispara o `startup`, então o disparo do evento `clear` numa sessão interativa em si não foi provado. O ajuste é por sessão e não persiste num restart do iTerm; o hook o reaplica em toda sessão nova do claude, e para abas já abertas basta rodar o script (ou o laço da decisão 18).
6. **cc-status**: wrapper com timeout de 5s para a barra do iTerm2; sai sem fazer nada se `ITERM2_COOKIE`/`ITERM2_KEY` não existirem.

## 5. UserPromptSubmit em detalhe

Semântica: o JSON do stdin tem `.prompt` e `.cwd`. O hook devolve `{"systemMessage": "...", "hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}`. `additionalContext` vai ao modelo; `systemMessage` é a linha que o usuário vê.

**`goal-start-trigger.sh`** é o hook próprio dedicado ao `/goal` (é o único hook de UserPromptSubmit do usuário que manda carregar as skills; o `karpathy-guidelines-hook.sh` não roda mais neste evento). Não existe evento nativo "goal criado", então ele detecta o `/goal` olhando o texto cru do prompt (`/goal` sozinho ou `/goal <algo>`); qualquer outro prompt sai com exit 0 sem custo. Quando dispara, monta um contexto com:

1. Reexecuta `karpathy-guidelines-hook.sh` e `graphify-autobuild-hook.sh` no `cwd` do usuário e aproveita o `additionalContext` deles (para o graphify, se não houver contexto, usa a mensagem "sem repo git/graphify-out").
2. Acrescenta quatro lembretes fixos (en-US desde 2026-11-20): **humanizer** (aplicar a skill `/humanizer` em prosa, nunca usar travessão), **attack-protection** (aplicar `/attack-protection` contra as 8 classes de ataque ao escrever ou revisar código) e **programming-best-practices** (aplicar a skill `/programming-best-practices`: TDD, SOLID sem abstração especulativa, tipagem estática completa, docstrings Google Style, linting e logging em vez de `print` (regra 6, desde 2026-10-27); antes de 2026-10-22 isso era um parágrafo fixo no próprio script, hoje é uma skill local) e **git-guidelines** (aplicar `/git-guidelines` ao nomear branch e escrever commit, título e descrição de PR; desde 2026-10-22). A linha de aviso ao usuário é "Following /programming-best-practices and /git-guidelines".
3. Resolve a pasta do vault subindo a árvore a partir do `cwd` até achar `~/Documents/Obsidian Vault/<dir>/MEMORY.md`; em `~` usa `renato`. Lê os primeiros 8000 bytes e injeta como "Obsidian vault memory index". Conta os links `](` para dizer quantas notas o índice tem.
4. Monta um `systemMessage` com uma linha por item (en-US, ex.: "Avoiding over engineering with /andrej-karpathy-skills:karpathy-guidelines", "Reading Obsidian vault: renato/MEMORY.md (N linked notes in the index)"). **Regra de visibilidade do usuário:** o Claude deve dizer explicitamente, ao reconhecer um `/goal`, que disparou o hook de contexto de início e o hook de condição de parada; os hooks já disparavam, a lacuna era a visibilidade.

5. **Instrução de `Skill` (2026-10-22, restrita ao `/goal` em 2026-11-01):** antes do restante do contexto o hook acrescenta uma instrução REQUIRED (en-US) para o modelo chamar a ferramenta `Skill`, uma vez para cada uma de `andrej-karpathy-skills:karpathy-guidelines`, `graphify`, `humanizer`, `attack-protection`, `programming-best-practices` e `git-guidelines` (seis chamadas), antes de qualquer outra ação. O usuário confere pelo aviso nativo `Skill(...) Successfully loaded skill`; o modelo não deve escrever esse aviso em texto. Sem garantia dura: o hook só instrui, quem chama é o modelo. Se a skill já estiver carregada na sessão, a ferramenta responde "already loaded" e não mostra o aviso de novo. Esta é a única instrução de `Skill` do setup: prompts comuns e SessionStart não a recebem (correção de 2026-11-01).

Por que esse hook existe: um objetivo novo deve receber o mesmo ancoramento de contexto de uma sessão nova (`/clear` não reexecuta tudo, e o `/goal` troca o foco do trabalho). Observação: a contagem "N notas" vem do índice dinâmico, não de um número fixo; um número fixo em uma condição de goal causou um bloqueio de conclusão nesta máquina (condição dizia 8, índice tinha 10).

Plugins em UserPromptSubmit: `claude-mem` e `security-guidance` (`security_reminder_hook.py`). Nada a copiar.

## 6. Stop em detalhe

Semântica do evento Stop: o hook recebe JSON com `transcript_path`, `session_id`, `cwd`, `stop_hook_active`. Para **bloquear** a parada e fazer o Claude continuar, imprima `{"decision":"block","reason":"<instrução ao modelo>","systemMessage":"<texto ao usuário>"}` com exit 0; ou escreva no stderr e saia com exit 2. Exit 0 sem JSON libera. Todos os hooks do grupo rodam; qualquer bloqueio mantém a sessão viva. Cada hook abaixo tem **válvula de segurança** (limite de rodadas) para nunca prender a sessão para sempre.

### 6.1 `feedback-loop-stop.sh` (+ `feedback-loop-lib.sh`, `feedback-loop.sh`)

**Legado desde 2026-10-25:** o `feedback-loop-stop.sh` não está mais registrado em Stop (continua no disco para rollback). A checagem de lint/tipos/testes agora é o check `lint-types-tests` do `quality-gate.sh` (seção 6.3), que faz `source` de `feedback-loop-lib.sh` e chama `find_project_root` e `run_checks`. A lib e o `feedback-loop.sh` (PostToolUse) seguem em uso. O texto abaixo descreve o comportamento original.

Acha a raiz do projeto subindo a partir do cwd (marcadores `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`; para em `$HOME`). Roda os comandos do próprio projeto: npm (`lint`, `typecheck`/`type-check` ou `tsc --noEmit`, `test`), Python (ruff se configurado, mypy se configurado, pytest se houver `[tool.pytest]` ou `tests/`), Go (`vet`, `build`, `test`), Rust (`check`, `test`). Cada comando tem timeout de 90s (implementação própria, sem `timeout`). Se falhar, escreve a saída (últimos 4000 bytes) no stderr e sai com **exit 2**, o que bloqueia a parada. Se `stop_hook_active` for `true` ele sai com 0 (já está em loop de Stop: não força loop infinito). `feedback-loop.sh` é a mesma checagem como **PostToolUse** em `Edit|Write|MultiEdit`, ignorando `node_modules`, `.git`, `dist`, `build`, `.venv`.

### 6.2 `pr-lint-stop.sh` + `pr_lint.py` + `pr-gate-pretool.py` (conformidade de PR)

Problema que resolveu: um PR saiu com cabeçalho de commit de 136 caracteres e sem corpo, só detectado depois do push (force push é vetado), o que obrigou a refazer o PR; e o antigo Stop de "checagem visual no Chrome" seguia cobrando um PR já fechado por 3 rodadas. A solução tem três peças e **substituiu por completo** o antigo `pr-visual-check-stop.sh` (apagado; não existe mais marcador `PR-VISUAL-CHECK: OK` nem inspeção no Chrome).

- **`pr_lint.py`** (fonte única das regras do /git-guidelines): título no formato Conventional Commits `type(scope): resumo imperativo`, até 72 caracteres, sem ponto final e sem travessão; corpo contendo todas as seções do template (`.github/PULL_REQUEST_TEMPLATE.md` ou `pull_request_template.md` do repo; senão o bloco ` ```markdown ` sob `## PR description` do `~/.claude/skills/git-guidelines/SKILL.md`) na mesma ordem, nenhuma vazia (exceto seções "if applicable/optional"), sem `TODO(fill)`, com ao menos um checkbox marcado em "Type of change"; cada commit com cabeçalho válido (72) e corpo não vazio; branch `<type>/[<TICKET>-]<kebab>` (ticket opcional, sem detecção por repo). O **scope é obrigatório** no cabeçalho de commit e no título de PR (`feat(auth): ...`; `feat: ...` é recusado). Decidido em 2026-10-22: a regex antiga tinha o scope opcional e o repo `publish-shorts` (PRs #134 a #148, sem scope) passava; o bump automático de versão (`chore: bump version ...`, branch `chore/bump-*`) vem de CI e não passa pelo gate, então seus títulos continuam sem scope. Mais de 400 linhas alteradas só gera aviso. CLI: `pr_lint.py url <url|num>` sai 0 se OK **ou se o PR não estiver OPEN**, 1 se houver erros. Também gera o esqueleto de corpo pré-preenchido (`skeleton()`).
- **`pr-gate-pretool.py`** (PreToolUse, matcher `Bash|mcp__plugin_github_github__create_pull_request|mcp__plugin_github_github__update_pull_request`): bloqueia com exit 2 e a lista de correções no stderr: `git commit -m` com cabeçalho/corpo inválido; `git push` com commits locais inválidos (última chance antes de virar irreversível, ignora delete/tags/branch default); `gh pr create|edit` e as ferramentas MCP de PR. Entende `-m` múltiplo, `-am` e heredoc `$(cat <<'EOF' ... EOF)`. **`updatedInput`** só para correção mecânica (travessão vira vírgula, ponto final do título MCP removido) e retorna `permissionDecision:"allow"` (atenção: isso pula o prompt de permissão daquele comando). Corpo ausente ou incompleto é **negado** com o caminho de um arquivo-template pré-preenchido em `$TMPDIR/pr-body-*.md` (campos que ninguém além do autor sabe, como "How to test" e "Risks and rollback", ficam `TODO(fill)` e o linter os recusa até serem preenchidos; nada é inventado).
- **Template de commit exigido pelo PreToolUse** (`gate_commit` em `pr-gate-pretool.py`, regras em `pr_lint.lint_header`): todo `git commit -m ...` precisa seguir o template do /git-guidelines (o scope é obrigatório), senão sai com `rc=2` e a lista de erros no stderr, e o commit não acontece. O template é: cabeçalho `type(scope): resumo imperativo` com scope obrigatório (types `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert`, até 72 caracteres, sem ponto final), linha em branco, corpo explicando o quê e o porquê, e nenhum travessão em cabeçalho ou corpo. Os vários `-m` são juntados com linha em branco, então `-m "feat(x): add thing" -m "Explica o porquê."` passa. Ficam fora da checagem: `Merge ...`, commit sem `-m` (editor, `-F`, `--no-edit`) e comando que o parser não consegue ler (falha aberta). O gate não reescreve mensagem de commit (sem `updatedInput`), só bloqueia. Medido em 2026-10-22 com payloads sintéticos: `update stuff` dá `rc=2` (cabeçalho e corpo), `feat(x): add thing` sem corpo dá `rc=2`, com corpo dá `rc=0`. O `git push` repete a mesma checagem nos commits locais ainda não enviados (`lint_commits`).
- **`pr-lint-stop.sh`** (Stop): varre o transcript atrás das URLs de PR criados/editados na sessão (`gh pr create|edit`, `create_pull_request`, `update_pull_request`), roda `pr_lint.py url` em cada uma e bloqueia com a lista de erros se algum falhar. PR fechado/mergeado é ignorado. Resultado vem do exit code, não de texto escrito pelo modelo. Válvula: 3 rodadas (estado em `/tmp/pr-lint-round-<session>`).

### 6.3 `quality-judge-stop.sh` + `quality-gate.sh` + `llm-judge.sh` (Stop unificado, desde 2026-10-25)

Em **todo** Stop (decisão do usuário: "sempre bloquear", inclusive em pergunta conceitual) o hook manda o modelo executar duas skills, nesta ordem, e só libera quando há evidência de que as duas passaram **neste turno**. Um hook não carrega skill, então ele bloqueia e instrui o modelo a chamar a ferramenta `Skill`; o resultado nunca vem de texto do modelo, vem de arquivos que os scripts gravam em `/tmp/qjs-<session>/`.

- **`quality-gate.sh`** (skill `/quality-gate`): checagens determinísticas, rápidas e sem LLM, sobre os arquivos alterados (`git diff --name-only HEAD` mais não rastreados) e o projeto do cwd. Checks: `schema` (json via `jq`, yaml e toml via python, só sintaxe; `tsconfig*`, `jsconfig*`, `.jsonc`, `.eslintrc*` e `.vscode/*` são pulados porque aceitam comentário), `lint-types-tests` (a lib `feedback-loop-lib.sh`), `pre-commit` (`--files` só dos alterados) e `secrets` (`gitleaks` se existir, senão regex para AKIA, `ghp_`, `github_pat_`, `sk-`, `xox*`, `AIza`, `PRIVATE KEY`, e `.env` versionado; nunca imprime o valor achado, só arquivo e linha). Cada check é `ok`, `fail` ou `na`; sem projeto e sem diff tudo é `na` e o gate passa. Grava `gate.json` (`{turn, pass, checks, ts}`) e sai 0 ou 1.
- **`llm-judge.sh`** (skill `/llm-as-judge`): sai com **3 sem chamar modelo** se não houver `gate.json` aprovado do mesmo turno (a ordem é imposta por código). Escolhe a evidência: `diff` (git diff, prompt com `/code-review` e "faz o que o pedido diz?"), `goal` (condição de `/goal` ativa) ou `response` (último pedido do usuário contra a última resposta: segue o pedido? o tom está certo?). Juiz `claude -p --model claude-fable-5-1` com `FABLE_JUDGE_ACTIVE=1`, fallback uma vez para `claude-opus-5-5` se o Fable estiver indisponível (resposta vazia, timeout, ou texto de limite sem `SCORE`), limiar 7, `JUDGE_TIMEOUT=60` por chamada, uma nova tentativa se a resposta for ilegível (aí `pass:false` com `judge-raw.txt`). Os dois indisponíveis: fail open (`judge:"unavailable"`, `pass:true`). Grava `judge.json` (`{turn, mode, score, pass, judge, feedback}`).
- **`qjs_transcript.py`**: consultas ao transcript usadas pelo hook e pelo juiz (`turn`, `request`, `response`, `edits`, `goal`). O id do turno é o `promptId` da última entrada `user` do transcript, que todas as entradas do turno compartilham (ver decisão 14 da seção 7).
- **`quality-judge-stop.sh`** (hook, timeout 15 porque só lê arquivos; o juiz roda no Bash do modelo): sai 0 se `FABLE_JUDGE_ACTIVE=1`. Máquina de estados a cada Stop: (1) sem `gate.json` do turno: bloqueia com os comandos exatos (`--state`, `--turn`, `--transcript`, `--cwd`) e as duas linhas "Running quality gate with /quality-gate" e "Running llm-as-judge with /llm-as-judge # Usando Fable 5.1 com fallback para Opus 5.5."; (2) gate reprovado: bloqueia e volta a iterar; (3) gate ok sem juiz: bloqueia mandando chamar `/llm-as-judge`; (4) juiz reprovado (nota < 7): bloqueia, apaga `gate.json` e `judge.json` para os dois rodarem de novo, e itera com o modelo da sessão (Sonnet 5.5 [1M]); (5) os dois ok e tarefa de código (repo git com `git status` não vazio ou Edit/Write no turno): bloqueia **uma vez** mandando fazer 3 perguntas em uma chamada de `AskUserQuestion` (commit? branch? PR?) com `/git-guidelines` obrigatório; fora disso pula; (6) bloqueia **uma vez** mandando persistir os achados no vault (flag por turno quando algo foi checado, por sessão nos turnos vazios); (7) libera com um resumo do gate e da nota. Válvulas: 3 rodadas de falha ou 8 bloqueios no turno liberam com aviso.
- Estado em `/tmp/qjs-<session>/`: `turn`, `gate.json`, `judge.json`, `judge-raw.txt`, `fail_rounds`, `blocks`, `git_asked`, `persisted_turn`, `persisted_session`.
- Ainda **não** registrado em `permissions.allow`: `Bash(/Users/renato.pereira/.claude/scripts/quality-gate.sh:*)` e `Bash(/Users/renato.pereira/.claude/scripts/llm-judge.sh:*)` são opcionais (evitam prompt de permissão); o classificador do auto mode negou essa edição como auto-modificação, então o usuário cola as duas linhas se quiser.

### 6.3b `fable-judge-stop.sh` (legado, não registrado desde 2026-10-25; histórico das decisões)

O que está abaixo descreve o hook antigo. A lógica de juiz (Fable com fallback Opus, `parse_score`, `judge_unavailable`, prompts de diff e goal) foi movida para o `llm-judge.sh`; a de persistência no vault e git virou os passos 5 e 6 do `quality-judge-stop.sh`.

Antes de o Claude encerrar o turno, um **outro modelo** (`claude -p --model claude-fable-5-1`) avalia o trabalho:

- **Modo diff**: se o cwd é um repo git com `git diff HEAD` não vazio (máx. 20 KB), o juiz procura bugs reais de correção. Desde 2026-10-21 o prompt manda o juiz usar o skill `/code-review` sobre o diff (ainda não exercitado em execução real).
- **Modo goal**: sem diff, mas com `/goal` ativo, o hook extrai do transcript o objetivo (texto após `A session-scoped Stop hook is now active with condition: "`) e os **últimos** 20 KB de texto/ações do assistente desde então (o fim do trecho, `[-CAP:]`), e o juiz avalia se o objetivo foi cumprido. *Correção de 2026-10-21:* antes o hook guardava os **primeiros** 20 KB e parava ao atingir o limite (`break`), então em sessão longa o juiz só via o início, quando o trabalho ainda estava bloqueado, e julgava um estado antigo. Agora ele vê o trabalho mais recente.
- Sem diff e sem goal: não há o que julgar, mas desde 2026-10-22 o hook ainda bloqueia **uma vez** por sessão (flag `/tmp/fable-judge-persisted-<session>`, que não é apagada nesse caminho) pedindo ao Claude para persistir os findings no vault (`vault_folder()` resolve a pasta, `~` vira `renato`); na segunda passagem libera com a mensagem "findings já persistidos nesta sessão". Sessão sem nada a guardar: o Claude pula e para de novo.
- Formato exigido da resposta: `SCORE: <0-10>` e `FEEDBACK: ...`. Limiar `THRESHOLD=7`, `MAX_ROUNDS=3`, `JUDGE_TIMEOUT=60`. Abaixo do limiar bloqueia e devolve o veredito para o modelo iterar; ao atingir 3 rodadas libera (válvula).
- Na aprovação (primeira vez na sessão, flag em `/tmp/fable-judge-persisted-<session>`) o hook bloqueia **uma vez** instruindo o próprio Claude da sessão a: rodar pre-commit (se houver `.pre-commit-config.yaml`), rodar testes (pytest, `npm test` ou `make test`), persistir os achados no vault Obsidian (`~/Documents/Obsidian Vault/<pasta>`, frontmatter padrão, atualizar notas existentes e o `MEMORY.md`) e, se for repo git com mudanças, seguir o `/git-guidelines` (branch, commits, push, PR; nunca commitar na default, sem atribuição ao Claude, sem travessão, sem force push). Depois pare de novo e então libera.
- Guarda de recursão: o `claude -p` do juiz também passa pelo Stop; `FABLE_JUDGE_ACTIVE=1` faz todos os hooks de Stop próprios saírem na hora.
- **Tratamento de falhas (versão atual):** resposta vazia/timeout, e mensagem de limite de uso ou indisponibilidade do serviço sem nenhum `SCORE` (regex: `reached your .*limit|usage limit|rate limit|overloaded|credits|try again later`), liberam a parada (fail open). A condição exige a ausência de `SCORE`, para um veredito legítimo que cita "rate limit" não ser confundido com falha. Resposta com texto mas sem `SCORE` parseável: 1 nova tentativa (regex tolerante a `**Score:** 8/10`); se continuar ilegível, **bloqueia como rodada contada** e grava a resposta crua em `/tmp/fable-judge-raw-<session>.txt` (a válvula de 3 rodadas ainda libera). Havia antes um fail open cego para "ilegível", que mascarava falhas reais.
- **Fallback para Opus 5.5:** o juiz primário é `claude-fable-5-1`. Se ele estiver indisponível (resposta vazia/timeout, ou texto de limite/outage sem `SCORE`), o hook refaz a mesma chamada **uma vez** com `claude-opus-5-5` (`FALLBACK_MODEL`) e segue o fluxo normal (nota, limiar, rodadas, persistência), com as mensagens ao usuário mostrando "Opus 5.5" em vez de "Fable 5.1" (variável `judge_name`). Só se o Opus também estiver indisponível o hook libera a parada (fail open), com a mensagem "Fable and fallback Opus 5.5 both unavailable". A detecção de indisponibilidade é a função `judge_unavailable`, a mesma regex de antes. Resposta ilegível do Fable (com texto, sem `SCORE`, sem cara de limite) **não** aciona o fallback: continua sendo a rodada contada descrita acima.
- `systemMessage` é emitido em todos os caminhos (inclusive os silenciosos) para o usuário sempre ver que o hook rodou.

### 6.4 Ordem e interação

Ordem em settings: pr-lint, quality-judge, cc-status. Dentro do `quality-judge`, a ordem gate antes do juiz é imposta por código: `llm-judge.sh` sai com 3 sem chamar modelo se não houver `gate.json` aprovado do mesmo turno. Estados em `/tmp/qjs-<session>/` (lista na seção 6.3) e `/tmp/pr-lint-round-<session>`. Para resetar um ciclo preso, apague a pasta `/tmp/qjs-<session>/`.

## 7. Decisões e armadilhas já vividas (leia antes de mexer)

1. **Validar antes, não depois.** Qualquer regra que só pode ser checada após o push (comprimento do commit, corpo) vira retrabalho porque força push é vetado. Por isso o gate PreToolUse bloqueia `git commit` e `git push`.
2. **Não confie em "OK" escrito pelo modelo.** O hook antigo exigia o texto `PR-VISUAL-CHECK: OK <url>`; o modelo o escrevia mesmo para PR não conforme. Passa/falha vem do exit code do linter.
3. **Estado do PR importa.** Sempre consultar `state` (`OPEN`) antes de cobrar algo; PR substituído fica fechado e não deve gerar bloqueio.
4. **`updatedInput` exige `permissionDecision`.** Usar só para correções mecânicas e saber que ele pula o prompt de permissão. Reescrever uma linha de comando com heredoc é frágil; por isso só se troca travessão.
5. **`sed -i` do macOS (BSD)** exige argumento de sufixo (`sed -i ''`); use Python para editar arquivos em scripts de manutenção.
6. **Fail open vs fail closed.** Indisponibilidade do juiz (limite de uso, timeout) deve primeiro cair no modelo de fallback (Opus 5.5) e só então liberar; resposta malformada deve contar rodada. Diferenciar os dois evitou 3 rodadas perdidas quando o Fable atingiu o limite de uso.
7. **O classificador do auto mode nega que o agente edite seus próprios hooks de Stop** ("Self-Modification"). Quando acontecer, não contorne: entregue o trecho ao usuário para colar no arquivo e depois valide com `bash -n` e testes sintéticos. Um comando solto no shell (`!`) não edita arquivo nenhum.
8. **Testar sem rede e sem PR real.** O gate foi testado com payloads JSON sintéticos num repo git temporário (commit ruim, sem corpo, heredoc, dois `-m`, `gh pr create` sem corpo, travessão no título, `gh pr edit` com título ruim, MCP create/update, push com commit ruim e push de delete). O Stop de PR foi testado com um transcript falso apontando para PRs fechados/mergeados (deve sair 0).
9. **Comentários e textos de hook em português ou inglês misturados são intencionais** (mensagens ao usuário em PT-BR, instruções ao modelo em EN/PT). Não reescreva.
10. **Não use travessão.** Regra global do usuário, vale para código, commits, notas e este documento.
11. **Hook não carrega skill; só o modelo carrega.** Injetar o texto da skill como contexto não mostra nada ao usuário, e um `systemMessage` com "Skill loaded(...)" escrito pelo próprio hook foi recusado: afirma um carregamento que ninguém provou. O que o usuário quer ver é o aviso nativo da ferramenta `Skill`. A única alavanca é instruir o modelo no `additionalContext` (seções 4 e 5). Nas sessões em que o aviso não aparecer, o hook rodou mas o modelo não obedeceu: endureça o texto da instrução. Testado em 2026-10-22: com o `/goal`, o modelo carregou as quatro skills pela ferramenta depois de o usuário cobrar. `programming-best-practices` foi criada e carregada na mesma sessão e `git-guidelines` entrou depois: a sessão filha da decisão 12 chamou as seis.
12. **Testar os hooks de `/goal` de ponta a ponta com uma sessão filha.** Um teste sintético da saída do script não prova que o modelo obedece a instrução de `Skill`. Rode, a partir de um diretório temporário: `FABLE_JUDGE_ACTIVE=1 claude -p "/goal teste de hooks" --output-format stream-json --verbose --allowedTools Skill --max-turns 8` e leia os eventos `tool_use`. `FABLE_JUDGE_ACTIVE=1` é a guarda de recursão que faz os hooks de Stop próprios saírem na hora (sem ela a sessão filha chama o juiz). Para prompt comum use `claude -p "oi" ...` com os mesmos flags. Resultado de 2026-10-22, nos dois casos (`/goal teste de hooks` e `oi`): a sessão nova chamou a ferramenta `Skill` seis vezes (`andrej-karpathy-skills:karpathy-guidelines`, `graphify`, `humanizer`, `attack-protection`, `programming-best-practices`, `git-guidelines`), cada uma com `Launching skill: ...`. Dentro de uma sessão já carregada a mesma chamada responde `already loaded` e não mostra o aviso de novo.

13. **Evidência em arquivo, não texto do modelo (quality-judge).** O `quality-judge-stop.sh` só libera quando `gate.json` e `judge.json` do turno corrente dizem `pass`; quem escreve esses arquivos são `quality-gate.sh` e `llm-judge.sh`, não o modelo. O usuário escolheu em 2026-10-25 "sempre bloquear": toda parada, inclusive pergunta conceitual, ganha uma rodada com as duas skills, e no modo `response` o juiz chama o Fable a cada turno (custo e latência). Se pesar, pular o juiz no modo `response` é uma linha no passo 1 do hook. Limite: o desenho protege contra esquecimento do modelo, não contra um modelo que forje o JSON.
14. **Turno = `promptId`, não "último user" nem `origin`.** No transcript, feedback de hook, corpo de skill, o lembrete `Skill /x is already loaded above; instructions unchanged.` (marcado `isMeta`) e `tool_result` também são entradas `type: user`. Usar o último `user` qualquer, ou o fallback por prefixo, fez cada bloqueio de Stop virar "turno novo": o estado zerava, o `gate.json` carimbado no turno anterior era ignorado e o hook bloqueava de novo, num loop sem fim (visto em 2026-10-25 numa sessão de `/goal`: ~14 rodadas gate+juiz 9/10 sem nunca liberar). Esses transcripts não têm campo `origin`. Todas as entradas de um turno (prompt, tool results, lembretes, feedback de hook) levam o mesmo `promptId`, então o turno é o `promptId` da última entrada `user` e começa na primeira entrada com esse id. Só em transcript sem `promptId` cai no fallback por `origin`/prefixo, ignorando `isMeta`. `qjs_transcript.py` centraliza isso. `gate.json` e `judge.json` carregam o id do turno e não são apagados na troca de turno (o velho é ignorado), então um gate rodado antes do primeiro Stop ainda vale.
15. **`${PIPESTATUS[0]}` não sai de `$(...)`.** Em `err="$(cmd 2>&1 | tail -n 1)"; [ "${PIPESTATUS[0]}" -eq 0 ]` o pipeline roda no subshell e o teste sempre vê 0: o `quality-gate.sh` chegou a aprovar toml e yaml quebrados assim. Capture o status do próprio comando (`err="$(cmd 2>&1)" || falha`) e só depois filtre com `tail`.
16. **Edição de `settings.json` e o classificador.** A troca do bloco `Stop` passou, mas a edição de `permissions.allow` (e um comando de leitura que citava o arquivo logo depois) foi negada como auto-modificação. Não contornar: entregar o trecho ao usuário (ver fim da seção 6.3).

17. **Session Name no iTerm2 só muda por AppleScript.** No iTerm2 3.7.3, as sequências OSC 0, 1 e 2 escritas no tty não alteraram o nome da sessão; `tell application "iTerm2" ... set name of session to "x"` alterou. `OSC 1337;SetProfile=...` mostra um aviso de segurança do iTerm ("A control sequence attempted to change the current profile. Allow this in the future?") que só o usuário pode aprovar; o hook não usa essa sequência. O hook acha a sessão pelo `unique id`, não por "current session", porque a sessão do claude pode não ser a que está em foco.
18. **Session Title "apenas Name" via API Python do iTerm2 (verificado).** A sessão nova do claude estava com Title "Name (Job)". `Title Components` é um bitmask no perfil (`1` = só Session Name). O que funciona, ao vivo e sem aviso de segurança: o pacote oficial `iterm2` (PyPI, 2.30) num venv (`python3 -m venv ~/.claude/venvs/iterm2 && ~/.claude/venvs/iterm2/bin/pip install iterm2`), com o servidor da API ligado (`defaults read com.googlecode.iterm2 EnableAPIServer` = 1), e `session.async_set_profile_properties(LocalWriteOnlyProfile().set_title_components([TitleComponents.SESSION_NAME]))`, que muda só aquela sessão. O hook chama `iterm-title-name.py` (apêndice) com `timeout 8`; sem venv ou sem API ele pula em silêncio. Provado: antes do hook a sessão lia bits de Job (inclusive o bit 2048, que a lib não conhece e faz `title_components` levantar `ValueError`); depois de uma sessão nova do claude leu `[SESSION_NAME]`. Para aplicar em todas as sessões abertas de uma vez: percorrer `app.terminal_windows`, `tabs` e `sessions` com o mesmo `set_title_components`. Caminhos que NÃO funcionaram: `OSC 0/1/2` (não mudam o nome), `OSC 1337;SetProfile` (pede aprovação do usuário), `defaults write` no perfil Default com o iTerm aberto (não aplica ao vivo) e perfil dinâmico (funciona, mas exige abrir a aba com ele). Cuidado em testes: forçar Job de propósito numa sessão real a faz exibir o Job até o hook rodar de novo.

19. **`/clear` devolvia o nome errado no iTerm2 (2026-10-29, verificado).** O hook `iterm-session-name.sh` disparava com o `cwd` certo no `/clear` (log `~/.claude/logs/iterm-session-name.log` e campo `cwd` dos transcripts), então a falha vinha depois dele: o Claude Code escreve o título do terminal (OSC 0/2) ao reiniciar a sessão, e o iTerm, com `Allow Title Setting` ligado (padrão do perfil), troca o Session Name pelo título do app. O usuário viu o nome virar "Claude Code". A primeira tentativa, `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` no `env`, ficou no `settings.json` mas não bastou (só vale para sessão iniciada depois da mudança e não foi provada). A correção que funciona está no iTerm: `iterm-title-name.py` agora também faz `profile.set_allow_title_setting(False)` na sessão (mesma chamada `async_set_profile_properties` da decisão 18, ao vivo, sem aviso de segurança), então o hook, que já roda em `startup|resume|clear`, desliga a aceitação de título do app em toda sessão do claude. Prova (iTerm2 3.7.6): `session.async_inject` de `ESC ] 0 ; Claude Code BEL` com `allow_title_setting` ligado muda o nome para "Claude Code"; com ele desligado o nome fica o da pasta. Para aplicar às abas já abertas: percorrer `app.terminal_windows`, `tabs` e `sessions` com `set_allow_title_setting(False)`. Prova com `/clear` real (2026-10-29 08:54): sessão interativa nova do `claude` aberta pela API do iTerm (`Window.async_create`, pasta já confiável, `FABLE_JUDGE_ACTIVE=1`), `/clear` digitado com `async_send_text`; o nome ficou `resume-renato` antes, 6 s e 16 s depois, e o log mostrou `source=startup` e `source=clear` com `allow_title_setting=0`. Pasta nova abre o prompt de confiança e o hook nem roda, então use uma pasta já confiável. Efeito colateral: apps (ssh, vim) dentro dessas abas deixam de retitular a aba.
20. **Nome da aba virou `agent-<id>` no meio da sessão (2026-10-30, verificado).** Em `~/Workspace/publish-shorts/` a aba do iTerm passou a mostrar `agent-abe0409a623d46726`. Causa: subagentes com `isolation: worktree` rodam em `<projeto>/.claude/worktrees/agent-<id>`, disparam o SessionStart (`source=startup`) com esse `cwd` e herdam o `ITERM_SESSION_ID` da aba do usuário, então o hook trocava o Session Name pelo basename do worktree. O log `~/.claude/logs/iterm-session-name.log` mostrou `08:49:02 source=startup name=agent-abe0409a623d46726`, e o diretório existe em `.claude/worktrees/` com a mesma hora. É um problema diferente do da decisão 19 (OSC do app): aqui o próprio hook errava. Correção: `iterm-session-name.sh` sai sem renomear quando o `cwd` casa `*/.claude/worktrees/*` e registra `skipped=worktree` no log. Teste com payload de worktree (nome preservado, `skipped=worktree`) e de projeto normal (renomeia). Para voltar o nome de uma aba já afetada: abrir nova sessão na pasta ou `/clear` (o hook roda em `clear` e restaura o basename). Os diretórios `agent-*` antigos em `.claude/worktrees/` podem ser removidos com `git worktree prune` e `rm -r` quando não forem mais úteis; não afetam o nome.
21. **Nome da sessão mudava para outra pasta no meio do uso (2026-11-02, verificado).** Uma sessão aberta em `/Volumes/Renato/PSVita/` passou a mostrar `ISO` na barra do iTerm2. Causa: `iterm-session-name.sh` derivava o nome do `cwd` do payload, e esse `cwd` acompanha os `cd` que o Claude faz dentro da sessão; em todo `clear` ou `resume` o hook renomeava a aba para a pasta onde o Claude estava naquele momento (o log mostra `source=clear name=renato.pereira`). Regra do usuário: depois que a sessão é aberta numa pasta e recebe o nome dela, o nome não muda mais. Correção: o nome vem de `CLAUDE_PROJECT_DIR` (pasta onde o Claude foi iniciado, estável durante a sessão), com fallback para o `cwd` e depois `$PWD`. A checagem de worktree de subagente (decisão 20) continua olhando o `cwd` do payload. Teste com UUID falso em `ITERM_SESSION_ID` (não toca em nenhuma aba real): payload `cwd=/Volumes/Renato/PSVita/ISO` com `CLAUDE_PROJECT_DIR=/Volumes/Renato/PSVita` registra `name=PSVita`; sem a variável registra `name=ISO` (fallback antigo). Segunda rodada (mesmo dia): o usuário abriu a sessão em `~`, deu `claude --resume` e a aba virou `Documents`, porque num `resume` o `CLAUDE_PROJECT_DIR` é o último `cwd` da sessão antiga (a pasta para onde o Claude tinha feito `cd`), não a original. O transcript guarda a pasta original no primeiro `cwd`, então o hook lê esse valor (`jq -rn 'first(inputs|select(.cwd).cwd)'`) e só depois usa `CLAUDE_PROJECT_DIR`; no `clear`, que abre transcript novo, o hook reaproveita o nome gravado para o UUID da aba em `~/.claude/state/iterm-names/`. Testes com UUID falso: `resume` com `CLAUDE_PROJECT_DIR=~/Documents` e transcript aberto em `~` registra `name=renato.pereira`; `clear` com `cwd=.../PSVita/ISO` reaproveita o nome guardado; `startup` em `.../PSVita` registra `PSVita`. Caso que ainda muda o nome: `resume` de uma sessão antiga numa aba nova nomeia pela pasta original dessa sessão, o que é o esperado. Prova em sessão interativa real (2026-11-02): janela nova do iTerm aberta pela API, `claude` iniciado em `~/Documents`, o Claude fez `cd` para a subpasta `_qjs_sub` (o transcript registra o `cwd` mudando para `Documents/_qjs_sub`), depois `/clear` duas vezes, `/exit` e `claude --continue`; o nome da aba lido pela API ficou `Documents` em todos os passos e o log registrou `startup`, `clear`, `clear` e `resume` com `name=Documents`. Repetido no cenário exato do relato (2026-11-02): sessão aberta em `/Volumes/Renato/PSVita`, o Claude fez `cd` para `PSVita/src` e `PSVita/app` (transcripts mostram o `cwd` mudando), `/clear` duas vezes, `/exit` e `claude --continue`; nome da aba `PSVita` em todos os passos e log `startup`, `clear`, `clear`, `resume` com `name=PSVita proj=/Volumes/Renato/PSVita`. Uma aba já aberta antes da correção (como o PSVita original) também passa a seguir a regra no próximo `/clear`, porque o hook é lido do disco a cada evento e `CLAUDE_PROJECT_DIR` vem do processo, que foi iniciado na pasta certa; na aba original do relato (UUID `01F13124...`, processo `claude` iniciado em 2026-11-01 20:01 com cwd `/Volumes/Renato/PSVita`) o transcript confirma a origem do bug, com o `cwd` passando por `PSVita/pspemu/ISO` e voltando; o estado gravado para essa aba em `~/.claude/state/iterm-names/` é `PSVita`, e rodar o hook com o UUID real dela e um payload `clear` com `cwd=.../pspemu/ISO` registrou `name=PSVita` (sem digitar `/clear` na sessão dela, para não apagar o contexto do usuário). Armadilha do teste: `cd` para fora do projeto (por exemplo `/tmp`) não reproduz o relato, porque o Claude Code repõe o `cwd`; o drift só acontece com `cd` para subpasta do projeto. No `send_text` do iTerm, `\n` só quebra linha no prompt do Claude; use `\r` para enviar. A correção vale para qualquer pasta, não só o PSVita (o PSVita foi o exemplo do relato). Prova numa sessão real do `claude -p` (2026-11-02, UUID falso): o log passou a registrar `proj=` e mostrou `name=_qjs_probe proj=/Users/renato.pereira/Documents/_qjs_probe`, ou seja, o hook recebe `CLAUDE_PROJECT_DIR`; `proj=unset` no log indica que a variável sumiu e o nome voltou ao `cwd`. O iTerm só vê a correção em sessões abertas depois da mudança do script; para uma aba já renomeada, `/clear` restaura o nome certo.

22. **Nome da aba mudava sozinho por `claude` filho herdar o `ITERM_SESSION_ID` (2026-11-03, verificado).** Regra do usuário, repetida: depois que uma sessão do claude é criada numa pasta, o nome da aba não muda mais, mesmo que o Claude faça `cd` por dentro. A aba do relato (UUID `C0B3363D...`) é um `claude --resume` iniciado em `~` em 2026-10-31 (processo 55703, cwd `~` até hoje), mas a barra mostrava `Doutorado-PRODEI-2026`. Causa: o log `~/.claude/logs/iterm-session-name.log` tinha dezenas de linhas `source=startup` com pastas que nunca foram a pasta da aba (`Wii U`, `renato` do vault, `docs`, `Doutorado-PRODEI-2026`), e a aba não tem `startup` de verdade desde 31/out. Eram processos `claude` filhos da sessão (o juiz `claude -p`, o claude-mem, helpers `--output-format stream-json --no-session-persistence`): herdam o `ITERM_SESSION_ID` da aba, rodam os hooks de SessionStart com a pasta deles e o hook renomeava a aba e ainda gravava esse nome no estado `~/.claude/state/iterm-names/<uuid>`, que o `clear` passa a respeitar. As decisões 20 (worktree de subagente) e 21 (drift de `cwd`) não cobriam esse caso. Correção: `iterm-session-name.sh` sobe a árvore de processos a partir de `$$` e conta os ancestrais cujo executável (`ps -o comm=`, basename) é `claude`; só o `claude` dono da aba tem exatamente um (o próprio, ancestrais `zsh`, `login`, iTerm2), e um filho tem dois ou mais. Com mais de um o hook sai sem tocar no nome nem no estado e registra `skipped=nested-claude(N)`. O match é pelo executável, não pela linha de comando: uma primeira versão com `grep` na linha de comando deu falso positivo, porque o `zsh -c` do comando de teste continha `/claude ` no texto. O log agora grava também o `uuid`, o que faltava para ligar cada linha à aba. Testes com UUID falso (sem tocar em aba real): hook chamado direto da sessão (um `claude` ancestral) renomeia (`name=renato.pereira`); hook chamado por um processo cujo executável se chama `claude` (cópia do binário do node, que roda sob o `claude` real) registra `skipped=nested-claude(2)` e não cria o arquivo de estado. Armadilha do teste: cópia de `/bin/bash` renomeada para `claude` não rodou nada no teste (provável SIP, não confirmado), use o binário do node. A aba do relato foi restaurada à mão para `renato.pereira` (estado e nome ao vivo, conferido por AppleScript), porque o nome errado já estava gravado no estado e o próximo `/clear` o reaproveitaria. Para outras abas afetadas: gravar o nome certo em `~/.claude/state/iterm-names/<uuid>` e fazer `set name` por AppleScript, ou rodar o laço da decisão 18.
23. **Hook do `/diff` ganhou a abertura do editor (2026-11-13, verificado).** Pedido do usuário: o mod `git-diff-on-start` já rodava `/diff` ao abrir o Claude numa pasta com `.git`; passou a rodar também `code . || antigravity-ide .`, isto é, abre o projeto no VS Code e, se o `code` não existir, no Antigravity. Implementação em `hooks/register.ts`: a função `openEditor` percorre `['code', 'antigravity-ide']` e chama `$.process.run([editor, '.'])`; para no primeiro que sai com código 0. `$.process.run` não usa shell, então o `||` virou o laço, e um executável que não existe faz a promessa rejeitar (tratado como falha, como o `command not found` do shell). Roda no mesmo gatilho do `/diff` (`session.start` interativo, dentro de repo, `turns() === 0`), então um hot reload no meio da sessão não reabre o editor. O `cwd` é o da sessão. Nesta máquina o `code` não está instalado (`which code` dá `not found`) e o `antigravity-ide` está em `~/.antigravity-ide/antigravity-ide/bin/antigravity-ide`, então na prática o fallback é o caminho usado. Três testes novos em `register.test.ts` (abre o `code`; cai para `antigravity-ide` quando o `code` falha; nada fora de repo); `claude plugin test ~/.claude/mods/git-diff-on-start` dá 8 pass, 0 fail. Armadilha: o PATH do processo do hook pode não ter `/opt/homebrew/bin` nem o diretório do `antigravity-ide`; se o editor não abrir, confira o PATH do Claude Code ou troque o item da lista por caminho absoluto.

## 8. Checklist de replicação (execute nesta ordem)

1. Instale os pré-requisitos da seção 2 e confirme `jq --version`, `python3 --version`, `gh auth status`, `claude --version`.
2. Adicione os marketplaces e instale os plugins listados (seção 2). Confirme que existe `~/.claude/plugins/cache/karpathy-skills/andrej-karpathy-skills/*/CLAUDE.md`.
3. Crie `~/.claude/scripts/` e grave **cada arquivo do apêndice** com o mesmo nome. `chmod +x` em todos os `.sh` e `.py`. Troque os caminhos `/Users/renato.pereira` (apenas em `cc-status-safe.py` e no JSON de settings) pelos da nova máquina, ou pule o cc-status.
4. Grave as skills `git-guidelines`, `attack-protection` e `tests-guidelines` em `~/.claude/skills/<nome>/SKILL.md` (fontes no apêndice). Instale `humanizer` e `graphify` do upstream. Grave também `quality-gate` e `llm-as-judge` em `~/.claude/skills/<nome>/SKILL.md` (fontes no apêndice).
5. Mescle a seção 3 no `~/.claude/settings.json`: ajuste `$HOME`/caminhos, remova do bloco os itens opcionais que você pulou (cc-status, mod `git-diff-on-start`). Valide: `python3 -c "import json;json.load(open('$HOME/.claude/settings.json'))"`.
6. Crie (ou aponte) o vault `~/Documents/Obsidian Vault/<pasta>/MEMORY.md` se for usar a memória; senão avise o usuário de que a parte de persistência ficará inativa.
7. Verifique cada script isoladamente:
   - `bash -n` em todos os `.sh`; `python3 -m py_compile` nos `.py`.
   - Gate: monte um repo git temporário e envie payloads sintéticos, por exemplo `printf '%s' '{"tool_name":"Bash","cwd":"/tmp/x","tool_input":{"command":"git commit -m \"update stuff\""}}' | ~/.claude/scripts/pr-gate-pretool.py; echo rc=$?` deve dar `rc=2` com a lista de erros; um commit `feat(x): add thing` com corpo deve dar `rc=0`.
   - Linter: `python3 ~/.claude/scripts/pr_lint.py url <url-de-um-PR-fechado>` deve sair 0.
   - Fable: `parse_score` deve extrair 8 de `SCORE: 8` e `**Score:** 8/10`; a condição de limite deve acionar o fallback para Opus 5.5 (e liberar só se o Opus também falhar) com a mensagem "You've reached your Fable limit..." e **não** liberar `SCORE: 5` + feedback citando "rate limit".
   - Gate e juiz: num repo git temporário, um JSON quebrado e uma chave AWS falsa montada com `printf` (não grave nada que pareça chave real) devem dar `GATE: FAIL`; `llm-judge.sh` sem `gate.json` do turno sai 3; com um `claude` falso no PATH, `SCORE: 8` aprova e o limite do Fable aciona o Opus; `quality-judge-stop.sh` com transcript sintético percorre bloqueio sem gate, gate fail, juiz fail, perguntas git, persistência e liberação.
   - Stop completo: `echo '{"transcript_path":"/caminho/tr.jsonl","session_id":"t1"}' | ~/.claude/scripts/pr-lint-stop.sh; echo rc=$?`.
8. Abra uma sessão nova: confirme que o contexto do Karpathy aparece no início e que uma mensagem comum NÃO dispara nenhuma chamada de `Skill`, rode `/goal teste` e confirme a mensagem do hook (linhas "Avoiding over engineering...", "Reading Obsidian vault...") e que o Claude avisa explicitamente que disparou os hooks de início e de parada. Confirme também, só depois do `/goal`, o aviso nativo `Skill(...) Successfully loaded skill` das seis skills (ou rode o teste da decisão 12 da seção 7).
9. Faça qualquer turno: o Stop deve bloquear mostrando "Running quality gate with /quality-gate" e "Running llm-as-judge with /llm-as-judge", o modelo deve chamar `Skill(quality-gate)` e `Skill(llm-as-judge)` e só então a parada é liberada. Com um `git diff` pequeno vêm também as 3 perguntas git e a persistência no vault.
10. (Opcional, só iTerm2) Grave `iterm-session-name.sh` e o perfil dinâmico do apêndice; teste com `echo '{"cwd":"/tmp/demo"}' | ~/.claude/scripts/iterm-session-name.sh` e leia `osascript -e 'tell application "iTerm2" to get name of current session of current window'`. Depois crie o venv com o pacote `iterm2` e grave `iterm-title-name.py` (decisão 18 da seção 7) e confirme com `session.async_get_profile()` que `title_components` é `[SESSION_NAME]`.
11. Relate ao usuário o que foi pulado e por quê.

**Estado de verificação desta máquina:** os scripts e o `settings.json` estão sintaticamente válidos; gate, linter, regex de score e condição de limite do juiz foram exercitados com entradas sintéticas; o juiz foi observado ao vivo bloqueando por limite de uso do Fable antes do ajuste de fail open, e a versão corrigida foi validada por testes da condição (não houve nova execução ao vivo com o Fable disponível). O gate ainda não rodou contra um `gh pr create` real depois de instalado. Em 2026-10-22 todos os `.sh` e `.py` passaram em `bash -n` e `py_compile`; `goal-start-trigger.sh` (com `/goal` e com prompt comum), `karpathy-guidelines-hook.sh`, o gate (commit inválido bloqueado) e o juiz (sem diff e sem goal) foram exercitados com entradas sintéticas, e o fluxo `/goal` foi provado de ponta a ponta por uma sessão filha (decisão 12 da seção 7). Prompt comum (UserPromptSubmit) e `/goal` foram provados com sessão filha (`claude -p`); o `goal` não duplica a instrução (uma ocorrência de OBRIGATORIO) e o hook do Karpathy fica em silêncio no `/goal`. Correção de 2026-11-01: só o `/goal` emite a instrução (testado com entradas sintéticas: SessionStart e prompt comum sem OBRIGATORIO, `/goal` com uma ocorrência); a afirmação antiga de que SessionStart e UserPromptSubmit a emitiam não vale mais. Em 2026-10-25: `quality-gate.sh`, `llm-judge.sh` (com `claude` falso) e a máquina de estados do `quality-judge-stop.sh` (transcript sintético, repo git temporário) foram exercitados; verificado ao vivo no primeiro Stop real da sessão: o hook bloqueou, o modelo chamou as duas skills e o Fable 5.1 pontuou 8/10 em modo `response`. Ainda não verificado: uma sessão interativa nova sem nenhum aviso de `Skill` em mensagem comum e com as seis skills só após `/goal`, o `exit 2` do gate medido direto (o `PIPESTATUS` do teste saiu vazio), e a execução real de `feedback-loop` e `pr-lint-stop.sh`, que só passaram na checagem de sintaxe.

## Apêndice A: fontes completas

Copie cada bloco para o caminho indicado. Atenção a `git-guidelines/SKILL.md`: o `pr_lint.py` extrai dele o template de PR padrão (bloco ` ```markdown ` logo após `## PR description`); não reformate esse trecho.

### `~/.claude/scripts/karpathy-guidelines-hook.sh`

````bash
#!/bin/bash
# karpathy-guidelines, SessionStart hook.
# Injects the andrej-karpathy-skills CLAUDE.md content as context. It does NOT
# tell the model to call the Skill tool: the six-skill load happens only on
# /goal, via goal-start-trigger.sh (which calls this script with stdin at EOF
# => SessionStart, KARPATHY_NO_INSTR=1). Normal prompts (UserPromptSubmit) get
# nothing from here.
payload="$(cat)"
event="$(printf '%s' "$payload" | jq -r '.hook_event_name // "SessionStart"' 2>/dev/null)"
[ -n "$event" ] || event="SessionStart"
[ "$event" = "UserPromptSubmit" ] && exit 0
f=$(ls -d "$HOME"/.claude/plugins/cache/karpathy-skills/andrej-karpathy-skills/*/CLAUDE.md 2>/dev/null | sort -V | tail -1)
[ -f "$f" ] || exit 0
jq -Rs --arg e "$event" '{hookSpecificOutput:{hookEventName:$e,additionalContext:.}}' < "$f"
````

### `~/.claude/scripts/graphify-autobuild-hook.sh`

````bash
#!/bin/bash
# graphify-autobuild: always-on SessionStart hook.
# In a git repo without graphify-out/graph.json, kicks off a no-API-key
# code-only index in the background (non-blocking) and tells the model
# indexing is underway.
# If already indexed, nudges the model to query the graph before grep/find.

command -v graphify >/dev/null 2>&1 || exit 0

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
graph="$root/graphify-out/graph.json"

if [ -f "$graph" ]; then
  msg="graphify: this repo is indexed ($graph). Use the graphify skill (/graphify query \"...\") before grep/find to locate or understand code."
else
  log="$root/.graphify-autobuild.log"
  nohup graphify "$root" --code-only >"$log" 2>&1 &
  disown
  msg="graphify: no graphify-out/ found for this repo. Auto-indexing started in code-only mode (no LLM key required; log: $log). It may not be ready yet this turn, so check for graphify-out/graph.json before relying on it, and fall back to grep/find until it appears."
fi

jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
````

### `~/.claude/scripts/goal-start-trigger.sh`

````bash
#!/usr/bin/env bash
# UserPromptSubmit hook: whenever the user runs /goal, re-fire the
# always-on SessionStart hooks (karpathy guidelines, graphify autobuild)
# and read the Obsidian vault's MEMORY.md for this folder, so a new goal
# gets the same context-grounding a fresh session gets.
# There's no native "goal created" hook event, so this detects it from
# the raw prompt text instead.
set -u

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty')"

case "$prompt" in
  /goal) : ;;
  /goal[[:space:]]*) : ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

context=""
lines=""
add_line() { lines="${lines}
    $1"; }
for hook in karpathy-guidelines-hook.sh graphify-autobuild-hook.sh; do
  case "$hook" in
    karpathy-*) label="/andrej-karpathy-skills:karpathy-guidelines"; verb="Avoiding over engineering with" ;;
    graphify-*) label="/graphify"; verb="Reading local files with" ;;
  esac
  out="$(cd "$cwd" && KARPATHY_NO_INSTR=1 "$HOME/.claude/scripts/$hook" 2>/dev/null)"
  piece="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  if [ -z "$piece" ] && [ "$hook" = graphify-autobuild-hook.sh ]; then
    piece="graphify: no git repo or graphify-out in $cwd. If this goal involves code, use the /graphify skill (e.g. /graphify . to index, /graphify query \"...\") before grep/find."
  fi
  [ -n "$piece" ] || { add_line "Skipped $label (no context to load here)"; continue; }
  if [ -n "$context" ]; then
    context="$context

$piece"
  else
    context="$piece"
  fi
  add_line "$verb $label"
done

append_ctx() { if [ -n "$context" ]; then context="$context

$1"; else context="$1"; fi; }

append_ctx "humanizer: when writing prose (replies, docs, notes, emails, commit/PR messages), apply the /humanizer skill (Skill tool) to remove AI writing patterns. Never use em dashes."
add_line "Writing text with /humanizer"

append_ctx "attack-protection: when writing or reviewing code, apply the /attack-protection skill (Skill tool) against XSS, exposed API routes, exposed API keys, open database, SQL injection, missing rate limits, prompt injection and hallucinated packages."
add_line "Avoiding attacks with /attack-protection"

append_ctx "programming-best-practices: when writing or reviewing code, apply the /programming-best-practices skill (Skill tool): TDD, SOLID without speculative abstractions, complete static typing, Google Style docstrings and linting."
append_ctx "git-guidelines: when naming a branch or writing a commit, PR title or PR description, apply the /git-guidelines skill (Skill tool): Conventional Commits, EN-US, no em dashes."
add_line "Following /programming-best-practices and /git-guidelines"

folder="$(basename "$cwd")"
d="$cwd"
while [ "$d" != "$HOME" ] && [ "$d" != "/" ]; do
  if [ -f "$HOME/Documents/Obsidian Vault/$(basename "$d")/MEMORY.md" ]; then folder="$(basename "$d")"; break; fi
  d="$(dirname "$d")"
done
[ "$cwd" = "$HOME" ] && folder="renato"
vault_memory="$HOME/Documents/Obsidian Vault/$folder/MEMORY.md"
if [ -r "$vault_memory" ]; then
  vault_content="$(head -c 8000 "$vault_memory" 2>/dev/null)"
  if [ -n "$vault_content" ]; then
    piece="Obsidian vault memory index for \"$folder\" (read per ~/.claude/CLAUDE.md: check before assuming context):

$vault_content"
    if [ -n "$context" ]; then
      context="$context

$piece"
    else
      context="$piece"
    fi
    notes="$(printf '%s' "$vault_content" | grep -o '\](' | wc -l | tr -d ' ')"
    add_line "Reading Obsidian vault: $folder/MEMORY.md ($notes linked notes in the index)"
  fi
else
  add_line "Obsidian vault: no $folder/MEMORY.md, nothing to read"
fi

instr='REQUIRED: before any other action, call the Skill tool once for each of: andrej-karpathy-skills:karpathy-guidelines, graphify, humanizer, attack-protection, programming-best-practices, git-guidelines. The user checks the native notice "Skill(...) Successfully loaded skill". Do not write that notice as text.'
context="$instr

$context"

if [ -z "$context" ]; then
  jq -n --arg l "$lines" '{systemMessage: $l}'
  exit 0
fi

msg="${lines}"
jq -n --arg m "$context" --arg sysmsg "$msg" \
  '{systemMessage: $sysmsg, hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}'
````

### `~/.claude/scripts/feedback-loop-lib.sh`

````bash
#!/usr/bin/env bash
# Shared helpers for feedback-loop.sh (PostToolUse) and
# feedback-loop-stop.sh (Stop): find the project a path belongs to and run
# whatever lint/typecheck/test commands that project already exposes.

# ponytail: no `timeout`/`gtimeout` on this machine, so roll a minimal one.
run_with_timeout() {
  secs="$1"; shift
  "$@" > "$out_file" 2>&1 &
  cmd_pid=$!
  ( sleep "$secs" && kill -TERM "$cmd_pid" 2>/dev/null ) &
  watchdog_pid=$!
  wait "$cmd_pid" 2>/dev/null
  status=$?
  kill "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  return $status
}

# Sets project_root and marker as a side effect; leaves both empty if none found.
find_project_root() {
  dir="$1"
  project_root=""
  marker=""
  while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
    for m in package.json pyproject.toml go.mod Cargo.toml; do
      if [ -f "$dir/$m" ]; then
        project_root="$dir"
        marker="$m"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  return 1
}

try_cmd() {
  label="$1"; shift
  run_with_timeout 90 "$@"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    body="$(tail -c 4000 "$out_file")"
    failures="${failures}\n### ${label} (exit ${rc})\n${body}\n"
  fi
}

# Requires project_root/marker set (find_project_root) and cwd already
# changed into project_root. Sets failures as a side effect.
run_checks() {
  failures=""
  out_file="$(mktemp)"
  trap 'rm -f "$out_file"' RETURN

  case "$marker" in
    package.json)
      has_script() { jq -e --arg s "$1" '.scripts[$s]' package.json >/dev/null 2>&1; }
      has_script lint && try_cmd "npm run lint" npm run lint --silent
      if has_script typecheck; then
        try_cmd "npm run typecheck" npm run typecheck --silent
      elif has_script type-check; then
        try_cmd "npm run type-check" npm run type-check --silent
      elif [ -f tsconfig.json ]; then
        try_cmd "tsc --noEmit" npx --no-install tsc --noEmit
      fi
      has_script test && try_cmd "npm test" npm test --silent
      ;;
    pyproject.toml)
      if grep -q '\[tool.ruff\]' pyproject.toml 2>/dev/null || [ -f ruff.toml ] || [ -f .ruff.toml ]; then
        try_cmd "ruff check" ruff check .
      fi
      if grep -q '\[tool.mypy\]' pyproject.toml 2>/dev/null || [ -f mypy.ini ]; then
        try_cmd "mypy" mypy .
      fi
      if grep -q '\[tool.pytest' pyproject.toml 2>/dev/null || [ -d tests ]; then
        try_cmd "pytest" pytest -q
      fi
      ;;
    go.mod)
      try_cmd "go vet" go vet ./...
      try_cmd "go build" go build ./...
      try_cmd "go test" go test ./...
      ;;
    Cargo.toml)
      try_cmd "cargo check" cargo check
      try_cmd "cargo test" cargo test
      ;;
  esac
}
````

### `~/.claude/scripts/feedback-loop.sh`

````bash
#!/usr/bin/env bash
# PostToolUse feedback loop: after Edit/Write/MultiEdit, run the touched
# project's own lint/typecheck/test commands and hand failures back to
# Claude via stderr + exit 2 so it can self-correct next turn.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./feedback-loop-lib.sh

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -n "$file_path" ] && [ -f "$file_path" ] || exit 0

case "$file_path" in
  */node_modules/*|*/.git/*|*/dist/*|*/build/*|*/.venv/*) exit 0 ;;
esac

find_project_root "$(dirname "$file_path")" || exit 0
cd "$project_root" || exit 0
run_checks

if [ -n "$failures" ]; then
  printf 'feedback-loop: checks failed in %s\n%b' "$project_root" "$failures" >&2
  exit 2
fi

exit 0
````

### `~/.claude/scripts/feedback-loop-stop.sh`

> Legado: não registrado em Stop desde 2026-10-25 (absorvido pelo `quality-gate.sh`); fica no disco para rollback.

````bash
#!/usr/bin/env bash
# Stop hook: before Claude ends its turn, run the current project's own
# lint/typecheck/test commands and block the stop until they pass.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./feedback-loop-lib.sh

payload="$(cat)"

# Already looping because a previous Stop hook blocked this turn, don't
# force an infinite loop if checks keep failing.
stop_active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')"
[ "$stop_active" = "true" ] && exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

find_project_root "$cwd" || exit 0
cd "$project_root" || exit 0
run_checks

if [ -n "$failures" ]; then
  printf 'feedback-loop: checks still failing in %s, fix them before finishing.\n%b' "$project_root" "$failures" >&2
  exit 2
fi

exit 0
````

### `~/.claude/scripts/pr_lint.py`

````python
#!/usr/bin/env python3
"""Deterministic /git-guidelines linter for commits, PR title/body and branch.

Library for pr-gate-pretool.py; CLI for the Stop hook:
  pr_lint.py url <pr-url-or-number>   exit 0 = ok (or PR not OPEN), 1 = errors printed
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys

TYPES = "feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
HEADER = re.compile(rf"^({TYPES})\([\w./-]+\)!?: \S.*[^.\s]$")
EM = "\u2014"
TODO = "TODO(fill)"
SKILL = pathlib.Path.home() / ".claude/skills/git-guidelines/SKILL.md"
GH = shutil.which("gh") or "/opt/homebrew/bin/gh"
HEADING = re.compile(r"(?m)^#{1,6}[ \t]+(.+?)[ \t]*$")
FENCE = re.compile(r"(?s)```.*?```")
COMMENT = re.compile(r"(?s)<!--.*?-->")


def run(cmd, cwd=None):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=20)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def template(cwd=None):
    top = run(["git", "rev-parse", "--show-toplevel"], cwd)
    for name in ("PULL_REQUEST_TEMPLATE.md", "pull_request_template.md"):
        p = pathlib.Path(top or ".") / ".github" / name
        if top and p.is_file():
            return p.read_text()
    m = re.search(r"## PR description\s+```markdown\n(.*?)\n```", SKILL.read_text(), re.S)
    return m.group(1) if m else ""


def sections(text):
    """Ordered [(heading, content)] outside code fences."""
    text = FENCE.sub("", text)
    hs = list(HEADING.finditer(text))
    return [(h.group(1).strip(), text[h.end(): hs[i + 1].start() if i + 1 < len(hs) else len(text)])
            for i, h in enumerate(hs)]


def optional(heading):
    return bool(re.search(r"if applicable|optional", heading, re.I))


def lint_header(h, label):
    e = []
    if len(h) > 72:
        e.append(f"{label}: {len(h)} chars, max 72")
    if not HEADER.match(h):
        e.append(f"{label}: must match 'type(scope): imperative summary' (types: {TYPES.replace('|', ', ')}), no trailing period")
    if EM in h:
        e.append(f"{label}: contains an em dash")
    return e


def lint_body(body, tpl):
    e = []
    if EM in body:
        e.append("body: contains an em dash")
    if TODO in body:
        e.append(f"body: still has {TODO} placeholders")
    want, got = sections(tpl), sections(body)
    names = [g[0].lower() for g in got]
    pos = -1
    for h, _ in want:
        if h.lower() not in names:
            e.append(f"body: missing section '{h}'")
            continue
        i = names.index(h.lower())
        if i < pos:
            e.append(f"body: section '{h}' is out of template order")
        pos = max(pos, i)
    for h, _ in want:
        if h.lower() not in names or optional(h):
            continue
        content = COMMENT.sub("", got[names.index(h.lower())][1]).strip()
        if not content:
            e.append(f"body: section '{h}' is empty")
        elif re.search(r"type of change", h, re.I) and "[ ]" in dict(want)[h] and not re.search(r"\[[xX]\]", content):
            e.append(f"body: section '{h}' has no checked box")
    return e


def lint_commits(commits):
    """commits: [(sha, subject, body)]"""
    e = []
    for sha, subj, body in commits:
        if subj.startswith("Merge "):
            continue
        e += lint_header(subj, f"commit {sha[:7]} header")
        if not body.strip():
            e.append(f"commit {sha[:7]}: no body (explain what and why)")
    return e


def lint_branch(name, cwd=None):
    if not name or re.match(rf"^({TYPES}|ai)/([A-Z][A-Z0-9]+-\d+-)?[a-z0-9][a-z0-9.-]*$", name):  # ai/ = autonomous daily runs
        return []
    return [f"branch '{name}': must be '<type>/[<TICKET-ID>-]<kebab-description>'"]


def default_base(cwd=None):
    ref = run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd)
    if ref:
        return ref
    for r in ("origin/main", "origin/master", "main", "master"):
        if run(["git", "rev-parse", "--verify", r], cwd):
            return r
    return ""


def commits_in(rng, cwd=None):
    out = run(["git", "log", "--format=%H%x1f%s%x1f%b%x1e", rng], cwd)
    res = []
    for rec in filter(str.strip, out.split("\x1e")):
        sha, subj, body = (rec.strip("\n").split("\x1f") + ["", ""])[:3]
        res.append((sha, subj, body))
    return res


def skeleton(title, commits, tpl, cwd=None):
    """Template pre-filled with what is derivable; the rest is TODO(fill)."""
    tm = re.match(rf"^({TYPES})(\(.*?\))?(!)?:", title or "")
    typ, brk = (tm.group(1), bool(tm.group(3))) if tm else ("", False)
    checks = {"feat": "feat", "fix": "fix", "refactor": "refactor / perf", "perf": "refactor / perf"}
    refs = sorted({m for _, s, b in commits for m in re.findall(r"(?:Closes|Fixes|Refs):? (#?[\w-]+)", b)})
    first_body = next((b.strip().split("\n\n")[0] for _, _, b in commits if b.strip()), "")
    out = []
    for h, content in sections(tpl):
        k = h.lower()
        if "summary" in k:
            body = first_body or TODO
        elif "type of change" in k:
            body = "\n".join(
                f"- [{'x' if (l.lower().lstrip('- [ ]').startswith(checks.get(typ, 'docs')) or (brk and 'breaking' in l.lower())) else ' '}] "
                + re.sub(r"^- \[.\] ", "", l) for l in content.strip().splitlines() if l.strip().startswith("- ["))
        elif "related" in k:
            body = "\n".join(f"Closes {r}" if r.startswith("#") else f"Refs: {r}" for r in refs) or "None"
        elif k == "changes":
            body = "\n".join(f"- {s}" for _, s, _ in commits) or TODO
        elif optional(h):
            body = "N/A"
        elif "checklist" in k:
            body = COMMENT.sub("", content).strip().replace("- [ ] Title follows Conventional Commits", "- [x] Title follows Conventional Commits")
        else:
            body = TODO
        out.append(f"## {h}\n{body}\n")
    return "\n".join(out)


def lint_pr(title, body, cwd=None):
    e = lint_header(title, "title") if title is not None else []
    if body is not None:
        e += lint_body(body, template(cwd))
    return e


def cli_url(ref):
    r = run([GH, "pr", "view", ref, "--json", "state,title,body,headRefName,commits,additions,deletions,url"])
    if not r:
        return 0  # gh unavailable or PR unreachable: nothing to judge
    d = json.loads(r)
    if d["state"] != "OPEN":
        return 0
    cs = [(c["oid"], c["messageHeadline"], c["messageBody"]) for c in d["commits"]]
    e = lint_pr(d["title"], d["body"]) + lint_commits(cs) + lint_branch(d["headRefName"])
    if d["additions"] + d["deletions"] > 400:
        print(f"note (non-blocking): {d['additions'] + d['deletions']} changed lines, guideline is ~400")
    if e:
        print(f"{d['url']}\n  - " + "\n  - ".join(e))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(cli_url(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[1] == "url" else 2)
````

### `~/.claude/scripts/pr-gate-pretool.py`

````python
#!/usr/bin/env python3
"""PreToolUse gate: block non-compliant commits/pushes/PRs before they exist.

Covers `git commit -m`, `git push`, `gh pr create|edit` and the GitHub MCP
create/update_pull_request. Violations: exit 2 with the fixes on stderr.
Only mechanical fixes (em dash, trailing period in an MCP title) are applied
through updatedInput; a missing/incomplete PR body is denied with a
pre-filled template file to complete (nothing is invented).
"""
import hashlib
import json
import re
import shlex
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import pr_lint as L  # noqa: E402

START = r"(?:^|[;&|(]\s*|\n\s*)"
HEREDOC = re.compile(r"^\$\(cat <<-?['\"]?(\w+)['\"]?\n(.*?)\n\s*\1\s*\)$", re.S)


def tokens(cmd, pattern):
    """Tokens of the first command matching `pattern`, up to the next shell operator."""
    m = re.search(START + f"(?P<c>{pattern})", cmd)
    if not m:
        return None
    lex = shlex.shlex(cmd[m.start("c"):], posix=True, punctuation_chars=True)
    lex.whitespace_split, lex.commenters = True, ""
    out = []
    for t in lex:
        if t in ("&&", "||", ";", "|", "&", "\n"):
            break
        out.append(t)
    return out


def val(tok):
    h = HEREDOC.match(tok)
    return h.group(2) if h else tok


def flag(toks, long, short=None):
    for i, t in enumerate(toks):
        if t == f"--{long}" or (short and t == f"-{short}") or (short and re.fullmatch(rf"-[a-zA-Z]*{short}", t)):
            return val(toks[i + 1]) if i + 1 < len(toks) else None
        if t.startswith(f"--{long}="):
            return val(t.split("=", 1)[1])
    return None


def all_flags(toks, long, short):
    vals, i = [], 0
    while i < len(toks):
        t = toks[i]
        if (t == f"--{long}" or re.fullmatch(rf"-[a-zA-Z]*{short}", t)) and i + 1 < len(toks):
            vals.append(val(toks[i + 1]))
            i += 1
        elif t.startswith(f"--{long}="):
            vals.append(val(t.split("=", 1)[1]))
        i += 1
    return vals


def deny(lines):
    print("pr-gate: blocked, fix and retry:\n  - " + "\n  - ".join(lines), file=sys.stderr)
    sys.exit(2)


def allow_updated(updated):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
                                             "updatedInput": updated}}))
    sys.exit(0)


def deny_body(title, body_errors, cwd, extra=()):
    base = L.default_base(cwd)
    commits = L.commits_in(f"{base}..HEAD", cwd) if base else []
    tpl = L.template(cwd)
    path = Path(tempfile.gettempdir()) / f"pr-body-{hashlib.md5((title or '').encode()).hexdigest()[:8]}.md"
    path.write_text(L.skeleton(title, commits, tpl, cwd))
    deny(list(extra) + body_errors + [
        f"template pre-filled at {path}: replace every {L.TODO}, then pass it with --body-file {path} "
        "(or as the MCP body)"])


def sanitize(s):
    return s.replace(f" {L.EM} ", ", ").replace(L.EM, ",") if s else s


def gate_commit(cmd, cwd):
    toks = tokens(cmd, r"git commit\b")
    if toks is None:
        return
    msgs = all_flags(toks, "message", "m")
    if not msgs:
        return  # editor, -F or --no-edit: nothing parseable here
    msg = "\n\n".join(msgs)
    head, _, body = msg.partition("\n")
    if head.startswith("Merge "):
        return
    e = L.lint_header(head, "commit header")
    if L.EM in body:
        e.append("commit body: contains an em dash")
    if not body.strip():
        e.append("commit: no body (explain what and why after a blank line)")
    if e:
        deny(e)


def gate_push(cmd, cwd):
    toks = tokens(cmd, r"git push\b")
    if toks is None or any(t in ("--delete", "-d", "--tags") or t.startswith(":") for t in toks):
        return
    branch = L.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd)
    base = L.default_base(cwd)
    if not branch or branch == "HEAD" or (base and base.split("/")[-1] == branch):
        return
    up = L.run(["git", "rev-parse", "--abbrev-ref", "@{u}"], cwd)
    rng = f"{up}..HEAD" if up else (f"{base}..HEAD" if base else "")
    if not rng:
        return
    e = L.lint_commits(L.commits_in(rng, cwd))
    if not up:
        e += L.lint_branch(branch, cwd)
    if e:
        deny(e + ["these commits are not pushed yet, so rewrite them now (git commit --amend, or "
                  "git reset --soft <base> && git commit); after the push it needs a force push"])


def gate_gh_pr(orig, cwd):
    cmd = sanitize(orig)
    toks = tokens(cmd, r"gh pr (?:create|edit)\b")
    if toks is None:
        return
    creating = toks[2] == "create"
    if "--web" in toks or "-w" in toks:
        return
    title, body = flag(toks, "title", "t"), flag(toks, "body", "b")
    bf = flag(toks, "body-file", "F")
    if bf and bf != "-" and Path(bf).is_file():
        body = Path(bf).read_text()
    if bf == "-":
        deny(["--body-file - (stdin) cannot be validated, write the body to a file"])
    if creating and (title is None or body is None):
        deny_body(title, [], cwd, extra=["gh pr create needs --title and --body/--body-file (no --fill/--web)"])
    if title is None and body is None:
        return
    e = L.lint_pr(title, body, cwd)
    if creating:
        base = L.default_base(cwd)
        e += L.lint_commits(L.commits_in(f"{base}..HEAD", cwd)) if base else []
    if e:
        if any(x.startswith("body") for x in e):
            deny_body(title, e, cwd)
        deny(e)
    if cmd != orig:
        allow_updated({"command": cmd})


def gate_mcp(name, ti, cwd):
    title, body = ti.get("title"), ti.get("body")
    creating = name.endswith("create_pull_request")
    if creating and (title is None or body is None):
        deny_body(title, [], cwd, extra=["create_pull_request needs title and body"])
    e = L.lint_pr(title, body, cwd)
    if e:
        if any(x.startswith("body") for x in e):
            deny_body(title, e, cwd)
        deny(e)


def main():
    p = json.load(sys.stdin)
    tool, ti, cwd = p.get("tool_name", ""), p.get("tool_input") or {}, p.get("cwd")
    if tool == "Bash":
        cmd = ti.get("command", "")
        try:
            gate_commit(cmd, cwd)
            gate_push(cmd, cwd)
            gate_gh_pr(cmd, cwd)
        except (ValueError, IndexError):
            pass  # unparseable shell: do not block on our own parsing limits
    elif tool.startswith("mcp__plugin_github_github__") and tool.endswith("_pull_request"):
        t, b = ti.get("title"), ti.get("body")
        st, sb = sanitize(t), sanitize(b)
        if st:
            st = st.rstrip(".")
        fixed = {**ti, **{k: v for k, v in (("title", st), ("body", sb)) if v is not None}}
        gate_mcp(tool, fixed, cwd)
        if fixed != ti:
            allow_updated(fixed)


main()
````

### `~/.claude/scripts/pr-lint-stop.sh`

````bash
#!/usr/bin/env bash
# Stop hook (safety net behind pr-gate-pretool.py): lint every PR this session
# created/edited with pr_lint.py. Closed/merged PRs are skipped, so a replaced
# PR no longer loops. Pass/fail comes from the linter exit code, not from text
# the model writes. Safety valve: MAX_ROUNDS blocks, then the stop is allowed.
set -u

[ "${FABLE_JUDGE_ACTIVE:-0}" = "1" ] && exit 0

MAX_ROUNDS=3
here="$(cd "$(dirname "$0")" && pwd)"

payload="$(cat)"
transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
[ -f "$transcript" ] || exit 0
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[ -n "$session_id" ] || exit 0

urls="$(python3 - "$transcript" <<'PYEOF'
import json, re, sys

CMD = re.compile(r'(^|[;&|(]\s*|\n\s*)gh pr (create|edit)\b')
MCP = re.compile(r'create_pull_request|update_pull_request')
URL = re.compile(r'https://github\.com/[\w.-]+/[\w.-]+/pull/\d+')
pr_calls, urls = set(), []
for line in open(sys.argv[1]):
    try:
        d = json.loads(line)
    except Exception:
        continue
    content = (d.get('message') or {}).get('content')
    if not isinstance(content, list):
        continue
    for b in content:
        if not isinstance(b, dict):
            continue
        if d.get('type') == 'assistant' and b.get('type') == 'tool_use':
            if CMD.search((b.get('input') or {}).get('command', '') or '') or MCP.search(b.get('name', '')):
                pr_calls.add(b.get('id'))
        elif d.get('type') == 'user' and b.get('type') == 'tool_result' and b.get('tool_use_id') in pr_calls:
            for u in URL.findall(json.dumps(b.get('content', ''))):
                if u not in urls:
                    urls.append(u)
print('\n'.join(urls))
PYEOF
)"
[ -n "$urls" ] || exit 0

errors=""
while read -r url; do
  [ -n "$url" ] || continue
  out="$(python3 "$here/pr_lint.py" url "$url" 2>&1)" || errors="$errors
$out"
done <<< "$urls"
state_file="/tmp/pr-lint-round-${session_id}"
if [ -z "$errors" ]; then rm -f "$state_file"; exit 0; fi

round="$(cat "$state_file" 2>/dev/null || echo 0)"
if [ "$round" -ge "$MAX_ROUNDS" ]; then
  rm -f "$state_file"
  jq -n --arg m "pr-lint: $MAX_ROUNDS rounds without a clean PR, allowing stop as a safety valve:$errors" '{systemMessage: $m}'
  exit 0
fi
printf '%s' $((round + 1)) > "$state_file"

jq -n --arg r "pr-lint: open PR(s) from this session break /git-guidelines (round $((round + 1))/$MAX_ROUNDS):$errors

Fix with 'gh pr edit' (title/body from the template). A bad commit already pushed cannot be fixed without force push: open a replacement PR from a new branch with compliant commits and close the old one. Do not claim compliance in text, the linter decides." \
  --arg m "
    🔎 pr-lint: PR breaks /git-guidelines (iteration $((round + 1))/$MAX_ROUNDS)$errors" \
  '{decision: "block", reason: $r, systemMessage: $m}'
````

### `~/.claude/scripts/fable-judge-stop.sh`

> Legado: não registrado em Stop desde 2026-10-25 (substituído por `quality-judge-stop.sh` e `llm-judge.sh`); fica no disco para rollback.

````bash
#!/usr/bin/env bash
# Stop hook: before Claude ends its turn, ask Fable (a different Claude
# model, acting as an independent LLM-as-judge) to score the turn 0-10.
# Two evidence modes:
#   - "diff" (original behavior): if the cwd is a git repo with a non-empty
#     diff, judge that diff for correctness bugs.
#   - "goal": if there's no diff but a /goal condition is active this
#     session (detected from the transcript), judge whether the goal was
#     satisfied, using the assistant's turn text/actions since the goal was
#     set as evidence. This covers non-code goals (investigations, system
#     fixes, etc.) that a git-diff-only judge would never see.
# Below threshold: block the stop so the current (non-Fable) model keeps
# iterating, until it scores >=7 or hits the round cap (safety valve
# against true infinite loops). On approval, it also asks the CURRENT
# model (not Fable, not a spawned agent: the same live session, via the
# same block-and-instruct mechanism that drives the iterate-until-approved
# loop) to persist session findings into the Obsidian vault once.
set -u

# Emits {"systemMessage": "..."} so the user sees this hook ran even on the
# silent/allow paths (systemMessage is shown to the user for all hooks,
# regardless of exit code: unlike hookSpecificOutput.additionalContext,
# which only reaches the model's context).
sysmsg() {
  jq -n --arg m "$1" '{systemMessage: $m}'
}

# Block the stop: "reason" goes to the model, "systemMessage" to the user.
block() {
  jq -n --arg r "$1" --arg m "$2" '{decision: "block", reason: ($m + "\n\n" + $r), systemMessage: $m}'
  exit 0
}

# Re-entrancy guard: the `claude -p` judge call below starts its own Claude
# Code session, which runs through this same global Stop hook on its own
# exit. Without this guard that recurses forever. The env var is inherited
# by that child session (and anything it spawns), so it short-circuits here.
[ "${FABLE_JUDGE_ACTIVE:-0}" = "1" ] && exit 0

THRESHOLD=7
MAX_ROUNDS=3
JUDGE_TIMEOUT=60

payload="$(cat)"

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0

transcript_path="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
# Pasta onde a sessao comecou (o cwd do payload muda com `cd` no meio da sessao)
origin_cwd="$(head -50 "$transcript_path" 2>/dev/null | jq -r '.cwd // empty' 2>/dev/null | head -1)"
[ -d "$origin_cwd" ] || origin_cwd="$cwd"

session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[ -n "$session_id" ] || session_id="$(printf '%s' "$payload" | jq -r '.transcript_path // "default"' | shasum | cut -d' ' -f1)"
state_file="/tmp/fable-judge-round-${session_id}"
persisted_flag="/tmp/fable-judge-persisted-${session_id}"

# Pasta do vault para esta sessao: sobe a partir de origin_cwd ate achar uma
# pasta com MEMORY.md no vault; ~ vira "renato".
vault_folder() {
  local folder d
  folder="$(basename "$origin_cwd")"
  d="$origin_cwd"
  while [ "$d" != "$HOME" ] && [ "$d" != "/" ]; do
    if [ -f "$HOME/Documents/Obsidian Vault/$(basename "$d")/MEMORY.md" ]; then folder="$(basename "$d")"; break; fi
    d="$(dirname "$d")"
  done
  [ "$origin_cwd" = "$HOME" ] && folder="renato"
  printf '%s' "$folder"
}

diff=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  diff="$(git diff HEAD -- . 2>/dev/null || git diff 2>/dev/null)"
  diff="$(printf '%s' "$diff" | head -c 20000)"
fi

goal_evidence_json=""
if [ -z "$diff" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  goal_evidence_json="$(python3 - "$transcript_path" <<'PYEOF'
import json, sys

path = sys.argv[1]
PREFIX = 'A session-scoped Stop hook is now active with condition: "'
CAP = 20000

lines = []
with open(path, 'r') as f:
    for line in f:
        line = line.strip()
        if line:
            lines.append(line)

goal = None
goal_idx = None
for i, line in enumerate(lines):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get('type') != 'user':
        continue
    content = (d.get('message') or {}).get('content')
    text = content if isinstance(content, str) else None
    if text is None and isinstance(content, list):
        parts = [b.get('text', '') for b in content if isinstance(b, dict) and b.get('type') == 'text']
        text = '\n'.join(parts)
    if not text or not text.startswith(PREFIX):
        continue
    rest = text[len(PREFIX):]
    end = rest.find('". ')
    goal = rest[:end] if end != -1 else rest
    goal_idx = i

if not goal:
    print(json.dumps({}))
    sys.exit(0)

pieces = []
for line in lines[goal_idx + 1:]:
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get('type') != 'assistant':
        continue
    content = (d.get('message') or {}).get('content')
    blocks_text = []
    if isinstance(content, str):
        blocks_text = [content]
    elif isinstance(content, list):
        for b in content:
            if not isinstance(b, dict):
                continue
            t = b.get('type')
            if t == 'text':
                blocks_text.append(b.get('text', ''))
            elif t == 'tool_use':
                blocks_text.append('[action: %s]' % b.get('name', 'tool'))
    for t in blocks_text:
        if not t:
            continue
        pieces.append(t)

# Keep the END of the excerpt: the most recent work is what the judge must see.
evidence = '\n\n'.join(pieces)[-CAP:]
print(json.dumps({'goal': goal, 'evidence': evidence}))
PYEOF
)"
fi

goal_text=""
evidence=""
if [ -n "$goal_evidence_json" ]; then
  goal_text="$(printf '%s' "$goal_evidence_json" | jq -r '.goal // empty')"
  evidence="$(printf '%s' "$goal_evidence_json" | jq -r '.evidence // empty')"
fi

if [ -n "$diff" ]; then
  mode="diff"
  evidence="$diff"
elif [ -n "$goal_text" ]; then
  mode="goal"
  [ -n "$evidence" ] || evidence="(no assistant text captured yet)"
else
  # Nothing to judge: no diff, no active goal. Sem juiz, mas persiste os
  # findings no vault uma vez por sessao (mesmo block-and-instruct da
  # aprovacao); o persisted_flag evita repetir e nao e apagado aqui.
  rm -f "$state_file"
  if [ ! -f "$persisted_flag" ]; then
    touch "$persisted_flag"
    folder="$(vault_folder)"
    block "fable-judge: nada para julgar (sem diff, sem goal ativo).
Antes de finalizar, persista os findings relevantes desta sessão no vault do Obsidian (\"$HOME/Documents/Obsidian Vault/$folder\"), conforme seu ~/.claude/CLAUDE.md (frontmatter padrão, atualize notas existentes em vez de duplicar, e o MEMORY.md daquela pasta; pule se nada vale guardar).
Depois pare novamente." \
      "
    ℹ️ Nada para julgar (sem diff, sem goal ativo)
        Persistindo findings da sessão no vault do Obsidian: $folder"
  fi
  sysmsg "fable-judge: nada para julgar (sem diff, sem goal ativo), findings já persistidos nesta sessão: parada liberada."
  exit 0
fi

model="$(tail -n 200 "$transcript_path" 2>/dev/null | jq -r 'select(.type=="assistant") | .message.model // empty' 2>/dev/null | grep -v '^<' | tail -1)"
[ -n "$model" ] || model="modelo da sessao"
# claude-sonnet-5-5[1m] -> Sonnet 5.5 [1M]
model="$(printf '%s' "$model" | sed -E 's/^claude-//;s/\[1m\]/ [1M]/;s/^([a-z]+)-([0-9]+)-([0-9]+)/\1 \2.\3/' | awk '{ $1=toupper(substr($1,1,1)) substr($1,2); print }')"

round="$(cat "$state_file" 2>/dev/null || echo 0)"
case "$round" in ''|*[!0-9]*) round=0 ;; esac

if [ "$round" -ge "$MAX_ROUNDS" ]; then
  printf 'fable-judge[%s]: hit %d review rounds without reaching a passing score: allowing stop as a safety valve.\n' "$mode" "$MAX_ROUNDS" >&2
  rm -f "$state_file"
  sysmsg "fable-judge[$mode]: hit $MAX_ROUNDS review rounds without a passing score: allowing stop as a safety valve."
  exit 0
fi

if [ "$mode" = "diff" ]; then
  prompt="You are an independent code reviewer acting as an LLM judge. Use the /code-review skill to review this diff (the working tree is the current directory) for real correctness bugs (not style/nits/opinions). Score it from 0 to 10 (10 = flawless/no bugs, 0 = fundamentally broken). Reply in EXACTLY this format, nothing else:
SCORE: <integer 0-10>
FEEDBACK: <short bullet list of the concrete bugs to fix, or 'none' if the score is 10>

--- DIFF ---
$evidence"
else
  prompt="You are an independent reviewer acting as an LLM judge. The user set this goal for the session:
\"$goal_text\"

Below is an excerpt of what the assistant did/said while working on it (text responses and [action: Tool] markers, in order). Score 0 to 10 how well the goal has been satisfied so far (10 = fully and correctly achieved, 0 = not addressed at all). Reply in EXACTLY this format, nothing else:
SCORE: <integer 0-10>
FEEDBACK: <short bullet list of what's missing or wrong, or 'none' if the score is 10>

--- TRANSCRIPT EXCERPT ---
$evidence"
fi

JUDGE_MODEL=claude-fable-5-1
FALLBACK_MODEL=claude-opus-5-5
judge_name="Fable 5.1"
judge() { printf '%s' "$prompt" | FABLE_JUDGE_ACTIVE=1 timeout "$JUDGE_TIMEOUT" claude -p --model "$JUDGE_MODEL" 2>/dev/null; }
# Tolerates "SCORE: 8", "**Score:** 8/10", "score - 8".
parse_score() { printf '%s' "$1" | grep -m1 -oiE 'score\W{0,6}[0-9]+' | grep -oE '[0-9]+$'; }
# Unavailable = empty reply (timeout/crash), or limit/outage text with no SCORE.
judge_unavailable() {
  [ -z "$1" ] && return 0
  ! printf '%s' "$1" | grep -qiE 'score\W{0,6}[0-9]' && printf '%s' "$1" | grep -qiE "reached your .*limit|usage limit|rate limit|overloaded|credits|try again later"
}

verdict="$(judge)"

# Primary judge unavailable: retry once with the fallback model (Opus 5.5).
# Only if that is also unavailable, fail open rather than block forever.
if judge_unavailable "$verdict"; then
  JUDGE_MODEL="$FALLBACK_MODEL"
  judge_name="Opus 5.5"
  verdict="$(judge)"
  if judge_unavailable "$verdict"; then
    rm -f "$state_file"
    sysmsg "fable-judge[$mode]: Fable and fallback Opus 5.5 both unavailable (limit/outage/timeout): failing open, stop allowed."
    exit 0
  fi
fi

score="$(parse_score "$verdict")"

# Unparsable score: retry once; if still unparsable, fail CLOSED as a counted round
# (the MAX_ROUNDS safety valve above still releases the stop eventually).
if [ -z "$score" ] && [ -n "$verdict" ]; then
  verdict="$(judge)"
  score="$(parse_score "$verdict")"
fi
if [ -z "$score" ] && [ -n "$verdict" ]; then
  printf '%s' "$verdict" > "/tmp/fable-judge-raw-${session_id}.txt"
  round=$((round + 1))
  printf '%s' "$round" > "$state_file"
  block "fable-judge[$mode]: judge reply unparsable twice (iteracao $round/$MAX_ROUNDS), raw reply in /tmp/fable-judge-raw-${session_id}.txt. Revise o que foi feito contra o objetivo e pare novamente para nova avaliacao." \
    "
    ⚠️ $judge_name respondeu fora do formato SCORE/FEEDBACK (iteração $round/$MAX_ROUNDS); reavaliando"
fi

feedback="$(printf '%s' "$verdict" | sed -n '/^FEEDBACK:/,$p' | sed '1s/^FEEDBACK:[[:space:]]*//' | sed '/^[[:space:]]*$/d' | sed 's/^/        /')"

if [ "$score" -ge "$THRESHOLD" ]; then
  rm -f "$state_file"

  if [ ! -f "$persisted_flag" ]; then
    touch "$persisted_flag"
    folder="$(vault_folder)"
    checks_msg=""
    checks_step=""
    if [ -f .pre-commit-config.yaml ] && command -v pre-commit >/dev/null 2>&1; then
      checks_msg="
        Executando pre-commit hooks"
      checks_step="Execute 'pre-commit run --all-files' e itere até todos os hooks passarem.
"
    fi
    test_cmd=""
    if [ -f pytest.ini ] || [ -f conftest.py ] || { [ -f pyproject.toml ] && grep -q pytest pyproject.toml; }; then test_cmd="pytest"
    elif [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then test_cmd="npm test"
    elif [ -f Makefile ] && grep -qE '^test:' Makefile; then test_cmd="make test"; fi
    if [ -n "$test_cmd" ]; then
      checks_msg="$checks_msg
        Executando testes ($test_cmd)"
      checks_step="${checks_step}Execute os testes ($test_cmd) e itere até todos passarem.
"
    fi
    git_msg="
        Sem mudanças em repositório git: pulando branch, commit, push e PR"
    git_step=""
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      git_msg="
        Fazendo commit, push, branch, PR obedecendo /git-guidelines"
      git_step="
Depois, como este diretorio e um repositorio git com mudancas, invoque a skill /git-guidelines (Skill tool) e siga-a para branch, commits, push e PR (cheque pull_request_template.md antes). Nunca commitar direto na default, sem atribuicao ao Claude, sem travessao, sem force push e sem mexer em branches alheias."
    fi
    block "fable-judge[$mode]: score $score/10, aprovado.
Antes de finalizar, ${checks_step}Persista os findings relevantes deste objetivo no vault do Obsidian (\"$HOME/Documents/Obsidian Vault/$folder\"), conforme seu ~/.claude/CLAUDE.md (frontmatter padrao, atualize notas existentes em vez de duplicar, e o MEMORY.md daquela pasta; pule se nada vale guardar).$git_step
Depois pare novamente." \
      "
    ✅ $judge_name avaliou a solução como adequada ($score/10):
$feedback$checks_msg
        Persistindo findings do objetivo no vault do Obsidian: $folder$git_msg"
  fi

  sysmsg "
    ✅ $judge_name avaliou a solução como adequada ($score/10)
        Findings já persistidos nesta sessão, parada liberada."
  exit 0
fi

round=$((round + 1))
printf '%s' "$round" > "$state_file"

block "fable-judge[$mode]: score $score/10 (minimo $THRESHOLD), iteracao $round/$MAX_ROUNDS. Continue iterando para corrigir estes gaps antes de parar:
$verdict" \
  "
    ❌ $judge_name avaliou a solução como insuficiente ($score/10) e precisa ser corrigido:
$feedback
        # Loop de até $MAX_ROUNDS iterações para corrigir os gaps, usando $model (iteração $round/$MAX_ROUNDS)"
````

### `~/.claude/scripts/qjs_transcript.py`

````python
#!/usr/bin/env python3
"""Transcript queries shared by quality-judge-stop.sh and llm-judge.sh.

Usage: qjs_transcript.py <turn|request|response|edits|goal> <transcript.jsonl>

turn      promptId of the current turn (uuid of its first entry on old transcripts)
request   text of that prompt
response  assistant text and [action: Tool] markers since that prompt
edits     number of Edit/Write/NotebookEdit tool calls since that prompt
goal      JSON {goal, evidence} when a /goal Stop condition is active, else {}

Hook feedback, skill bodies, "already loaded" reminders and tool results are
also stored as "user" entries; they share the turn's promptId, so none of
them can start a new turn and a Stop block never resets the state.
"""
import json
import sys
from typing import Any

CAP = 20000
GOAL_PREFIX = 'A session-scoped Stop hook is now active with condition: "'
# Fallback when a transcript has no origin field at all (older versions).
INJECTED = ("Base directory for this skill", "Stop hook feedback", "<system-reminder", "<local-command", "<command-")
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


def load(path: str) -> list[dict[str, Any]]:
    """Read a JSONL transcript, skipping unparsable lines."""
    entries: list[dict[str, Any]] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except ValueError:
                continue
    return entries


def text_of(content: Any) -> str:
    """Join the text blocks of a message content (str or list of blocks)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def last_human(entries: list[dict[str, Any]]) -> int:
    """Index of the first entry of the current turn, or -1.

    Claude Code stamps every entry of a turn (prompt, tool results, injected
    skill reminders, hook feedback) with the same promptId, so the turn starts
    at the first user entry carrying the last promptId. Without promptId
    (older transcripts) fall back to the last non-injected human prompt.
    """
    user = [(i, d) for i, d in enumerate(entries) if d.get("type") == "user" and not d.get("isSidechain")]
    for _, d in reversed(user):
        pid = d.get("promptId")
        if pid:
            return next(i for i, e in user if e.get("promptId") == pid)
    has_origin = any("origin" in d for _, d in user)
    for i, d in reversed(user):
        if d.get("isMeta") or d.get("turnCompanion"):
            continue
        text = text_of((d.get("message") or {}).get("content")).strip()
        if has_origin:
            if (d.get("origin") or {}).get("kind") == "human" and text:
                return i
        elif text and not text.startswith(INJECTED):
            return i
    return -1


def assistant_pieces(entries: list[dict[str, Any]], start: int) -> list[str]:
    """Assistant text blocks and tool markers after entries[start], in order."""
    pieces: list[str] = []
    for d in entries[start + 1:]:
        if d.get("type") != "assistant":
            continue
        content = (d.get("message") or {}).get("content")
        if isinstance(content, str):
            pieces.append(content)
        elif isinstance(content, list):
            for b in content:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and b.get("text"):
                    pieces.append(b["text"])
                elif b.get("type") == "tool_use":
                    pieces.append("[action: %s]" % b.get("name", "tool"))
    return pieces


def find_goal(entries: list[dict[str, Any]]) -> tuple[str, int] | None:
    """Last /goal condition set in the session, with the index of its message."""
    found: tuple[str, int] | None = None
    for i, d in enumerate(entries):
        if d.get("type") != "user":
            continue
        text = text_of((d.get("message") or {}).get("content"))
        if not text.startswith(GOAL_PREFIX):
            continue
        rest = text[len(GOAL_PREFIX):]
        end = rest.find('". ')
        found = (rest[:end] if end != -1 else rest, i)
    return found


def main(argv: list[str]) -> int:
    """Dispatch one query; prints the answer on stdout."""
    if len(argv) != 3 or argv[1] not in {"turn", "request", "response", "edits", "goal"}:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, path = argv[1], argv[2]
    try:
        entries = load(path)
    except OSError:
        entries = []
    idx = last_human(entries)

    if cmd == "turn":
        print((entries[idx].get("promptId") or entries[idx].get("uuid", "")) if idx >= 0 else "")
    elif cmd == "request":
        print(text_of((entries[idx].get("message") or {}).get("content")).strip() if idx >= 0 else "")
    elif cmd == "response":
        print("\n\n".join(assistant_pieces(entries, idx))[-CAP:])
    elif cmd == "edits":
        count = 0
        for d in entries[idx + 1:]:
            content = (d.get("message") or {}).get("content")
            if d.get("type") == "assistant" and isinstance(content, list):
                count += sum(1 for b in content if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in EDIT_TOOLS)
        print(count)
    else:  # goal
        goal = find_goal(entries)
        if goal is None:
            print(json.dumps({}))
        else:
            # Keep the END of the excerpt: the most recent work is what the judge must see.
            evidence = "\n\n".join(assistant_pieces(entries, goal[1]))[-CAP:]
            print(json.dumps({"goal": goal[0], "evidence": evidence}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
````

### `~/.claude/scripts/quality-gate.sh`

````bash
#!/usr/bin/env bash
# Deterministic quality gate: schema, lint/types/tests, secrets.
# Runs over the files changed in the current git repo (diff vs HEAD plus
# untracked) and the project the cwd belongs to. Fast, free, no LLM.
# Writes <state>/gate.json ({turn, pass, checks, ts}); exit 0 = pass, 1 = fail.
# Usage: quality-gate.sh [--state DIR] [--turn ID] [--cwd DIR]
set -u
PATH="/opt/homebrew/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=feedback-loop-lib.sh
source "$SCRIPT_DIR/feedback-loop-lib.sh"

state="/tmp/qjs-manual"; turn="manual"; cwd="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state="$2"; shift 2 ;;
    --turn) turn="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$state"
cd "$cwd" || { echo "quality-gate: cwd not found: $cwd" >&2; exit 2; }

checks_file="$(mktemp)"
trap 'rm -f "$checks_file"' EXIT
add_check() { jq -nc --arg n "$1" --arg s "$2" --arg d "$3" '{name:$n,status:$s,detail:$d}' >> "$checks_file"; }

# Changed files, relative to the git root (diff HEAD, falling back to the
# index on a repo with no commits yet, plus untracked-not-ignored).
root=""; changed=""
if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  changed="$({ git -C "$root" diff --name-only HEAD 2>/dev/null || git -C "$root" diff --name-only --cached 2>/dev/null
               git -C "$root" ls-files --others --exclude-standard 2>/dev/null; } | sort -u | sed '/^$/d')"
fi

check_schema() {
  if [ -z "$changed" ]; then add_check schema na "no changed files"; return; fi
  bad=""; n=0
  while IFS= read -r f; do
    p="$root/$f"; [ -f "$p" ] || continue
    case "$f" in
      # ponytail: these formats allow comments, so strict JSON parsing would false-fail them
      */tsconfig*.json|tsconfig*.json|*/jsconfig*.json|jsconfig*.json|*.jsonc|*/.eslintrc*|.eslintrc*|*/.vscode/*|.vscode/*) continue ;;
      *.json) n=$((n+1)); err="$(jq empty "$p" 2>&1)" || bad="${bad}${f}: ${err}"$'\n' ;;
      *.yaml|*.yml)
        n=$((n+1))
        err="$(python3 -I -c 'import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
list(yaml.safe_load_all(open(sys.argv[1])))' "$p" 2>&1)" || bad="${bad}${f}: $(printf '%s' "$err" | tail -n 1)"$'\n' ;;
      *.toml)
        n=$((n+1))
        err="$(python3 -I -c 'import sys
try:
    import tomllib
except ImportError:
    sys.exit(0)
tomllib.load(open(sys.argv[1], "rb"))' "$p" 2>&1)" || bad="${bad}${f}: $(printf '%s' "$err" | tail -n 1)"$'\n' ;;
    esac
  done <<< "$changed"
  if [ -n "$bad" ]; then add_check schema fail "$bad"
  elif [ "$n" -eq 0 ]; then add_check schema na "no json/yaml/toml among changed files"
  else add_check schema ok "$n file(s) well-formed (syntax only)"; fi
}

check_project() {
  if ! find_project_root "$cwd"; then
    add_check lint-types-tests na "no project marker (package.json, pyproject.toml, go.mod, Cargo.toml) above $cwd"
    return
  fi
  cd "$project_root" || { add_check lint-types-tests na "cannot enter $project_root"; return; }
  run_checks
  cd "$cwd" || true
  if [ -n "$failures" ]; then add_check lint-types-tests fail "$(printf '%b' "$failures")"
  else add_check lint-types-tests ok "$marker project at $project_root"; fi
}

check_precommit() {
  if [ -z "$changed" ] || [ ! -f "$root/.pre-commit-config.yaml" ] || ! command -v pre-commit >/dev/null 2>&1; then
    add_check pre-commit na "no changed files, no .pre-commit-config.yaml, or pre-commit not installed"
    return
  fi
  out_file="$(mktemp)"
  files=(); while IFS= read -r f; do [ -f "$root/$f" ] && files+=("$f"); done <<< "$changed"
  # pre-commit may reformat files and exit 1 on the first run; the second run then passes.
  ( cd "$root" && run_with_timeout 120 pre-commit run --files "${files[@]}" ); rc=$?
  if [ "$rc" -eq 0 ]; then add_check pre-commit ok "hooks passed on ${#files[@]} file(s)"
  else add_check pre-commit fail "exit $rc"$'\n'"$(tail -c 3000 "$out_file")"; fi
  rm -f "$out_file"
}

check_secrets() {
  if [ -z "$changed" ]; then add_check secrets na "no changed files"; return; fi
  hits=""
  # Versioned env files (templates are fine).
  while IFS= read -r f; do
    case "$f" in
      *.env.example|*.env.sample|*.env.template) ;;
      .env|.env.*|*/.env|*/.env.*) hits="${hits}${f}: env file in the change set"$'\n' ;;
    esac
  done <<< "$changed"
  if command -v gitleaks >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    # Copy only the changed files so gitleaks scans exactly them.
    printf '%s\n' "$changed" | tar -C "$root" -cf - -T - 2>/dev/null | tar -C "$tmp" -xf - 2>/dev/null
    gl="$(gitleaks detect --no-git --source "$tmp" --no-banner --redact 2>&1)" || hits="${hits}gitleaks: $(printf '%s' "$gl" | tail -n 15)"$'\n'
    rm -rf "$tmp"
    engine="gitleaks"
  else
    # ponytail: regex scan has a coverage ceiling, install gitleaks (brew install gitleaks) for real coverage
    engine="regex (gitleaks not installed)"
    pats=(
      'aws-key::AKIA[0-9A-Z]{16}'
      'github-token::gh[pousr]_[A-Za-z0-9]{36}'
      'github-pat::github_pat_[A-Za-z0-9_]{22,}'
      'sk-key::(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}'
      'slack-token::xox[baprs]-[A-Za-z0-9-]{10,}'
      'google-key::AIza[0-9A-Za-z_-]{35}'
      'private-key::-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
    )
    while IFS= read -r f; do
      p="$root/$f"; [ -f "$p" ] || continue
      for entry in "${pats[@]}"; do
        # Report file and line only, never the matched value.
        lines="$(grep -nIE -e "${entry#*::}" "$p" 2>/dev/null | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')"
        [ -n "$lines" ] && hits="${hits}${f}:${lines}: possible secret (${entry%%::*})"$'\n'
      done
    done <<< "$changed"
  fi
  if [ -n "$hits" ]; then add_check secrets fail "$hits"
  else add_check secrets ok "scanned changed files with $engine"; fi
}

check_schema
check_project
check_precommit
check_secrets

tmp_json="$(mktemp "$state/.gate.XXXXXX")"
jq -s --arg turn "$turn" --arg ts "$(date -u +%FT%TZ)" \
  '{turn:$turn, pass:(all(.[]; .status != "fail")), checks:., ts:$ts}' "$checks_file" > "$tmp_json" \
  && mv "$tmp_json" "$state/gate.json"

jq -r '.checks[] | "\(.name): \(.status)" + (if .status == "fail" then "\n" + .detail else "" end)' "$state/gate.json"
if [ "$(jq -r '.pass' "$state/gate.json")" = "true" ]; then echo "GATE: PASS"; exit 0; fi
echo "GATE: FAIL"; exit 1
````

### `~/.claude/scripts/llm-judge.sh`

````bash
#!/usr/bin/env bash
# LLM-as-judge: scores the turn 0-10 with Fable 5.1 (fallback Opus 5.5).
# Only runs after quality-gate.sh passed for the same turn (exit 3 otherwise).
# Evidence modes: diff (git diff vs HEAD), goal (active /goal), response
# (last request vs last answer). Writes <state>/judge.json; exit 0 = pass, 1 = fail.
# Usage: llm-judge.sh --state DIR --turn ID --transcript PATH [--cwd DIR]
set -u
PATH="/opt/homebrew/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

THRESHOLD=7
JUDGE_TIMEOUT=60
JUDGE_MODEL=claude-fable-5-1
FALLBACK_MODEL=claude-opus-5-5
judge_name="Fable 5.1"

state="/tmp/qjs-manual"; turn="manual"; transcript=""; cwd="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state="$2"; shift 2 ;;
    --turn) turn="$2"; shift 2 ;;
    --transcript) transcript="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$state"
cd "$cwd" || { echo "llm-judge: cwd not found: $cwd" >&2; exit 2; }

# Order is enforced here, not by the prompt: no gate pass for this turn, no judge.
if [ "$(jq -r --arg t "$turn" 'select(.turn == $t) | .pass' "$state/gate.json" 2>/dev/null)" != "true" ]; then
  echo "llm-judge: quality-gate has not passed for turn $turn. Run /quality-gate first." >&2
  exit 3
fi

tq() { [ -f "$transcript" ] && python3 -I "$SCRIPT_DIR/qjs_transcript.py" "$1" "$transcript"; }
request="$(tq request)"

diff=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  diff="$(git diff HEAD -- . 2>/dev/null || git diff 2>/dev/null)"
  diff="$(printf '%s' "$diff" | head -c 20000)"
fi
goal_json="$(tq goal)"; [ -n "$goal_json" ] || goal_json='{}'
goal_text="$(printf '%s' "$goal_json" | jq -r '.goal // empty')"

FMT='Reply in EXACTLY this format, nothing else:
SCORE: <integer 0-10>
FEEDBACK: <short bullet list of what to fix, or '"'none'"' if the score is 10>'

if [ -n "$diff" ]; then
  mode="diff"
  prompt="You are an independent code reviewer acting as an LLM judge. Use the /code-review skill to review this diff (the working tree is the current directory) for real correctness bugs (not style/nits/opinions). Also check that the diff does what the user asked for.
The user's request was:
\"$request\"

Score it from 0 to 10 (10 = flawless and does what was asked, 0 = fundamentally broken or off-request). $FMT

--- DIFF ---
$diff"
elif [ -n "$goal_text" ]; then
  mode="goal"
  evidence="$(printf '%s' "$goal_json" | jq -r '.evidence // empty')"
  prompt="You are an independent reviewer acting as an LLM judge. The user set this goal for the session:
\"$goal_text\"

Below is an excerpt of what the assistant did/said while working on it (text responses and [action: Tool] markers, in order). Score 0 to 10 how well the goal has been satisfied so far (10 = fully and correctly achieved, 0 = not addressed at all). $FMT

--- TRANSCRIPT EXCERPT ---
$evidence"
else
  mode="response"
  response="$(tq response)"
  prompt="You are an independent reviewer acting as an LLM judge. Below are the user's last request and the assistant's answer. Score 0 to 10 whether the answer follows the request (correct, complete, on topic) and whether the tone fits the user (10 = excellent, 0 = off-request or wrong). Do not reward length. $FMT

--- USER REQUEST ---
$request

--- ASSISTANT ANSWER (text and [action: Tool] markers) ---
${response:-(no assistant text captured)}"
fi

TO="$(command -v timeout || command -v gtimeout || true)"
judge() { printf '%s' "$prompt" | FABLE_JUDGE_ACTIVE=1 ${TO:+"$TO" "$JUDGE_TIMEOUT"} claude -p --model "$JUDGE_MODEL" 2>/dev/null; }
# Tolerates "SCORE: 8", "**Score:** 8/10", "score - 8".
parse_score() { printf '%s' "$1" | grep -m1 -oiE 'score\W{0,6}[0-9]+' | grep -oE '[0-9]+$'; }
# Unavailable = empty reply (timeout/crash), or limit/outage text with no SCORE.
judge_unavailable() {
  [ -z "$1" ] && return 0
  ! printf '%s' "$1" | grep -qiE 'score\W{0,6}[0-9]' && printf '%s' "$1" | grep -qiE "reached your .*limit|usage limit|rate limit|overloaded|credits|try again later"
}

write_result() {  # score(or "") pass judge feedback
  jq -nc --arg turn "$turn" --arg mode "$mode" --arg score "$1" --argjson pass "$2" --arg judge "$3" --arg fb "$4" \
    '{turn:$turn, mode:$mode, score:(if $score == "" then null else ($score|tonumber) end), pass:$pass, judge:$judge, feedback:$fb}' \
    > "$state/judge.json.tmp" && mv "$state/judge.json.tmp" "$state/judge.json"
}

verdict="$(judge)"
if judge_unavailable "$verdict"; then
  JUDGE_MODEL="$FALLBACK_MODEL"; judge_name="Opus 5.5"
  verdict="$(judge)"
  if judge_unavailable "$verdict"; then
    write_result "" true "unavailable" "Fable and fallback Opus 5.5 both unavailable (limit/outage/timeout): failing open."
    echo "JUDGE: unavailable (Fable and Opus 5.5), failing open"; exit 0
  fi
fi

score="$(parse_score "$verdict")"
if [ -z "$score" ]; then verdict="$(judge)"; score="$(parse_score "$verdict")"; fi
if [ -z "$score" ]; then
  printf '%s' "$verdict" > "$state/judge-raw.txt"
  write_result "" false "$judge_name" "Judge reply unparsable twice (raw in $state/judge-raw.txt). Run /llm-as-judge again."
  echo "JUDGE: $judge_name reply unparsable twice, raw in $state/judge-raw.txt"; exit 1
fi

feedback="$(printf '%s' "$verdict" | sed -n '/^FEEDBACK:/,$p' | sed '1s/^FEEDBACK:[[:space:]]*//' | sed '/^[[:space:]]*$/d')"
if [ "$score" -ge "$THRESHOLD" ]; then pass=true; else pass=false; fi
write_result "$score" "$pass" "$judge_name" "$feedback"
echo "JUDGE[$mode]: $judge_name scored $score/10 ($([ "$pass" = true ] && echo PASS || echo FAIL), minimum $THRESHOLD)"
[ -n "$feedback" ] && printf '%s\n' "$feedback"
[ "$pass" = true ]
````

### `~/.claude/scripts/quality-judge-stop.sh`

````bash
#!/usr/bin/env bash
# Stop hook: on EVERY stop, make the session run /quality-gate (deterministic
# checks) and then /llm-as-judge (Fable 5.1, fallback Opus 5.5), and only
# release the stop once both left a passing result for this turn.
# A hook cannot load a skill, so it blocks and instructs the model to call
# the Skill tool. Pass/fail never comes from what the model writes: it comes
# from <state>/gate.json and <state>/judge.json, produced by quality-gate.sh
# and llm-judge.sh and stamped with the turn id (promptId of the current turn).
# Flow per turn:
#   no gate.json            -> block: run /quality-gate, then /llm-as-judge
#   gate fail               -> block: fix and rerun (counts a failed round)
#   gate ok, no judge.json  -> block: run /llm-as-judge
#   judge fail              -> block: iterate with the session model, rerun both
#   both ok, code task      -> block once: ask commit / branch / PR via /git-guidelines
#   both ok                 -> block once: persist findings in the Obsidian vault
#   done                    -> release
# Safety valves: 3 failed rounds or 8 blocks in one turn release with a warning.
set -u

# The judge's own `claude -p` session runs through this global hook on exit.
[ "${FABLE_JUDGE_ACTIVE:-0}" = "1" ] && exit 0

PATH="/opt/homebrew/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_FAIL_ROUNDS=3
MAX_BLOCKS=8

# "systemMessage" is shown to the user on every path; "reason" goes to the model.
sysmsg() { jq -n --arg m "$1" '{systemMessage: $m}'; exit 0; }

payload="$(cat)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0
transcript_path="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[ -n "$session_id" ] || session_id="$(printf '%s' "$transcript_path" | shasum | cut -d' ' -f1)"

state="/tmp/qjs-${session_id}"
mkdir -p "$state"

tq() { python3 -I "$SCRIPT_DIR/qjs_transcript.py" "$1" "$transcript_path" 2>/dev/null; }
turn="$(tq turn)"
[ -n "$turn" ] || sysmsg "quality-judge: no human prompt found in the transcript, nothing to verify: stop allowed."

# New turn: reset counters and flags. gate.json/judge.json carry their own turn id, so stale ones
# are ignored and a gate the user ran before the first Stop still counts. persisted_session survives.
if [ "$(cat "$state/turn" 2>/dev/null)" != "$turn" ]; then
  rm -f "$state"/judge-raw.txt "$state"/git_asked "$state"/persisted_turn "$state"/fail_rounds "$state"/blocks
  printf '%s' "$turn" > "$state/turn"
fi

counter() { local v; v="$(cat "$state/$1" 2>/dev/null)"; case "$v" in ''|*[!0-9]*) v=0 ;; esac; printf '%s' "$v"; }
bump() { printf '%s' "$(( $(counter "$1") + 1 ))" > "$state/$1"; }

blocks="$(counter blocks)"; fail_rounds="$(counter fail_rounds)"
if [ "$blocks" -ge "$MAX_BLOCKS" ] || [ "$fail_rounds" -ge "$MAX_FAIL_ROUNDS" ]; then
  sysmsg "
    ⚠️ quality-judge: round limit reached this turn ($fail_rounds failures, $blocks blocks): stop allowed as a safety valve.
        Review manually what is still pending."
fi

BANNER="
    Running quality gate with /quality-gate
    Running llm-as-judge with /llm-as-judge # Using Fable 5.1 with fallback to Opus 5.5."

block() {  # reason, user message
  bump blocks
  jq -n --arg r "$1" --arg m "$2" '{decision: "block", reason: ($m + "\n\n" + $r), systemMessage: $m}'
  exit 0
}

q() { printf '%q' "$1"; }
GATE_CMD="$SCRIPT_DIR/quality-gate.sh --state $(q "$state") --turn $turn --cwd $(q "$cwd")"
JUDGE_CMD="$SCRIPT_DIR/llm-judge.sh --state $(q "$state") --turn $turn --transcript $(q "$transcript_path") --cwd $(q "$cwd")"

# Same vault folder rule as goal-start-trigger.sh: climb from where the session
# started to the first folder with a MEMORY.md; ~ is "renato".
origin_cwd="$(head -50 "$transcript_path" 2>/dev/null | jq -r '.cwd // empty' 2>/dev/null | head -1)"
[ -d "$origin_cwd" ] || origin_cwd="$cwd"
vault_folder() {
  local folder d
  folder="$(basename "$origin_cwd")"
  d="$origin_cwd"
  while [ "$d" != "$HOME" ] && [ "$d" != "/" ]; do
    if [ -f "$HOME/Documents/Obsidian Vault/$(basename "$d")/MEMORY.md" ]; then folder="$(basename "$d")"; break; fi
    d="$(dirname "$d")"
  done
  [ "$origin_cwd" = "$HOME" ] && folder="renato"
  printf '%s' "$folder"
}

result() { jq -r --arg t "$turn" "select(.turn == \$t) | $2" "$state/$1" 2>/dev/null; }
gate_pass="$(result gate.json '.pass')"
judge_pass="$(result judge.json '.pass')"

# 1. Nothing ran yet this turn.
if [ -z "$gate_pass" ]; then
  block "quality-judge: run both skills now, in this order. This applies to every Stop.
1. Call the Skill tool with \"quality-gate\" and run (Bash, timeout 300000): $GATE_CMD
   If it fails, fix the root cause (do not edit a test to make it pass, do not silence a rule) and rerun until it passes.
2. Only then call the Skill tool with \"llm-as-judge\" and run (Bash, timeout 300000): $JUDGE_CMD
3. Stop again. The hook checks this turn's gate.json and judge.json; text you write saying it passed does not count." \
    "$BANNER"
fi

# 2. Gate failed.
if [ "$gate_pass" = "false" ]; then
  bump fail_rounds
  failures="$(jq -r '.checks[] | select(.status == "fail") | "- " + .name + ": " + .detail' "$state/gate.json" 2>/dev/null | head -c 3000)"
  block "quality-judge: the quality gate failed. Fix the root cause and rerun: $GATE_CMD
$failures" \
    "
    ❌ /quality-gate failed (round $(counter fail_rounds)/$MAX_FAIL_ROUNDS), iterating again:
$(printf '%s' "$failures" | sed 's/^/        /')"
fi

# 3. Gate passed, judge not run yet.
if [ -z "$judge_pass" ]; then
  block "quality-judge: the gate passed. Now call the Skill tool with \"llm-as-judge\" and run (Bash, timeout 300000): $JUDGE_CMD" \
    "$BANNER"
fi

# 4. Judge failed: iterate with the session model, then both must run again.
if [ "$judge_pass" = "false" ]; then
  bump fail_rounds
  verdict="$(jq -r '"score " + ((.score // "n/a")|tostring) + "/10 (" + .judge + "):\n" + .feedback' "$state/judge.json" 2>/dev/null)"
  model="$(tail -n 200 "$transcript_path" 2>/dev/null | jq -r 'select(.type=="assistant") | .message.model // empty' 2>/dev/null | grep -v '^<' | tail -1)"
  [ -n "$model" ] || model="session model"
  # claude-sonnet-5-5[1m] -> Sonnet 5.5 [1M]
  model="$(printf '%s' "$model" | sed -E 's/^claude-//;s/\[1m\]/ [1M]/;s/^([a-z]+)-([0-9]+)-([0-9]+)/\1 \2.\3/' | awk '{ $1=toupper(substr($1,1,1)) substr($1,2); print }')"
  rm -f "$state/gate.json" "$state/judge.json"
  block "quality-judge: the judge failed it ($verdict)
Fix the gaps with the session model and rerun, in this order: $GATE_CMD  then  $JUDGE_CMD" \
    "
    ❌ /llm-as-judge failed:
$(printf '%s' "$verdict" | sed 's/^/        /')
        # Loop of up to $MAX_FAIL_ROUNDS iterations with $model (iteration $(counter fail_rounds)/$MAX_FAIL_ROUNDS)"
fi

# 5. Both passed. Code task in a git repo: ask commit / branch / PR once.
edits="$(tq edits)"; edits="${edits:-0}"
code_task=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  { [ -n "$(git status --porcelain 2>/dev/null)" ] || [ "$edits" -gt 0 ]; } && code_task=1
fi
if [ "$code_task" = 1 ] && [ ! -f "$state/git_asked" ]; then
  touch "$state/git_asked"
  block "quality-judge: the gate and the judge approved a code task. Before stopping, ask the user the 3 questions in ONE AskUserQuestion call: (1) Make a commit? (2) Create a branch? (3) Prepare a PR?
If the user accepts any of them, call the Skill tool with \"git-guidelines\" and follow it strictly (branch, commit, PR title and description; check pull_request_template.md first). Never commit directly to the default branch, no Claude attribution, no em dashes, no force push, do not touch branches that are not yours. Merge and deploy still require confirmation.
If the user declines everything, stop." \
    "
    ✅ Gate and judge approved (code changed)
        Asking the user: commit? branch? PR? (following /git-guidelines)"
fi

# 6. Persist findings in the vault once: per turn when something was checked,
# per session on empty turns (so plain Q&A does not ask for a note every time).
all_na="$(jq -r 'all(.checks[]; .status == "na")' "$state/gate.json" 2>/dev/null)"
judge_mode="$(jq -r '.mode // empty' "$state/judge.json" 2>/dev/null)"
if [ "$all_na" = "true" ] && [ "$judge_mode" = "response" ] && [ "$code_task" = 0 ]; then
  flag="$state/persisted_session"
else
  flag="$state/persisted_turn"
fi
if [ ! -f "$flag" ]; then
  touch "$flag"
  folder="$(vault_folder)"
  block "quality-judge: the gate and the judge approved. Before finishing, persist this turn's relevant findings in the Obsidian vault (\"$HOME/Documents/Obsidian Vault/$folder\"), per your ~/.claude/CLAUDE.md (standard name/description/metadata.type frontmatter, update an existing note instead of duplicating, and the MEMORY.md line of that folder; test that the directory accepts writes before claiming you saved; skip if nothing is worth keeping). Then stop again." \
    "
    ✅ Gate and judge approved
        Persisting findings in the Obsidian vault: $folder"
fi

# 7. Done.
summary="$(jq -r '[.checks[] | .name + ": " + .status] | join(" | ")' "$state/gate.json" 2>/dev/null)"
judge_line="$(jq -r '(.judge) + " " + ((.score // "n/a")|tostring) + "/10 (" + (.mode) + ")"' "$state/judge.json" 2>/dev/null)"
sysmsg "
    ✅ quality-gate: $summary
    ✅ llm-as-judge: $judge_line
        Findings already persisted, stop allowed."
````

### `~/.claude/scripts/cc-status-safe.py`

````python
#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys

CC_STATUS = "/Users/renato.pereira/.config/iterm2/cc-status"
payload = sys.stdin.buffer.read()

try:
    event_name = json.loads(payload).get("hook_event_name", "")
except (json.JSONDecodeError, AttributeError):
    event_name = ""

if not os.environ.get("ITERM2_COOKIE") or not os.environ.get("ITERM2_KEY"):
    if event_name == "SessionStart":
        sys.stderr.write(
            "cc-status: skipped because ITERM2_COOKIE and ITERM2_KEY are unset; "
            "it2 would wait for interactive AppleScript authorization.\n"
        )
    sys.exit(0)

process = subprocess.Popen(
    [CC_STATUS],
    stdin=subprocess.PIPE,
    start_new_session=True,
)
try:
    process.communicate(payload, timeout=5)
except subprocess.TimeoutExpired:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    if event_name in {"SessionStart", "SessionEnd"}:
        sys.stderr.write("cc-status: iTerm API did not respond within 5 seconds.\n")

sys.exit(0)
````

### `~/.claude/skills/git-guidelines/SKILL.md`

````markdown
---
name: git-guidelines
description: Use when naming a branch, writing a commit message, titling a PR or drafting a PR description. Applies Conventional Commits and git best practices, output in EN-US. Trigger on /git-guidelines, "PR template", "commit message", "branch name", "PR description".
---

# /git-guidelines

Produce branch name, commit message, PR title and PR description in **EN-US**, following the rules below. If the user passes context (diff, ticket, summary), fill the templates with it; otherwise show the blank templates. Never use em dashes.

## Branch name

```
<type>/[<ticket-id>-]<short-kebab-description>
```

The ticket id is optional. Examples: `feat/PROJ-123-add-oauth-login`, `fix/PROJ-456-null-user-on-checkout`, `chore/bump-0.1.82`

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

## Commit message (Conventional Commits)

```
<type>(<scope>): <imperative summary, max 72 chars, no period>

<body: what and why, wrapped at 72 chars>

BREAKING CHANGE: <description, only if applicable>
Refs: PROJ-123 (optional)
```

- The `(<scope>)` is mandatory (`feat(auth): ...`, never `feat: ...`): the module, area or component touched.
- Imperative mood ("add", not "added").
- One logical change per commit.
- Use `!` after the type (`feat(api)!:`) for breaking changes.

## PR title

Same format as the commit header, scope included, because it becomes the squash commit. The ticket suffix is optional. The 72-char limit applies, ticket included:

```
feat(auth): add OAuth2 login with Google (PROJ-123)
```

## PR description

```markdown
## Summary
<!-- What does this PR do and why? 1-3 sentences. -->

## Type of change
- [ ] feat (new feature)
- [ ] fix (bug fix)
- [ ] refactor / perf
- [ ] docs / test / chore / ci
- [ ] Breaking change

## Related issues
Closes #123

## Changes
- Added ...
- Changed ...
- Removed ...

## How to test
1. Check out the branch
2. Run `...`
3. Expected result: ...

## Screenshots / logs (if applicable)

## Risks and rollback
<!-- Impact, migrations, feature flags. How to revert safely. -->

## Checklist
- [ ] Title follows Conventional Commits
- [ ] Branch is up to date with the base branch
- [ ] Tests added or updated and passing
- [ ] Lint and type checks pass
- [ ] Docs / changelog updated
- [ ] No secrets or debug code committed
- [ ] Self-reviewed the diff
```

If the repo has `.github/pull_request_template.md`, use it instead of the block above.

## Best practices

- Small PRs (under ~400 changed lines), one purpose each.
- Rebase on the base branch before merge to keep history linear.
- Squash merge when branch commits are noisy; the PR title becomes the message.
- Open a draft PR for work in progress.
- Protect `main`: required review and green CI.
````

### `~/.claude/skills/attack-protection/SKILL.md`

````markdown
---
name: attack-protection
description: Use when writing, changing or reviewing any code that handles user input, renders HTML, exposes API routes, uses secrets or API keys, touches a database, calls an LLM, or adds dependencies. Builds code defensively against 8 attacks (XSS, exposed API routes, exposed API keys, open database, SQL injection, no rate limit, prompt injection, hallucinated packages). Trigger on /attack-protection, "hardening", "security checklist".
---

# /attack-protection

Write (or review) code so the 8 attacks below fail by construction. Before finishing, walk the 8 checks against the code touched and fix every miss. If invoked with a file, diff or path, audit it and report per attack: OK, FIXED or RISK (with file:line). Never use em dashes.

## 1. XSS
- Never insert user data as HTML: no `innerHTML`, `dangerouslySetInnerHTML`, `v-html`, `document.write`, `eval`, `javascript:` URLs. Use `textContent` or the framework's default escaping.
- If HTML from users is unavoidable, sanitize with DOMPurify (allowlist tags).
- Add a CSP header (`default-src 'self'`, no `unsafe-inline`), cookies `HttpOnly; Secure; SameSite=Lax`, and `X-Content-Type-Options: nosniff`.
- Escape on output for the exact context (HTML, attribute, JS, URL).

## 2. Exposed API routes
- Every route is private by default: authenticate first, then authorize the specific resource (owner/role check, prevents IDOR).
- Deny by default; public routes are an explicit allowlist.
- Validate body, query and params with a schema (zod, pydantic) and reject unknown fields.
- Restrict CORS to known origins (never `*` with credentials). Protect state-changing cookie-auth routes against CSRF.
- Return generic errors; no stack traces, no internal IDs or enumeration hints. Disable debug/docs endpoints in production.

## 3. Exposed API keys
- Secrets only from env vars or a secret manager. Never hardcode, never in client bundles (`NEXT_PUBLIC_`, `VITE_`, etc. are public), never in logs, URLs or error messages.
- Calls needing a secret go through a backend/proxy; the browser gets short-lived tokens at most.
- `.env*` in `.gitignore`; commit only `.env.example` with placeholders. Add a secret scan (gitleaks/trufflehog) to pre-commit or CI.
- If a key was ever committed or pasted, treat it as leaked: rotate it, do not just delete it.

## 4. Open database
- Never expose the DB to the internet: private network or localhost, firewall, no default creds, TLS on.
- Least privilege: the app user gets only the grants it needs (no superuser, no DDL at runtime).
- Row-level security / per-tenant filters on every query (Supabase/Firebase rules must be on, never "allow all").
- Encrypt backups, hash passwords with argon2/bcrypt, never store plaintext secrets or card data.

## 5. SQL injection
- Parameterized queries or ORM query builders only. Never build SQL with string concat, f-strings or template literals.
- Identifiers (table/column/order by) cannot be parameterized: map them from a fixed allowlist.
- Apply the same to NoSQL operators (`$where`, `$ne` from user JSON) and shell/ORM raw escape hatches.

## 6. No attempt limit
- Rate limit every route by IP and by account; tight limits on login, signup, password reset, OTP, and any costly or LLM endpoint.
- Login: exponential backoff or temporary lockout after N failures, same error for unknown user and wrong password, CAPTCHA after repeated failures.
- OTP/reset tokens: short expiry, single use, attempt cap.
- Cap request body size, pagination size and timeouts.

## 7. Prompt injection
- Treat all external text (user input, web pages, files, emails, tool results, RAG docs) as data, never as instructions. Keep it in separate, delimited message parts, not concatenated into the system prompt.
- Least privilege for tools: allowlist tools, no destructive or outbound action (send, delete, pay, shell) without human confirmation; never let model output reach `eval`, shell or SQL unvalidated.
- Validate and schema-check model output; strip or block markdown images/links that could exfiltrate data to external URLs.
- Never put secrets in prompts; scope the model's data access to the current user.

## 8. Invented (hallucinated) packages
- Never add a dependency from memory. Verify it exists on the registry (`npm view <pkg>`, `pip index versions <pkg>`), check publisher, download count, repo link and age. Beware typosquats (one-letter variants of popular names).
- Prefer stdlib or an already-installed dependency. Pin versions, commit the lockfile, install with `npm ci` / `pip install --require-hashes` when possible.
- Run `npm audit` / `pip-audit` in CI. If a package cannot be verified, do not install it; tell the user.

## Output when writing code
After the code, add one line per attack touched, e.g. `XSS: textContent only | Routes: authz on /orders/:id | Keys: env only | DB: parameterized | Rate: 5/min login | Prompt: input delimited | Pkgs: verified on npm`. Mark any attack not applicable as `n/a`. Anything you could not guarantee goes under `RISK` with the reason.
````

### `~/.claude/skills/programming-best-practices/SKILL.md`

`````markdown
---
name: programming-best-practices
description: Use when writing, changing or reviewing code in any language. Applies TDD, SOLID without speculative abstraction, complete static typing, Google Style docstrings, linting and proper logging instead of print. Trigger on /programming-best-practices, "best practices", "TDD", "SOLID", "typing", "docstring", "lint", "logging", "print".
---

# /programming-best-practices

Write (or review) code following the 6 rules below. Before finishing, walk the 6 checks against the code touched and fix every miss. If invoked with a file, diff or path, audit it and report per rule: OK, FIXED or RISK (with file:line). Never use em dashes.

## 1. TDD
- Load `/tests-guidelines` (Skill tool) and follow it for every test decision: runner detection, test-first cycle, unit, integration and E2E patterns, mocking, and the 80% coverage gate. The bullets below are the summary; where they differ, `/tests-guidelines` wins.
- Write a failing test first, run it and see it fail for the right reason, then write the minimum code to pass it.
- Bug fix: first a test that reproduces the bug, then the fix.
- Refactor only with the tests green before and after.
- Test behavior, not implementation details. Cover the edge cases the code actually branches on.

## 2. SOLID without speculative abstraction
- Single responsibility: one reason to change per function, class or module.
- Depend on abstractions only where there is already a second implementation or a test double that needs it.
- Open/closed, Liskov, interface segregation: apply them when the code already varies along that axis, not in advance.
- No interface with one implementation, no factory for one product, no config for a value that never changes.

## 3. Complete static typing
- Annotate every function parameter and return, and every public attribute (Python type hints, TypeScript explicit types, equivalents elsewhere).
- No `Any` / `any` unless justified in a comment. Prefer precise types: `Literal`, `TypedDict`, `Protocol`, unions, generics.
- Run the project's type checker (mypy, pyright, `tsc --noEmit`) and fix the errors.

## 4. Docstrings in Google Style
- Every public function, class and module gets a docstring: one-line summary, then `Args:`, `Returns:`, `Raises:` (and `Attributes:` for classes) when they apply.
- Describe what and why, not a line-by-line retelling of the code. Keep them in sync when the signature changes.
- Skip trivial private helpers whose name and types already say everything.

## 5. Linting
- Run the project's own linter and formatter (ruff, eslint, golangci-lint, clippy, whatever the repo configures) before concluding.
- Fix every warning in the code you touched. Do not silence a rule with a disable comment unless you state why.
- Do not reformat or fix unrelated files.

## 6. Logging, not print
- Never use `print` / `console.log` for diagnostics or runtime output in application code. Use the language's logging facility (Python `logging`, `logger` in JS/TS, `slog`/`zap` in Go, `tracing` in Rust). `print` stays only for a CLI's actual user-facing output and in throwaway scripts.
- One module-level logger per file (`logger = logging.getLogger(__name__)`). Never call `logging.basicConfig` in library code; configure handlers once, at the application entry point.
- Pick the level on purpose: DEBUG for diagnostics, INFO for normal milestones, WARNING for recoverable oddities, ERROR for failures, CRITICAL for fatal ones. Respect the project's existing level and format conventions.
- Lazy formatting: `logger.info("loaded %s rows", n)`, not f-strings, so the message is only built when the level is enabled.
- In `except` blocks use `logger.exception("...")` (or `exc_info=True`) to keep the traceback; log an error once, where it is handled, not at every layer it passes through.
- Never log secrets, tokens, passwords or personal data (see `/attack-protection`). Prefer structured context (`extra=` / key-value fields) over interpolating whole objects.
- When touching code that already has stray `print` calls, replace those in the lines you change; leave unrelated files alone and mention them.

## Output when writing code
After the code, add one line per rule, e.g. `TDD: /tests-guidelines applied, test_x fails then passes, coverage >= 80% | SOLID: single class, no extra interface | Types: mypy clean | Docs: Google style on public API | Lint: ruff clean | Logging: logger, no print`. Mark a rule not applicable as `n/a`. Anything you could not run or guarantee goes under `RISK` with the reason.
`````

### `~/.claude/skills/tests-guidelines/SKILL.md`

Origem: https://github.com/affaan-m/everything-claude-code, skill `tdd-workflow` (`.agents/skills/tdd-workflow/SKILL.md`, MIT). Instalada como `tests-guidelines` em 2026-11-11 por ser a de testes (cobertura, unitários, integração) com mais estrelas. Alterações em relação ao original: `name`, `description` e `source` no frontmatter; o Step 0 não usa mais o `scripts/setup-package-manager.js` do ECC e passou a ler `package.json`, lockfile, `pyproject.toml`, `go.mod` e `Cargo.toml`, com comandos de Python, Go e Rust; removida a referência à skill `bun-runtime`; travessões trocados por hífen.

`````markdown
---
name: tests-guidelines
description: Use when writing tests or doing TDD: new features, bug fixes, refactors. Enforces test-first development with 80%+ coverage across unit, integration and E2E tests. Trigger on /tests-guidelines, "tests", "coverage", "unit test", "integration test", "TDD".
license: MIT
source: https://github.com/affaan-m/everything-claude-code (skill tdd-workflow, MIT), adapted
---

# Test-Driven Development Workflow

This skill ensures all code development follows TDD principles with comprehensive test coverage.

## When to Activate

- Writing new features or functionality
- Fixing bugs or issues
- Refactoring existing code
- Adding API endpoints
- Creating new components

## Core Principles

### 1. Tests BEFORE Code
ALWAYS write tests first, then implement code to make tests pass.

### 2. Coverage Requirements
- Minimum 80% coverage (unit + integration + E2E)
- All edge cases covered
- Error scenarios tested
- Boundary conditions verified

### 3. Test Types

#### Unit Tests
- Individual functions and utilities
- Component logic
- Pure functions
- Helpers and utilities

#### Integration Tests
- API endpoints
- Database operations
- Service interactions
- External API calls

#### E2E Tests (Playwright)
- Critical user flows
- Complete workflows
- Browser automation
- UI interactions

## TDD Workflow Steps

### Step 0: Detect the Test Runner

Do not assume `npm test`. The commands in the steps and examples below use `<test>`, `<test-watch>`, and `<coverage>` as placeholders for the project's actual runner. Resolve them once before starting:

1. **Find the project's runner.** Read `package.json` (`packageManager`, `scripts.test`), the lockfile, `pyproject.toml` / `pytest.ini`, `go.mod`, `Cargo.toml`. The first match wins; do not assume `npm test`.

2. **Distinguish the package manager from the test runner. They are not the same.** A project can use Bun to install dependencies yet still run Jest or Vitest. Inspect `package.json` `scripts.test` and the test files:
   - `scripts.test` invokes `jest` / `vitest` -> run through the detected PM (`npm test`, `pnpm test`, `yarn test`, or `bun run test`).
   - `scripts.test` is `bun test`, or test files `import { test, expect } from "bun:test"`, or there is no jest/vitest config but Bun is present -> use **Bun's native runner** (`bun test`). See [Bun Native Test Pattern](#bun-native-test-pattern-buntest) below.
   - Python: `<test>` = `pytest`, `<coverage>` = `pytest --cov --cov-fail-under=80`. Go: `go test ./...` and `go test -cover ./...`. Rust: `cargo test`.

Runner command matrix:

| Runner | `<test>` | `<test-watch>` | `<coverage>` | `<lint>` |
|--------|----------|----------------|--------------|----------|
| npm | `npm test` | `npm test -- --watch` | `npm run test:coverage` | `npm run lint` |
| pnpm | `pnpm test` | `pnpm test --watch` | `pnpm test:coverage` | `pnpm lint` |
| yarn | `yarn test` | `yarn test --watch` | `yarn test:coverage` | `yarn lint` |
| Bun (script runs jest/vitest) | `bun run test` | `bun run test --watch` | `bun run test:coverage` | `bun run lint` |
| Bun (native `bun:test`) | `bun test` | `bun test --watch` | `bun test --coverage` | `bun run lint` |

> `bun test` (Bun's built-in runner) is **not** the same as `bun run test` (which runs the `package.json` `test` script). Picking the wrong one is a common failure - e.g. invoking Jest through `npx`/`bun run` in an ESM-only project breaks, while `bun test` runs the suite natively. Confirm which the project expects before the RED gate, then substitute `<test>` / `<coverage>` everywhere `npm test` appears below.

### Step 1: Write User Journeys
```
As a [role], I want to [action], so that [benefit]

Example:
As a user, I want to search for markets semantically,
so that I can find relevant markets even without exact keywords.
```

### Step 2: Generate Test Cases
For each user journey, create comprehensive test cases:

```typescript
describe('Semantic Search', () => {
  it('returns relevant markets for query', async () => {
    // Test implementation
  })

  it('handles empty query gracefully', async () => {
    // Test edge case
  })

  it('falls back to substring search when Redis unavailable', async () => {
    // Test fallback behavior
  })

  it('sorts results by similarity score', async () => {
    // Test sorting logic
  })
})
```

### Step 3: Run Tests (They Should Fail)
```bash
<test>
# Tests should fail - we haven't implemented yet
```

### Step 4: Implement Code
Write minimal code to make tests pass:

```typescript
// Implementation guided by tests
export async function searchMarkets(query: string) {
  // Implementation here
}
```

### Step 5: Run Tests Again
```bash
<test>
# Tests should now pass
```

### Step 6: Refactor
Improve code quality while keeping tests green:
- Remove duplication
- Improve naming
- Optimize performance
- Enhance readability

### Step 7: Verify Coverage
```bash
<coverage>
# Verify 80%+ coverage achieved
```

## Testing Patterns

### Unit Test Pattern (Jest/Vitest)
```typescript
import { render, screen, fireEvent } from '@testing-library/react'
import { Button } from './Button'

describe('Button Component', () => {
  it('renders with correct text', () => {
    render(<Button>Click me</Button>)
    expect(screen.getByText('Click me')).toBeInTheDocument()
  })

  it('calls onClick when clicked', () => {
    const handleClick = jest.fn()
    render(<Button onClick={handleClick}>Click</Button>)

    fireEvent.click(screen.getByRole('button'))

    expect(handleClick).toHaveBeenCalledTimes(1)
  })

  it('is disabled when disabled prop is true', () => {
    render(<Button disabled>Click</Button>)
    expect(screen.getByRole('button')).toBeDisabled()
  })
})
```

### Bun Native Test Pattern (`bun:test`)

When the project uses Bun's built-in runner (see [Step 0](#step-0-detect-the-test-runner)), import from `bun:test` and run with `bun test` - not `bun run test`. The API is Jest-like, so `describe` / `it` / `expect` and most matchers carry over.

```typescript
import { describe, it, expect, mock } from 'bun:test'
import { searchMarkets } from './search'

describe('searchMarkets', () => {
  it('returns an empty list for an empty query', async () => {
    expect(await searchMarkets('')).toEqual([])
  })

  it('sorts results by similarity score', async () => {
    const results = await searchMarkets('election')
    expect(results).toEqual([...results].sort((a, b) => b.score - a.score))
  })
})
```

```bash
bun test              # run once (RED/GREEN gate)
bun test --watch      # watch mode during development
bun test --coverage   # coverage report
```

- Mock modules with `mock.module(...)` / `mock(...)` from `bun:test` instead of `jest.mock(...)`.
- Configure coverage thresholds in `bunfig.toml` under `[test]` (e.g. `coverageThreshold`) rather than the Jest `coverageThresholds` config block.

### API Integration Test Pattern
```typescript
import { NextRequest } from 'next/server'
import { GET } from './route'

describe('GET /api/markets', () => {
  it('returns markets successfully', async () => {
    const request = new NextRequest('http://localhost/api/markets')
    const response = await GET(request)
    const data = await response.json()

    expect(response.status).toBe(200)
    expect(data.success).toBe(true)
    expect(Array.isArray(data.data)).toBe(true)
  })

  it('validates query parameters', async () => {
    const request = new NextRequest('http://localhost/api/markets?limit=invalid')
    const response = await GET(request)

    expect(response.status).toBe(400)
  })

  it('handles database errors gracefully', async () => {
    // Mock database failure
    const request = new NextRequest('http://localhost/api/markets')
    // Test error handling
  })
})
```

### E2E Test Pattern (Playwright)
```typescript
import { test, expect } from '@playwright/test'

test('user can search and filter markets', async ({ page }) => {
  // Navigate to markets page
  await page.goto('/')
  await page.click('a[href="/markets"]')

  // Verify page loaded
  await expect(page.locator('h1')).toContainText('Markets')

  // Search for markets
  await page.fill('input[placeholder="Search markets"]', 'election')

  // Wait for debounce and results
  await page.waitForTimeout(600)

  // Verify search results displayed
  const results = page.locator('[data-testid="market-card"]')
  await expect(results).toHaveCount(5, { timeout: 5000 })

  // Verify results contain search term
  const firstResult = results.first()
  await expect(firstResult).toContainText('election', { ignoreCase: true })

  // Filter by status
  await page.click('button:has-text("Active")')

  // Verify filtered results
  await expect(results).toHaveCount(3)
})

test('user can create a new market', async ({ page }) => {
  // Login first
  await page.goto('/creator-dashboard')

  // Fill market creation form
  await page.fill('input[name="name"]', 'Test Market')
  await page.fill('textarea[name="description"]', 'Test description')
  await page.fill('input[name="endDate"]', '2025-12-31')

  // Submit form
  await page.click('button[type="submit"]')

  // Verify success message
  await expect(page.locator('text=Market created successfully')).toBeVisible()

  // Verify redirect to market page
  await expect(page).toHaveURL(/\/markets\/test-market/)
})
```

## Test File Organization

```
src/
├── components/
│   ├── Button/
│   │   ├── Button.tsx
│   │   ├── Button.test.tsx          # Unit tests
│   │   └── Button.stories.tsx       # Storybook
│   └── MarketCard/
│       ├── MarketCard.tsx
│       └── MarketCard.test.tsx
├── app/
│   └── api/
│       └── markets/
│           ├── route.ts
│           └── route.test.ts         # Integration tests
└── e2e/
    ├── markets.spec.ts               # E2E tests
    ├── trading.spec.ts
    └── auth.spec.ts
```

## Mocking External Services

### Supabase Mock
```typescript
jest.mock('@/lib/supabase', () => ({
  supabase: {
    from: jest.fn(() => ({
      select: jest.fn(() => ({
        eq: jest.fn(() => Promise.resolve({
          data: [{ id: 1, name: 'Test Market' }],
          error: null
        }))
      }))
    }))
  }
}))
```

### Redis Mock
```typescript
jest.mock('@/lib/redis', () => ({
  searchMarketsByVector: jest.fn(() => Promise.resolve([
    { slug: 'test-market', similarity_score: 0.95 }
  ])),
  checkRedisHealth: jest.fn(() => Promise.resolve({ connected: true }))
}))
```

### OpenAI Mock
```typescript
jest.mock('@/lib/openai', () => ({
  generateEmbedding: jest.fn(() => Promise.resolve(
    new Array(1536).fill(0.1) // Mock 1536-dim embedding
  ))
}))
```

## Test Coverage Verification

### Run Coverage Report
```bash
<coverage>
```

### Coverage Thresholds
```json
{
  "jest": {
    "coverageThresholds": {
      "global": {
        "branches": 80,
        "functions": 80,
        "lines": 80,
        "statements": 80
      }
    }
  }
}
```

## Common Testing Mistakes to Avoid

### FAIL: WRONG: Testing Implementation Details
```typescript
// Don't test internal state
expect(component.state.count).toBe(5)
```

### PASS: CORRECT: Test User-Visible Behavior
```typescript
// Test what users see
expect(screen.getByText('Count: 5')).toBeInTheDocument()
```

### FAIL: WRONG: Brittle Selectors
```typescript
// Breaks easily
await page.click('.css-class-xyz')
```

### PASS: CORRECT: Semantic Selectors
```typescript
// Resilient to changes
await page.click('button:has-text("Submit")')
await page.click('[data-testid="submit-button"]')
```

### FAIL: WRONG: No Test Isolation
```typescript
// Tests depend on each other
test('creates user', () => { /* ... */ })
test('updates same user', () => { /* depends on previous test */ })
```

### PASS: CORRECT: Independent Tests
```typescript
// Each test sets up its own data
test('creates user', () => {
  const user = createTestUser()
  // Test logic
})

test('updates user', () => {
  const user = createTestUser()
  // Update logic
})
```

## Continuous Testing

### Watch Mode During Development
```bash
<test-watch>
# Tests run automatically on file changes
```

### Pre-Commit Hook
```bash
# Runs before every commit
<test> && <lint>
```

### CI/CD Integration
```yaml
# GitHub Actions
- name: Run Tests
  run: <coverage>
- name: Upload Coverage
  uses: codecov/codecov-action@v3
```

## Best Practices

1. **Write Tests First** - Always TDD
2. **One Assert Per Test** - Focus on single behavior
3. **Descriptive Test Names** - Explain what's tested
4. **Arrange-Act-Assert** - Clear test structure
5. **Mock External Dependencies** - Isolate unit tests
6. **Test Edge Cases** - Null, undefined, empty, large
7. **Test Error Paths** - Not just happy paths
8. **Keep Tests Fast** - Unit tests < 50ms each
9. **Clean Up After Tests** - No side effects
10. **Review Coverage Reports** - Identify gaps

## Success Metrics

- 80%+ code coverage achieved
- All tests passing (green)
- No skipped or disabled tests
- Fast test execution (< 30s for unit tests)
- E2E tests cover critical user flows
- Tests catch bugs before production

---

**Remember**: Tests are not optional. They are the safety net that enables confident refactoring, rapid development, and production reliability.
`````

### `~/.claude/skills/quality-gate/SKILL.md`

````markdown
---
name: quality-gate
description: Use when finishing a turn, before claiming work is done, or when a Stop hook asks for it. Runs the deterministic checks (schema, lint, types, tests, pre-commit, secrets scan) over the changed files and the current project. Fast, free, no LLM. Trigger on /quality-gate, "quality gate", "run checks", "gate".
---

# /quality-gate

Deterministic checks only. They are fast, free and cannot hallucinate. The LLM judge (`/llm-as-judge`) runs after this one, never before. Never use em dashes.

## Run

Use the exact command the Stop hook gave you (it carries `--state`, `--turn` and `--cwd`). With no hook, run it bare:

```bash
~/.claude/scripts/quality-gate.sh
```

Use a Bash timeout of 300000 ms: test suites can be slow.

## What it checks

Over the git diff vs HEAD plus untracked files, and the project the cwd belongs to:

- **schema:** json, yaml and toml files are well-formed (syntax only; files that allow comments, like tsconfig, are skipped).
- **lint-types-tests:** the project's own lint, typecheck and test commands (npm, ruff, mypy, pytest, go, cargo).
- **pre-commit:** `pre-commit run --files <changed>` when `.pre-commit-config.yaml` exists.
- **secrets:** gitleaks when installed, otherwise a regex scan for common key formats and versioned `.env` files.

A check with nothing to do reports `na`, and the gate still passes.

## When it fails

1. Read the failing check's detail. Fix the root cause in the code.
2. Never edit a test just to make it pass, never silence a lint rule, never delete the finding.
3. If pre-commit reformatted files and exited 1, run the gate again.
4. A secret hit means rotate the key, not just delete the line.
5. Rerun until `GATE: PASS`.

## Report

One line per check as the script prints it, for example `schema: ok | lint-types-tests: ok | pre-commit: na | secrets: ok`. Say pass only when the command printed `GATE: PASS` (exit 0). Do not call the judge from here; the order is gate first, judge second.
````

### `~/.claude/skills/llm-as-judge/SKILL.md`

````markdown
---
name: llm-as-judge
description: Use after /quality-gate passed, when finishing a turn or when a Stop hook asks for it. An independent model (Fable 5.1, fallback Opus 5.5) scores 0-10 what code cannot check: does the answer follow the request, is the tone right, does the code do what the PR says. Trigger on /llm-as-judge, "llm as judge", "judge", "score the answer".
---

# /llm-as-judge

Covers what cannot be coded: "does the answer follow the request?", "is the tone right?", "does the code do what the PR says?". It runs only after `/quality-gate` passed for the same turn; the script refuses to run otherwise (exit 3). Never use em dashes.

## Run

Use the exact command the Stop hook gave you (it carries `--state`, `--turn`, `--transcript` and `--cwd`). Use a Bash timeout of 300000 ms.

```bash
~/.claude/scripts/llm-judge.sh --state DIR --turn ID --transcript PATH
```

The judge model is Fable 5.1 with a fallback to Opus 5.5 when Fable is unavailable. If both are unavailable the script fails open and says so. Threshold: 7 out of 10.

## Evidence mode (automatic)

- **diff:** the git diff vs HEAD, reviewed with `/code-review` plus "does it do what the user asked?".
- **goal:** the active `/goal` condition against the work done since it was set.
- **response:** the last request against the last answer (follows the request, tone fits).

## If the score is below 7

Iterate with the session's own model (the default, Sonnet 1M). Do not switch models. Fix every point in the feedback, then run `/quality-gate` again and `/llm-as-judge` again. Do not argue with the judge in text; change the work.

If the reply was unparsable, just run the command again.

## If the score is 7 or higher

- **Code task** (a git repo with changes): ask the user three questions in one `AskUserQuestion` call: make a commit? create a branch? prepare a PR? For anything the user accepts, `/git-guidelines` is mandatory (branch name, Conventional Commits with scope, PR title and template, EN-US). Never commit to the default branch, no Claude attribution, no force push. Merge and deploy still ask for confirmation.
- **Not a code task:** go on without questions.

Finally, persist the relevant findings in the Obsidian vault folder of the working directory (existing note updated instead of duplicated, plus the `MEMORY.md` line; skip if nothing is worth keeping, and test that the directory accepts writes before claiming it did).

## Report

State the judge, the score and whether it passed, as printed by the script, for example `Fable 5.1 8/10 (response) PASS`. Say pass only when the command printed PASS (exit 0).
````

### `~/.claude/scripts/iterm-session-name.sh`

```bash
#!/bin/bash
# SessionStart hook: in iTerm2, set the Session Name to the folder name and the
# Session Title to Session Name only (via the iTerm2 Python API, live).
# No-op outside iTerm2. Never blocks the session. Logs each run to
# ~/.claude/logs/iterm-session-name.log (event source, name, title read back).

[ -n "$ITERM_SESSION_ID" ] || exit 0

payload=$(cat)
dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
source_=$(printf '%s' "$payload" | jq -r '.source // "unknown"' 2>/dev/null)
uuid="${ITERM_SESSION_ID#*:}"

# Nested claude (judge `claude -p`, claude-mem, headless helpers) inherits the tab's
# ITERM_SESSION_ID and fires its own SessionStart with its own folder. Only the claude
# that owns the tab (no other claude among its ancestors) may name it.
n=0; p=$$
while [ "${p:-0}" -gt 1 ]; do
  [ "$(basename -- "$(ps -o comm= -p "$p" 2>/dev/null)")" = claude ] && n=$((n + 1))
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done
if [ "$n" -gt 1 ]; then
  mkdir -p "$HOME/.claude/logs"
  printf '%s source=%s uuid=%s skipped=nested-claude(%s)\n' "$(date '+%F %T')" "$source_" "$uuid" "$n" >> "$HOME/.claude/logs/iterm-session-name.log"
  exit 0
fi
# Name from the folder the session was opened in; the payload cwd follows Claude's
# `cd` and would rename the tab. Order: first cwd in the transcript (the original
# folder, also on --resume, where CLAUDE_PROJECT_DIR is the old last cwd), then
# CLAUDE_PROJECT_DIR, then cwd. On /clear the name stored for this tab wins.
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
first=""
[ -f "$transcript" ] && first=$(jq -rn 'first(inputs | select(.cwd) | .cwd)' "$transcript" 2>/dev/null)
name=$(basename "${first:-${CLAUDE_PROJECT_DIR:-${dir:-$PWD}}}")
store="$HOME/.claude/state/iterm-names"
if [ "$source_" = clear ] && [ -s "$store/$uuid" ]; then name=$(cat "$store/$uuid"); fi

# Subagent worktrees (<project>/.claude/worktrees/agent-*) inherit ITERM_SESSION_ID
# from the user's tab; renaming here would replace the project name with agent-<id>.
case "${dir:-$PWD}" in
  */.claude/worktrees/*)
    mkdir -p "$HOME/.claude/logs"
    printf '%s source=%s name=%s skipped=worktree\n' "$(date '+%F %T')" "$source_" "$name" >> "$HOME/.claude/logs/iterm-session-name.log"
    exit 0 ;;
esac

osascript - "$uuid" "$name" <<'APPLESCRIPT' >/dev/null 2>&1
on run {uuid, nm}
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is uuid then set name of s to nm
        end repeat
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT

mkdir -p "$store" && printf '%s' "$name" > "$store/$uuid"

# Title: needs the iterm2 package in a venv and the API server enabled; skip silently otherwise.
PY="$HOME/.claude/venvs/iterm2/bin/python"
title=skipped
if [ -x "$PY" ] && command -v timeout >/dev/null; then
  title=$(timeout 8 "$PY" "$HOME/.claude/scripts/iterm-title-name.py" "$uuid" 2>&1 | tail -1)
  [ -n "$title" ] || title=ok
fi

mkdir -p "$HOME/.claude/logs"
printf '%s source=%s uuid=%s name=%s proj=%s %s\n' "$(date '+%F %T')" "$source_" "$uuid" "$name" "${CLAUDE_PROJECT_DIR:-unset}" "$title" >> "$HOME/.claude/logs/iterm-session-name.log"
exit 0
```

### `~/.claude/scripts/iterm-title-name.py`

```python
"""Pin an iTerm2 session's title to Session Name and stop apps from retitling it (needs the iterm2 venv)."""
import sys

import iterm2


async def main(connection: iterm2.Connection) -> None:
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(sys.argv[1])
    if session is None:
        return
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_title_components([iterm2.profile.TitleComponents.SESSION_NAME])
    # Claude Code retitles the tab (OSC) on /clear; ignore app-set titles so the folder name sticks.
    profile.set_allow_title_setting(False)
    await session.async_set_profile_properties(profile)
    after = await session.async_get_profile()
    print("title=" + ",".join(c.name for c in after.title_components) + f" allow_title_setting={after.allow_title_setting}")


iterm2.run_until_complete(main, retry=False)
```

### `~/.claude/mods/git-diff-on-start/hooks/register.ts`

```ts
import type { EngineInterface, Register } from 'claude-code'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // turns === 0 keeps a hot reload mid-session from opening /diff again
    if (e.isInteractive && (await $.session.repo()) && (await $.session.turns()) === 0) {
      void openDiff($)
      void openEditor($)
    }
    return next(e)
  })
}

// /diff is registered by the built-in diff plugin after session.start settles, so wait for it
const openDiff = async ($: EngineInterface) => {
  for (let i = 0; i < 40; i++) {
    if ((await $.command.list()).some(c => c.name === 'diff')) break
    await $.clock.sleep(250)
  }
  // /diff toggles: if the panel was restored open, the first run hides it, so run again
  const { text } = await $.command.run({ command: 'diff' })
  if (text?.includes('hidden')) await $.command.run({ command: 'diff' })
}

// same as `code . || antigravity-ide .`: antigravity-ide takes over when code is missing or fails
const openEditor = async ($: EngineInterface) => {
  for (const editor of ['code', 'antigravity-ide']) {
    const ok = await $.process.run([editor, '.']).then(r => r.exitCode === 0, () => false)
    if (ok) return
  }
}
```

### `~/.claude/mods/git-diff-on-start/hooks/register.test.ts`

```ts
import { expect, test } from 'claude-code/testing'

declare const setTimeout: (fn: (value?: unknown) => void, ms: number) => unknown

const opened_ref: { current: string[] } = { current: [] }

const start = async (
  $: any,
  on: any,
  { repo, turns, isInteractive, hiddenFirst = false, editors = ['code'] }: { repo: boolean; turns: number; isInteractive: boolean; hiddenFirst?: boolean; editors?: string[] },
) => {
  const ran: string[] = []
  const opened: string[] = []
  opened_ref.current = opened
  on('session.repo', () => ({ value: repo ? { internal: false } : null }))
  on('session.turns', () => ({ value: turns }))
  on('clock.sleep', () => ({ value: undefined }))
  let listed = 0
  // /diff shows up in the list only on the third look, as in the real session
  on('command.list', () => ({ value: ++listed < 3 ? [] : [{ name: 'diff' }] }))
  on('command.run', (_: unknown, e: { command: string }) => {
    ran.push(e.command)
    return { text: ran.length === 1 && hiddenFirst ? 'Diff panel hidden' : 'Diff panel shown' }
  })
  // editors lists the executables that exist; anything else fails to start
  on('process.run', (_: unknown, e: { argv: string[] }) => {
    opened.push(e.argv[0])
    if (!editors.includes(e.argv[0])) throw new Error('spawn ENOENT')
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  on('session.start', (_: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive })
  await new Promise(r => setTimeout(r, 1200))
  return ran
}

test('opens /diff on an interactive start inside a repo', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 0, isInteractive: true })).toEqual(['diff'])
})

test('does nothing outside a repo', async ($, on) => {
  expect(await start($, on, { repo: false, turns: 0, isInteractive: true })).toEqual([])
})

test('does nothing when headless', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 0, isInteractive: false })).toEqual([])
})

test('does nothing after a mid-session reload', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 3, isInteractive: true })).toEqual([])
})

test('runs /diff again when the first run hid a restored panel', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 0, isInteractive: true, hiddenFirst: true })).toEqual(['diff', 'diff'])
})

test('opens the project in code', async ($, on) => {
  await start($, on, { repo: true, turns: 0, isInteractive: true })
  expect(opened_ref.current).toEqual(['code'])
})

test('falls back to antigravity-ide when code is missing', async ($, on) => {
  await start($, on, { repo: true, turns: 0, isInteractive: true, editors: ['antigravity-ide'] })
  expect(opened_ref.current).toEqual(['code', 'antigravity-ide'])
})

test('opens no editor outside a repo', async ($, on) => {
  await start($, on, { repo: false, turns: 0, isInteractive: true })
  expect(opened_ref.current).toEqual([])
})
```

O mod também precisa de `hooks/hooks.json` (`{ "modules": ["./register.ts"] }`), `.claude-plugin/plugin.json` (`{ "name": "git-diff-on-start", "version": "0.1.0", "description": "Opens /diff when an interactive session starts inside a git repository" }`) e `tsconfig.json` (`{ "extends": "./.claude-plugin/types/tsconfig.json" }`).
