///|
fn json_required_string(args : Json, key : String) -> String? {
  match args {
    Object(obj) =>
      match obj.get(key) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn json_optional_string(args : Json, key : String) -> String? {
  json_required_string(args, key)
}

///|
fn json_optional_int(args : Json, key : String, default : Int) -> Int {
  match args {
    Object(obj) =>
      match obj.get(key) {
        Some(Number(value, ..)) => value.to_int()
        _ => default
      }
    _ => default
  }
}

///|
fn json_optional_bool(args : Json, key : String, default : Bool) -> Bool {
  match args {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
async fn workspace_text_path(config : AgentConfig, path : String) -> String {
  resolve_workspace_path(config.workspace, path)
}

///|
async fn workspace_text_path_allow_missing(
  config : AgentConfig,
  path : String,
) -> String {
  resolve_workspace_path_allow_missing(config.workspace, path)
}

///|
async fn read_file_tool(config : AgentConfig, args : Json) -> String {
  guard json_required_string(args, "path") is Some(path) else {
    return "ERROR: read_file requires string field `path`"
  }
  let full = workspace_text_path(config, path)
  let start_line = json_optional_int(args, "start_line", 1).max(1)
  let max_lines = json_optional_int(args, "max_lines", 200).max(1).min(1000)
  let text = @fs.read_file(full).text()
  let out = StringBuilder::new()
  let mut line_no = 1
  let end_line = start_line + max_lines
  for line in text.split("\n") {
    if line_no >= start_line && line_no < end_line {
      out.write_object(line_no)
      out.write_stringview(": ")
      out.write_stringview(line)
      out.write_stringview("\n")
    }
    line_no += 1
  }
  out.to_string()
}

///|
async fn list_dir_tool(config : AgentConfig, args : Json) -> String {
  let path = match json_optional_string(args, "path") {
    Some(path) => path
    None => "."
  }
  let full = workspace_text_path(config, path)
  let entries = @fs.readdir(
    full,
    include_hidden=true,
    include_special=false,
    sort=true,
  )
  entries.join("\n") + "\n"
}

///|
async fn search_tool(config : AgentConfig, args : Json) -> String {
  guard json_required_string(args, "pattern") is Some(pattern) else {
    return "ERROR: search requires string field `pattern`"
  }
  let path = match json_optional_string(args, "path") {
    Some(path) => path
    None => "."
  }
  ignore(workspace_text_path(config, path))
  let argv : Array[String] = [
    "--line-number", "--no-heading", "--color", "never",
  ]
  if json_optional_string(args, "glob") is Some(glob) {
    argv.push("-g")
    argv.push(glob)
  }
  argv.push(pattern)
  argv.push(path)
  let (code, stdout, stderr) = @process.collect_output(
    "rg",
    argv,
    cwd=config.workspace,
  )
  "exit_code: \{code}\nstdout:\n\{stdout.text()}\nstderr:\n\{stderr.text()}"
}

///|
async fn glob_tool(config : AgentConfig, args : Json) -> String {
  guard json_required_string(args, "pattern") is Some(pattern) else {
    return "ERROR: glob requires string field `pattern`"
  }
  let path = match json_optional_string(args, "path") {
    Some(path) => path
    None => "."
  }
  ignore(workspace_text_path(config, path))
  let (code, stdout, stderr) = @process.collect_output(
    "rg",
    ["--files", path, "-g", pattern],
    cwd=config.workspace,
  )
  "exit_code: \{code}\nstdout:\n\{stdout.text()}\nstderr:\n\{stderr.text()}"
}

///|
fn arg_has_shell_syntax(arg : String) -> Bool {
  arg.contains(";") ||
  arg.contains("|") ||
  arg.contains(">") ||
  arg.contains("<") ||
  arg.contains("$(") ||
  arg.contains("`") ||
  arg.contains("&&") ||
  arg.contains("||")
}

///|
fn command_arg_safe(arg : String) -> Bool {
  !arg_has_shell_syntax(arg) && !arg.has_prefix("/") && !arg.contains("..")
}

///|
fn ls_arg_allowed(arg : String) -> Bool {
  if arg.has_prefix("-") {
    arg == "-l" || arg == "-a" || arg == "-la" || arg == "-al"
  } else {
    command_arg_safe(arg)
  }
}

///|
fn cat_arg_allowed(arg : String) -> Bool {
  command_arg_safe(arg) && !arg.has_prefix("-")
}

///|
fn sed_script_allowed(script : String) -> Bool {
  if !script.has_suffix("p") {
    return false
  }
  for ch in script {
    if !((ch >= '0' && ch <= '9') || ch == ',' || ch == 'p') {
      return false
    }
  }
  true
}

///|
pub fn command_allowed(argv : Array[String]) -> Bool {
  if argv.is_empty() {
    return false
  }
  for arg in argv {
    if arg_has_shell_syntax(arg) {
      return false
    }
  }
  match argv {
    ["pwd"] => true
    ["moon", "check"] | ["moon", "test"] | ["moon", "info"] | ["moon", "fmt"] =>
      true
    ["moon", "check", "--target", "native"]
    | ["moon", "test", "--target", "native"] => true
    ["git", "status", "--short"] | ["git", "diff"] | ["git", "ls-files"] => true
    ["git", "diff", "--", .. paths] =>
      !paths.is_empty() && paths.all(path => cat_arg_allowed(path))
    ["sed", "-n", script, path] =>
      sed_script_allowed(script) && cat_arg_allowed(path)
    _ => {
      let cmd = argv[0]
      if cmd == "ls" {
        argv[1:].all(arg => ls_arg_allowed(arg))
      } else if cmd == "cat" {
        !argv[1:].is_empty() && argv[1:].all(arg => cat_arg_allowed(arg))
      } else if cmd == "rg" {
        argv[1:].all(arg => command_arg_safe(arg))
      } else {
        false
      }
    }
  }
}

///|
fn parse_argv(args : Json) -> Array[String]? {
  match args {
    Object(obj) =>
      match obj.get("argv") {
        Some(Array(values)) => {
          let argv : Array[String] = []
          for value in values {
            match value {
              String(text) => argv.push(text)
              _ => return None
            }
          }
          Some(argv)
        }
        _ => None
      }
    _ => None
  }
}

///|
async fn run_command_tool(config : AgentConfig, args : Json) -> String {
  guard parse_argv(args) is Some(argv) else {
    return "ERROR: run_command requires `argv` as an array of strings"
  }
  guard command_allowed(argv) else {
    return "ERROR: command is not in the allowlist"
  }
  let command = argv[0]
  let command_args = argv[1:]
  let (code, stdout, stderr) = @process.collect_output(
    command,
    command_args,
    cwd=config.workspace,
  )
  "exit_code: \{code}\nstdout:\n\{stdout.text()}\nstderr:\n\{stderr.text()}"
}

///|
async fn write_file_tool(config : AgentConfig, args : Json) -> String {
  guard json_required_string(args, "path") is Some(path) else {
    return "ERROR: write_file requires string field `path`"
  }
  guard json_required_string(args, "content") is Some(content) else {
    return "ERROR: write_file requires string field `content`"
  }
  let full = workspace_text_path_allow_missing(config, path)
  let dir = parent_dir(full)
  if dir != "." && !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
  @fs.write_file(full, content, create_mode=OpenOrCreate)
  "wrote \{content.length()} bytes to \{path}"
}

///|
fn replace_once(text : String, old_text : String, new_text : String) -> String {
  let parts = text.split(old_text).to_array()
  parts[0].to_owned() + new_text + parts[1].to_owned()
}

///|
fn replace_all_exact(
  text : String,
  old_text : String,
  new_text : String,
) -> String {
  text.split(old_text).to_array().join(new_text)
}

///|
async fn edit_file_tool(config : AgentConfig, args : Json) -> String {
  guard json_required_string(args, "path") is Some(path) else {
    return "ERROR: edit_file requires string field `path`"
  }
  guard json_required_string(args, "old_text") is Some(old_text) else {
    return "ERROR: edit_file requires string field `old_text`"
  }
  guard json_required_string(args, "new_text") is Some(new_text) else {
    return "ERROR: edit_file requires string field `new_text`"
  }
  guard old_text != "" else {
    return "ERROR: edit_file requires non-empty `old_text`"
  }
  let replace_all = json_optional_bool(args, "replace_all", false)
  let full = workspace_text_path(config, path)
  let text = @fs.read_file(full).text()
  let occurrences = text.split(old_text).to_array().length() - 1
  guard occurrences > 0 else { return "ERROR: `old_text` was not found" }
  let updated = if replace_all {
    replace_all_exact(text, old_text, new_text)
  } else {
    guard occurrences == 1 else {
      return "ERROR: `old_text` matched multiple locations; set `replace_all` to true"
    }
    replace_once(text, old_text, new_text)
  }
  @fs.write_file(full, updated)
  "edited \{path}; replaced \{occurrences} occurrence(s)"
}

///|
fn url_authority(url : String) -> String? {
  let prefix = if url.has_prefix("https://") {
    "https://"
  } else if url.has_prefix("http://") {
    "http://"
  } else {
    return None
  }
  let rest = match url.strip_prefix(prefix) {
    Some(value) => value
    None => return None
  }
  match rest.split("/").to_array() {
    [authority, ..] => Some(authority.to_owned())
    [] => None
  }
}

///|
fn host_from_authority(authority : String) -> String {
  let without_user = match authority.rev_split_once("@") {
    Some((_, host_port)) => host_port.to_owned()
    None => authority
  }
  if without_user.has_prefix("[") {
    match without_user.split("]").to_array() {
      [left, ..] =>
        match left.strip_prefix("[") {
          Some(host) => host.to_owned()
          None => left.to_owned()
        }
      _ => without_user
    }
  } else {
    match without_user.split(":").to_array() {
      [host, ..] => host.to_owned()
      [] => without_user
    }
  }
}

///|
fn is_ipv4(host : String) -> Bool {
  let parts = host.split(".").to_array()
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    let value = @string.parse_int(part) catch { _ => return false }
    if value < 0 || value > 255 {
      return false
    }
  }
  true
}

///|
fn is_private_ipv4(host : String) -> Bool {
  guard is_ipv4(host) else { return false }
  let parts = host.split(".").to_array()
  let first = @string.parse_int(parts[0]) catch { _ => 0 }
  let second = @string.parse_int(parts[1]) catch { _ => 0 }
  if first == 10 || first == 127 || first == 0 {
    return true
  }
  if first == 192 && second == 168 {
    return true
  }
  if first == 169 && second == 254 {
    return true
  }
  first == 172 && second >= 16 && second <= 31
}

///|
fn host_blocked(host : String) -> Bool {
  let lowered = ascii_lower(host)
  if lowered == "localhost" || lowered.has_suffix(".localhost") {
    return true
  }
  if lowered == "::1" ||
    lowered == "0:0:0:0:0:0:0:1" ||
    lowered.has_suffix(".local") {
    return true
  }
  is_private_ipv4(lowered)
}

///|
async fn web_fetch_tool(_config : AgentConfig, args : Json) -> String {
  guard json_required_string(args, "url") is Some(url) else {
    return "ERROR: web_fetch requires string field `url`"
  }
  guard url_authority(url) is Some(authority) else {
    return "ERROR: web_fetch only allows http/https URLs"
  }
  let host = host_from_authority(authority)
  guard !host_blocked(host) else {
    return "ERROR: blocked local or private host `\{host}`"
  }
  let headers : Map[String, String] = { "User-Agent": "DeepMoon/0.1" }
  let (response, body) = @async.with_timeout(8000, async fn() {
    @http.get(url, headers~)
  }) catch {
    _ => return "ERROR: web_fetch timed out or failed"
  }
  let text = body.text()
  let limited = summarize_text(text, 20000)
  "status: \{response.code}\nurl: \{url}\nbody:\n\{limited}"
}

///|
fn load_skill_tool(session : SessionState, args : Json) -> String {
  guard json_required_string(args, "name") is Some(name) else {
    return "ERROR: load_skill requires string field `name`"
  }
  guard session.skills_loader is Some(loader) else {
    return "ERROR: no skills directory is configured"
  }
  guard loader.get(name) is Some(definition) else {
    return "ERROR: unknown skill `\{name}`"
  }
  ignore(session.mark_skill_loaded(name))
  "loaded skill `\{definition.meta.name}` from \{definition.meta.path}"
}

///|
fn parse_todo_item(value : Json, default_id : Int) -> TodoItem? {
  guard value is Object(obj) else { return None }
  let content = match obj.get("content") {
    Some(String(text)) if text.trim() != "" => text.trim().to_owned()
    _ => return None
  }
  let id = match obj.get("id") {
    Some(Number(number, ..)) => number.to_int()
    _ => default_id
  }
  let status = match obj.get("status") {
    Some(String(text)) =>
      if text == "pending" || text == "in_progress" || text == "completed" {
        text
      } else {
        "pending"
      }
    _ => "pending"
  }
  Some({ id, content, status })
}

///|
fn update_todos_tool(session : SessionState, args : Json) -> String {
  let items = match args {
    Object(obj) =>
      match obj.get("todos") {
        Some(Array(values)) => values
        _ => return "ERROR: update_todos requires `todos` as an array"
      }
    _ => return "ERROR: update_todos requires `todos` as an array"
  }
  let todos : Array[TodoItem] = []
  let mut next_id = 1
  for value in items {
    if parse_todo_item(value, next_id) is Some(todo) {
      todos.push(todo)
      next_id = todo.id + 1
    }
  }
  let mut in_progress = 0
  for todo in todos {
    if todo.status == "in_progress" {
      in_progress += 1
    }
  }
  guard in_progress <= 1 else {
    return "ERROR: only one todo may be `in_progress` at a time"
  }
  session.set_todos(todos)
  "todos updated\n" + render_todos(session.todos)
}

///|
async fn[C : ModelClient] dispatch_subagent_tool(
  config : AgentConfig,
  session : SessionState,
  client : C,
  registry : ToolRegistry,
  args : Json,
) -> String {
  guard json_required_string(args, "agent_type") is Some(agent_type) else {
    return "ERROR: dispatch_subagent requires string field `agent_type`"
  }
  guard json_required_string(args, "task") is Some(task) else {
    return "ERROR: dispatch_subagent requires string field `task`"
  }
  let purpose = match json_optional_string(args, "purpose") {
    Some(text) => text
    None => task
  }
  guard find_subagent_spec(agent_type) is Some(spec) else {
    return "ERROR: unknown subagent `\{agent_type}`"
  }
  println("[subagent] \{spec.name}: \{summarize_text(purpose, 80)}")
  let sub_registry = registry.filter(spec.tool_names)
  let sub_config : AgentConfig = {
    api_key: config.api_key,
    base_url: config.base_url,
    model: config.model,
    workspace: config.workspace,
    history_path: None,
    skills_dir: config.skills_dir,
    memory_dir: config.memory_dir,
    context_window: config.context_window,
    max_steps: spec.max_turns,
    debug: config.debug,
  }
  let sub_session = SessionState::new(
    spec.system_prompt,
    session.skills_loader,
    None,
    None,
  )
  sub_session.history.push(Message::user(task))
  let result = run_agent(sub_config, client, sub_registry, sub_session)
  result.final_text
}

///|
pub fn[C : ModelClient] build_tool_registry(
  config : AgentConfig,
  session : SessionState,
  client : C,
) -> ToolRegistry {
  let registry = ToolRegistry::new()

  registry.register({
    name: "read_file",
    description: "Read a text file in the workspace with optional line bounds.",
    parameters: object_schema(
      {
        "path": string_schema("Relative path within the workspace"),
        "start_line": integer_schema("1-based first line to include"),
        "max_lines": integer_schema("Maximum number of lines to return"),
      },
      ["path"],
    ),
    concurrency_safe: false,
    execute: async fn(args) { read_file_tool(config, args) },
  })

  registry.register({
    name: "list_dir",
    description: "List entries in a workspace directory.",
    parameters: object_schema(
      { "path": string_schema("Relative directory path, defaulting to .") },
      [],
    ),
    concurrency_safe: false,
    execute: async fn(args) { list_dir_tool(config, args) },
  })

  registry.register({
    name: "search",
    description: "Search workspace text using rg.",
    parameters: object_schema(
      {
        "pattern": string_schema("Regular expression pattern for rg"),
        "path": string_schema("Relative path to search, defaulting to ."),
        "glob": string_schema("Optional rg glob such as *.mbt"),
      },
      ["pattern"],
    ),
    concurrency_safe: false,
    execute: async fn(args) { search_tool(config, args) },
  })

  registry.register({
    name: "glob",
    description: "List workspace files that match a glob pattern.",
    parameters: object_schema(
      {
        "pattern": string_schema("rg glob such as *.mbt or templates/**/*.md"),
        "path": string_schema("Relative search root, defaulting to ."),
      },
      ["pattern"],
    ),
    concurrency_safe: false,
    execute: async fn(args) { glob_tool(config, args) },
  })

  registry.register({
    name: "run_command",
    description: "Run an allowlisted command via argv, never through a shell.",
    parameters: object_schema(
      { "argv": array_of_strings_schema("Command argv") },
      ["argv"],
    ),
    concurrency_safe: false,
    execute: async fn(args) { run_command_tool(config, args) },
  })

  registry.register({
    name: "write_file",
    description: "Write a UTF-8 text file inside the workspace, creating parent directories as needed.",
    parameters: object_schema(
      {
        "path": string_schema("Relative file path within the workspace"),
        "content": string_schema("Full file content to write"),
      },
      ["path", "content"],
    ),
    concurrency_safe: false,
    execute: async fn(args) { write_file_tool(config, args) },
  })

  registry.register({
    name: "edit_file",
    description: "Replace exact text inside a workspace file. Use replace_all only when every match should change.",
    parameters: object_schema(
      {
        "path": string_schema("Relative file path within the workspace"),
        "old_text": string_schema("Exact text to replace"),
        "new_text": string_schema("Replacement text"),
        "replace_all": boolean_schema("Whether to replace every occurrence"),
      },
      ["path", "old_text", "new_text"],
    ),
    concurrency_safe: false,
    execute: async fn(args) { edit_file_tool(config, args) },
  })

  registry.register({
    name: "web_fetch",
    description: "Fetch a public http/https URL with GET. Localhost, loopback, and private-network hosts are blocked.",
    parameters: object_schema(
      { "url": string_schema("Public http or https URL") },
      ["url"],
    ),
    concurrency_safe: true,
    execute: async fn(args) { web_fetch_tool(config, args) },
  })

  registry.register({
    name: "load_skill",
    description: "Load a skill definition into the next system prompt without copying the entire skill into history.",
    parameters: object_schema({ "name": string_schema("Skill name to load") }, [
      "name",
    ]),
    concurrency_safe: false,
    execute: async fn(args) { load_skill_tool(session, args) },
  })

  registry.register({
    name: "update_todos",
    description: "Replace the current todo list. Statuses must be pending, in_progress, or completed, and only one item may be in_progress.",
    parameters: object_schema(
      {
        "todos": Json::object({
          "type": Json::string("array"),
          "description": Json::string("Complete todo list in execution order"),
          "items": object_schema(
            {
              "id": integer_schema("Stable todo id"),
              "content": string_schema("What to do"),
              "status": string_schema("pending, in_progress, or completed"),
            },
            ["id", "content", "status"],
          ),
        }),
      },
      ["todos"],
    ),
    concurrency_safe: false,
    execute: async fn(args) { update_todos_tool(session, args) },
  })

  registry.register({
    name: "dispatch_subagent",
    description: "Run a bounded subagent with isolated history and return only its summary.\n\nAvailable subagents:\n\{describe_subagents()}",
    parameters: object_schema(
      {
        "agent_type": string_schema("One of the built-in subagent roles"),
        "task": string_schema("Bounded task for the subagent"),
        "purpose": string_schema("Short label for terminal trace output"),
      },
      ["agent_type", "task"],
    ),
    concurrency_safe: true,
    execute: async fn(args) {
      dispatch_subagent_tool(config, session, client, registry, args)
    },
  })

  registry
}
