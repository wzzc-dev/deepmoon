///|
fn subagent_spec(
  name : String,
  description : String,
  tool_names : Array[String],
  max_turns : Int,
) -> SubagentSpec {
  {
    name,
    description,
    system_prompt: default_subagent_prompt(name),
    tool_names,
    max_turns,
  }
}

///|
pub fn default_subagent_specs() -> Array[SubagentSpec] {
  [
    subagent_spec(
      "scout",
      "Fast workspace scouting with read-only tools for quick inspection.",
      ["list_dir", "glob", "search", "run_command"],
      6,
    ),
    subagent_spec(
      "reader",
      "Close reading of code and docs, with optional skill loading.",
      ["read_file", "list_dir", "glob", "search", "load_skill"],
      10,
    ),
    subagent_spec(
      "researcher",
      "External research and evidence gathering with web access.",
      ["web_fetch", "search", "read_file", "glob", "load_skill"],
      10,
    ),
    subagent_spec(
      "verifier",
      "Read-only validation of file layouts, diffs, and command output.",
      ["run_command", "read_file", "glob", "search", "list_dir"],
      8,
    ),
    subagent_spec(
      "editor",
      "Focused implementation work inside the workspace with safe file editing.",
      [
        "read_file", "write_file", "edit_file", "glob", "search", "run_command",
        "load_skill",
      ],
      12,
    ),
  ]
}

///|
pub fn find_subagent_spec(name : String) -> SubagentSpec? {
  for spec in default_subagent_specs() {
    if spec.name == name {
      return Some(spec)
    }
  }
  None
}

///|
pub fn describe_subagents() -> String {
  let lines : Array[String] = []
  for spec in default_subagent_specs() {
    lines.push("- \{spec.name}: \{spec.description}")
  }
  lines.join("\n")
}
