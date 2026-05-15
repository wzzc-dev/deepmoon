# deepmoon

`deepmoon` is a MoonBit native CLI agent for coding, workspace inspection, and
small workflow orchestration. It talks to an OpenAI-compatible Chat
Completions endpoint, keeps local JSONL session history, maintains lightweight
memory files, can load reusable skills, and can dispatch bounded subagents for
isolated work.

## Features

- Native MoonBit CLI with `run` and `repl`
- OpenAI-compatible `POST /chat/completions` client via `moonbitlang/async/http`
- Workspace-scoped tools for reading, searching, writing, editing, fetching
  public web pages, planning todos, and dispatching subagents
- Skills loaded from `skills/**/SKILL.md`
- Local memory under `.deepmoon/memory/`
- JSONL session transcripts under `.deepmoon/sessions/`
- Shell-free command execution with an allowlist

## Configuration

`deepmoon` resolves configuration in this order:

1. CLI flags
2. custom `deepmoon_*` environment variables
3. compatibility `OPENAI_*` environment variables

Required / supported environment variables:

- `deepmoon_key`: API key
- `deepmoon_api`: API base URL, for example `https://api.openai.com/v1`
- `OPENAI_MODEL`: model name

Compatibility fallbacks:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`

Example:

```sh
export deepmoon_key="your-api-key"
export deepmoon_api="https://api.openai.com/v1"
export OPENAI_MODEL="gpt-4.1-mini"
```

## Usage

Show help:

```sh
moon run --target native cmd/main -- --help
```

Run a single task:

```sh
moon run --target native cmd/main -- run "summarize the package structure"
```

Start an interactive REPL:

```sh
moon run --target native cmd/main -- repl
```

Useful flags:

- `--base-url <url>`
- `--model <model>`
- `--history <path>`
- `--max-steps <n>`
- `--skills-dir <path>`
- `--memory-dir <path>`
- `--context-window <n>`
- `--debug`

REPL commands:

- `/exit`
- `/clear`
- `/debug on`
- `/debug off`
- `/skills`
- `/todos`
- `/compact`

## Tools

Built-in tools:

- `read_file(path, start_line?, max_lines?)`
- `list_dir(path?)`
- `search(pattern, path?, glob?)`
- `glob(pattern, path?)`
- `run_command(argv)`
- `write_file(path, content)`
- `edit_file(path, old_text, new_text, replace_all?)`
- `web_fetch(url)`
- `load_skill(name)`
- `update_todos(todos)`
- `dispatch_subagent(agent_type, task, purpose?)`

Built-in subagent roles:

- `scout`
- `reader`
- `researcher`
- `verifier`
- `editor`

## Safety

All file tools are restricted to the directory where `deepmoon` starts.

Path rules:

- absolute paths are rejected
- `..` traversal is rejected
- existing symlink hops must stay under the workspace root

`run_command(argv)` is shell-free and only allows:

- `pwd`
- `ls`
- `rg`
- `cat`
- `sed -n`
- `moon check`
- `moon test`
- `moon info`
- `moon fmt`
- `git status --short`
- `git diff`
- `git ls-files`

Shell syntax such as pipes, redirects, command substitution, `&&`, and `;` is
rejected.

`web_fetch` allows only public `http/https` GET requests. `localhost`,
loopback, and private-network hosts are blocked.

## History And Memory

Session transcripts:

```text
.deepmoon/sessions/<timestamp>.jsonl
```

Memory files:

```text
.deepmoon/memory/
  MEMORY.md
  USER.md
  history.jsonl
  tokens.jsonl
  <day>.md
```

Behavior:

- full user / assistant / tool messages are appended to the session transcript
- full user / assistant / tool messages are also appended to the memory ledger
- token usage is recorded when the API returns `usage`
- when prompt usage crosses `context_window * 0.7`, older history is compacted
  into episodic and long-term memory
- `/clear` resets working history, loaded skills, and todos, but keeps memory
  files

## Skills And Templates

- Skills live under `skills/**/SKILL.md`
- `always: true` skills are injected automatically
- other skills are pulled in with `load_skill(name)`
- prompt templates are documented under `templates/`

## Development

Run checks, formatters, and tests:

```sh
moon info
moon fmt
moon test --target native
```

Current tests cover:

- request / response / usage JSON handling
- CLI option parsing and env precedence
- path safety and command allowlist
- skills frontmatter parsing
- memory ledger behavior
- todo validation
- local-host blocking for `web_fetch`
- fake-model tool loop execution
