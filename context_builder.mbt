///|
fn skills_body_section(session : SessionState) -> String {
  let definitions = session.loaded_skill_definitions()
  if definitions.is_empty() {
    return ""
  }
  let parts : Array[String] = []
  for definition in definitions {
    parts.push(
      "## Skill: \{definition.meta.name}\nPath: \{definition.meta.path}\n\n\{definition.body}",
    )
  }
  parts.join("\n\n")
}

///|
async fn memory_section(session : SessionState) -> String {
  match session.memory_store {
    Some(store) => store.read_memory().trim().to_owned()
    None => ""
  }
}

///|
async fn user_section(session : SessionState) -> String {
  match session.memory_store {
    Some(store) => store.read_user().trim().to_owned()
    None => ""
  }
}

///|
pub async fn build_system_prompt(
  config : AgentConfig,
  session : SessionState,
) -> String {
  let prompt = StringBuilder::new()
  prompt.write_stringview(session.base_prompt.trim())
  prompt.write_stringview("\n\n## Workspace\n")
  prompt.write_stringview("Current workspace root: `")
  prompt.write_stringview(config.workspace)
  prompt.write_stringview("`\n")
  prompt.write_stringview("All file tools must stay within this workspace.\n")

  let memory = memory_section(session)
  if memory != "" {
    prompt.write_stringview("\n## Long-Term Memory\n")
    prompt.write_stringview(memory)
    prompt.write_stringview("\n")
  }

  let user = user_section(session)
  if user != "" {
    prompt.write_stringview("\n## User Preferences\n")
    prompt.write_stringview(user)
    prompt.write_stringview("\n")
  }

  prompt.write_stringview("\n## Current Todos\n")
  prompt.write_stringview(render_todos(session.todos))
  prompt.write_stringview("\n")

  prompt.write_stringview("\n## Available Skills\n")
  prompt.write_stringview(session.available_skills_summary())
  prompt.write_stringview("\n")

  let loaded_skills = skills_body_section(session)
  if loaded_skills != "" {
    prompt.write_stringview("\n## Loaded Skills\n")
    prompt.write_stringview(loaded_skills)
    prompt.write_stringview("\n")
  }

  prompt.to_string()
}
