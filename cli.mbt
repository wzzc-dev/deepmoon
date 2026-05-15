///|
priv struct CliOptions {
  mut base_url : String?
  mut model : String?
  mut history : String?
  mut max_steps : Int?
  mut skills_dir : String?
  mut memory_dir : String?
  mut context_window : Int?
  mut debug : Bool
  rest : Array[String]
}

///|
fn CliOptions::new() -> CliOptions {
  {
    base_url: None,
    model: None,
    history: None,
    max_steps: None,
    skills_dir: None,
    memory_dir: None,
    context_window: None,
    debug: false,
    rest: [],
  }
}

///|
fn usage() -> String {
  (
    #|Usage:
    #|  deepmoon run [options] <task>
    #|  deepmoon repl [options]
    #|
    #|Options:
    #|  --base-url <url>        OpenAI-compatible API base URL
    #|  --model <model>         Chat Completions model name
    #|  --history <path>        JSONL history file path
    #|  --max-steps <n>         Maximum tool-calling steps (default: 8)
    #|  --skills-dir <path>     Skills directory relative to the workspace (default: skills)
    #|  --memory-dir <path>     Memory directory relative to the workspace (default: .deepmoon/memory)
    #|  --context-window <n>    Context window used for compaction thresholds (default: 32000)
    #|  --debug                 Print full HTTP/tool debug output
    #|  -h, --help              Show help
    #|
    #|Env:
    #|  deepmoon_key / OPENAI_API_KEY
    #|  deepmoon_api / OPENAI_BASE_URL
    #|  OPENAI_MODEL
  )
}

///|
fn parse_positive_int(flag : String, value : String) -> Int? {
  let parsed = @string.parse_int(value) catch { _ => return None }
  if parsed > 0 {
    Some(parsed)
  } else {
    println("error: \{flag} must be greater than 0")
    None
  }
}

///|
fn parse_options(args : ArrayView[String]) -> (CliOptions?, String?) {
  let options = CliOptions::new()
  for rest = args {
    match rest {
      [] => break
      ["--", .. tail] => {
        for item in tail {
          options.rest.push(item)
        }
        break
      }
      ["--debug", .. tail] => {
        options.debug = true
        continue tail
      }
      ["--base-url", value, .. tail] => {
        options.base_url = Some(value)
        continue tail
      }
      ["--model", value, .. tail] => {
        options.model = Some(value)
        continue tail
      }
      ["--history", value, .. tail] => {
        options.history = Some(value)
        continue tail
      }
      ["--skills-dir", value, .. tail] => {
        options.skills_dir = Some(value)
        continue tail
      }
      ["--memory-dir", value, .. tail] => {
        options.memory_dir = Some(value)
        continue tail
      }
      ["--max-steps", value, .. tail] => {
        guard parse_positive_int("--max-steps", value) is Some(parsed) else {
          return (None, Some("invalid --max-steps value `\{value}`"))
        }
        options.max_steps = Some(parsed)
        continue tail
      }
      ["--context-window", value, .. tail] => {
        guard parse_positive_int("--context-window", value) is Some(parsed) else {
          return (None, Some("invalid --context-window value `\{value}`"))
        }
        options.context_window = Some(parsed)
        continue tail
      }
      [flag, ..] if flag.has_prefix("--") =>
        return (None, Some("unknown option `\{flag}`"))
      [arg, .. tail] => {
        options.rest.push(arg)
        for item in tail {
          options.rest.push(item)
        }
        break
      }
    }
  }
  (Some(options), None)
}

///|
fn choose_option(
  cli : String?,
  env_name : String,
  default : String?,
) -> String? {
  match cli {
    Some(value) => Some(value)
    None =>
      match @env.get_env_var(env_name) {
        Some(value) => Some(value)
        None => default
      }
  }
}

///|
fn choose_option_from_envs(
  cli : String?,
  env_names : Array[String],
  default : String?,
) -> String? {
  match cli {
    Some(value) => Some(value)
    None => {
      for name in env_names {
        if @env.get_env_var(name) is Some(value) {
          return Some(value)
        }
      }
      default
    }
  }
}

///|
fn require_relative_workspace_path(_name : String, path : String) -> String? {
  if path_is_lexically_safe(path) {
    Some(path)
  } else {
    None
  }
}

