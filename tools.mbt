///|
pub fn path_is_lexically_safe(path : String) -> Bool {
  if path == "" {
    return true
  }
  if path.has_prefix("/") || path.contains("\u{0}") {
    return false
  }
  for part in path.split("/") {
    if part == ".." {
      return false
    }
  }
  true
}

///|
fn workspace_path(config : AgentConfig, path : String) -> String {
  if path == "" || path == "." {
    config.workspace
  } else {
    "\{config.workspace}/\{path}"
  }
}

///|
async fn resolve_workspace_path(config : AgentConfig, path : String) -> String {
  guard path_is_lexically_safe(path) else {
    fail("path must be relative and must not contain ..")
  }
  let root = @fs.realpath(config.workspace)
  let full = @fs.realpath(workspace_path(config, path))
  guard full == root || full.has_prefix("\{root}/") else {
    fail("path escapes workspace")
  }
  full
}

///|
fn json_arg(arguments : String) -> Json? {
  Some(@json.parse(arguments)) catch {
    _ => None
  }
}

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
async fn read_file_tool(config : AgentConfig, args : Json) -> String {
  guard json_required_string(args, "path") is Some(path) else {
    return "ERROR: read_file requires string field `path`"
  }
  let full = resolve_workspace_path(config, path)
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
  let full = resolve_workspace_path(config, path)
  let entries = @fs.readdir(
    full,
    include_hidden=true,
    include_special=true,
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
  ignore(resolve_workspace_path(config, path))
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
    ["moon", "check"] | ["moon", "test"] => true
    ["moon", "check", "--target", "native"]
    | ["moon", "test", "--target", "native"] => true
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
    return "ERROR: command is not in the read-only allowlist"
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
pub async fn run_tool(config : AgentConfig, call : ToolCall) -> String {
  guard json_arg(call.arguments) is Some(args) else {
    return "ERROR: tool arguments are not valid JSON"
  }
  match call.name {
    "read_file" => read_file_tool(config, args)
    "list_dir" => list_dir_tool(config, args)
    "search" => search_tool(config, args)
    "run_command" => run_command_tool(config, args)
    other => "ERROR: unknown tool `\{other}`"
  }
}