///|
fn build_config(options : CliOptions) -> (AgentConfig?, String?) {
  guard choose_option_from_envs(None, ["deepmoon_key", "OPENAI_API_KEY"], None)
    is Some(api_key) else {
    return (None, Some("deepmoon_key or OPENAI_API_KEY is required"))
  }
  guard choose_option(options.model, "OPENAI_MODEL", None) is Some(model) else {
    return (None, Some("--model or OPENAI_MODEL is required"))
  }
  let base_url = match
    choose_option_from_envs(
      options.base_url,
      ["deepmoon_api", "OPENAI_BASE_URL"],
      Some("https://api.openai.com/v1"),
    ) {
    Some(value) => value
    None => "https://api.openai.com/v1"
  }
  let workspace = match @env.current_dir() {
    Some(path) => path
    None => "."
  }
  let history_path = match options.history {
    Some(path) => Some(path)
    None => Some(default_history_path())
  }
  let max_steps = match options.max_steps {
    Some(value) => value
    None => 8
  }
  let skills_dir = match options.skills_dir {
    Some(path) =>
      match require_relative_workspace_path("--skills-dir", path) {
        Some(valid) => valid
        None =>
          return (None, Some("--skills-dir must stay within the workspace"))
      }
    None => "skills"
  }
  let memory_dir = match options.memory_dir {
    Some(path) =>
      match require_relative_workspace_path("--memory-dir", path) {
        Some(valid) => valid
        None =>
          return (None, Some("--memory-dir must stay within the workspace"))
      }
    None => ".deepmoon/memory"
  }
  let context_window = match options.context_window {
    Some(value) => value
    None => 32000
  }
  (
    Some({
      api_key,
      base_url,
      model,
      workspace,
      history_path,
      skills_dir,
      memory_dir,
      context_window,
      max_steps,
      debug: options.debug,
    }),
    None,
  )
}

///|
fn has_help(args : ArrayView[String]) -> Bool {
  args.contains("-h") || args.contains("--help")
}

///|
priv struct CliStreamState {
  mut wrote_text : Bool
  mut needs_prefix : Bool
}

///|
async fn write_line_if_needed(text : String, to_stderr? : Bool = false) -> Unit {
  if text == "" || !text.has_suffix("\n") {
    if to_stderr {
      @stdio.stderr.write("\n")
    } else {
      @stdio.stdout.write("\n")
    }
  }
}

///|
fn run_stream_sink() -> ModelStreamSink {
  {
    on_text_delta: async fn(text) { @stdio.stdout.write(text) },
    on_tool_status: async fn(text) {
      @stdio.stderr.write(text)
      write_line_if_needed(text, to_stderr=true)
    },
  }
}

///|
fn repl_stream_sink() -> ModelStreamSink {
  let state = { wrote_text: false, needs_prefix: false }
  {
    on_text_delta: async fn(text) {
      if state.needs_prefix {
        @stdio.stdout.write("DeepMoon: ")
        state.needs_prefix = false
      }
      @stdio.stdout.write(text)
      state.wrote_text = true
    },
    on_tool_status: async fn(text) {
      if state.wrote_text || !state.needs_prefix {
        @stdio.stdout.write("\n")
      }
      @stdio.stdout.write(text)
      write_line_if_needed(text)
      state.wrote_text = false
      state.needs_prefix = true
    },
  }
}

///|
async fn run_command(args : ArrayView[String]) -> Unit {
  if has_help(args) {
    println(usage())
    return
  }
  let (options, error) = parse_options(args)
  if error is Some(message) {
    println("error: \{message}\n")
    println(usage())
    return
  }
  guard options is Some(options) else { return }
  let (config, config_error) = build_config(options)
  if config_error is Some(message) {
    println("error: \{message}")
    return
  }
  guard config is Some(config) else { return }
  guard !options.rest.is_empty() else {
    println("error: run requires a task")
    return
  }
  let task = options.rest.join(" ")
  let client = HttpModelClient::new()
  let session = open_main_session(config, client)
  let registry = build_tool_registry(config, session, client)
  let user_message = Message::user(task)
  session.history.push(user_message)
  append_persistent_message(config, session, user_message)
  let result = run_agent_stream(
    config,
    client,
    registry,
    session,
    run_stream_sink(),
  )
  write_line_if_needed(result.final_text)
}

///|
fn print_skills(session : SessionState) -> Unit {
  println(session.available_skills_summary())
}

///|
fn print_todos(session : SessionState) -> Unit {
  println(render_todos(session.todos))
}

///|
priv enum ReplReadResult {
  ReplNeedMore
  ReplEof
  ReplCommand(String)
  ReplMessage(String)
}

///|
fn repl_line_text(line : String) -> String {
  line.trim(chars="\r").to_owned()
}

///|
fn is_repl_command(input : String) -> Bool {
  match input {
    "/exit"
    | "/clear"
    | "/debug on"
    | "/debug off"
    | "/skills"
    | "/todos"
    | "/compact" => true
    _ => false
  }
}

///|
fn repl_read_result_from_lines(
  raw_lines : Array[String],
  eof~ : Bool,
) -> ReplReadResult {
  let lines : Array[String] = []
  for raw in raw_lines {
    let line = repl_line_text(raw)
    let trimmed = line.trim().to_owned()
    if lines.is_empty() && is_repl_command(trimmed) {
      return ReplCommand(trimmed)
    }
    if trimmed == "" {
      if !lines.is_empty() {
        return ReplMessage(lines.join("\n"))
      }
    } else {
      lines.push(line)
    }
  }
  if eof {
    if lines.is_empty() {
      ReplEof
    } else {
      ReplMessage(lines.join("\n"))
    }
  } else {
    ReplNeedMore
  }
}

///|
async fn read_repl_input() -> ReplReadResult {
  let lines : Array[String] = []
  while true {
    if lines.is_empty() {
      @stdio.stdout.write("User: ")
    } else {
      @stdio.stdout.write("... ")
    }
    match @stdio.stdin.read_until("\n") {
      None => return repl_read_result_from_lines(lines, eof=true)
      Some(line) => {
        if lines.is_empty() && repl_line_text(line).trim().to_owned() == "" {
          continue
        }
        lines.push(line)
        match repl_read_result_from_lines(lines, eof=false) {
          ReplNeedMore => continue
          result => return result
        }
      }
    }
  }
  ReplEof
}

///|
async fn repl_command(args : ArrayView[String]) -> Unit {
  if has_help(args) {
    println(usage())
    return
  }
  let (options, error) = parse_options(args)
  if error is Some(message) {
    println("error: \{message}\n")
    println(usage())
    return
  }
  guard options is Some(options) else { return }
  let (config, config_error) = build_config(options)
  if config_error is Some(message) {
    println("error: \{message}")
    return
  }
  guard config is Some(config) else { return }
  guard options.rest.is_empty() else {
    println("error: repl does not accept a task argument")
    return
  }
  let client = HttpModelClient::new()
  let session = open_main_session(config, client)
  let registry = build_tool_registry(config, session, client)
  while true {
    match read_repl_input() {
      ReplEof => break
      ReplNeedMore => continue
      ReplCommand(command) =>
        if command == "/exit" {
          break
        } else if command == "/clear" {
          session.clear_working()
          println("working context cleared")
          continue
        } else if command == "/debug on" {
          config.debug = true
          println("debug on")
          continue
        } else if command == "/debug off" {
          config.debug = false
          println("debug off")
          continue
        } else if command == "/skills" {
          print_skills(session)
          continue
        } else if command == "/todos" {
          print_todos(session)
          continue
        } else if command == "/compact" {
          session.force_compact = true
          if compact_session_history(config, client, session) {
            println("history compacted")
          } else {
            println("nothing to compact")
          }
          continue
        }
      ReplMessage(input) => {
        let user_message = Message::user(input)
        session.history.push(user_message)
        append_persistent_message(config, session, user_message)
        @stdio.stdout.write("DeepMoon: ")
        let result = run_agent_stream(
          config,
          client,
          registry,
          session,
          repl_stream_sink(),
        )
        write_line_if_needed(result.final_text)
      }
    }
  }
}

///|
pub async fn cli_main() -> Unit {
  let args = @env.args()[1:]
  match args {
    [] => println(usage())
    ["-h" | "--help", ..] => println(usage())
    ["run", .. rest] => run_command(rest)
    ["repl", .. rest] => repl_command(rest)
    [other, ..] => {
      println("error: unknown command `\{other}`\n")
      println(usage())
    }
  }
}
