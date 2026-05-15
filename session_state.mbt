///|
pub(all) struct SessionState {
  base_prompt : String
  mut history : Array[Message]
  mut loaded_skills : Array[String]
  mut todos : Array[TodoItem]
  skills_loader : SkillsLoader?
  memory_store : MemoryStore?
  token_tracker : TokenTracker?
  mut force_compact : Bool
}

///|
pub fn SessionState::new(
  base_prompt : String,
  skills_loader : SkillsLoader?,
  memory_store : MemoryStore?,
  token_tracker : TokenTracker?,
) -> SessionState {
  {
    base_prompt,
    history: [],
    loaded_skills: [],
    todos: [],
    skills_loader,
    memory_store,
    token_tracker,
    force_compact: false,
  }
}

///|
pub fn SessionState::clear_working(self : SessionState) -> Unit {
  self.history = []
  self.loaded_skills = []
  self.todos = []
  self.force_compact = false
}

///|
pub fn SessionState::mark_skill_loaded(
  self : SessionState,
  name : String,
) -> Bool {
  if self.loaded_skills.contains(name) {
    false
  } else {
    self.loaded_skills.push(name)
    true
  }
}

///|
pub fn SessionState::set_todos(
  self : SessionState,
  items : Array[TodoItem],
) -> Unit {
  self.todos = items
}

///|
fn unique_names(names : Array[String]) -> Array[String] {
  let unique : Array[String] = []
  for name in names {
    if !unique.contains(name) {
      unique.push(name)
    }
  }
  unique
}

///|
pub fn SessionState::context_skill_names(self : SessionState) -> Array[String] {
  let names : Array[String] = []
  match self.skills_loader {
    Some(loader) =>
      for name in loader.always_names() {
        names.push(name)
      }
    None => ()
  }
  for name in self.loaded_skills {
    names.push(name)
  }
  unique_names(names)
}

///|
pub fn SessionState::loaded_skill_definitions(
  self : SessionState,
) -> Array[SkillDefinition] {
  let definitions : Array[SkillDefinition] = []
  guard self.skills_loader is Some(loader) else { return definitions }
  for name in self.context_skill_names() {
    if loader.get(name) is Some(definition) {
      definitions.push(definition)
    }
  }
  definitions
}

///|
pub fn SessionState::available_skills_summary(self : SessionState) -> String {
  match self.skills_loader {
    Some(loader) => loader.summary(self.context_skill_names())
    None => "(no skills available)"
  }
}

///|
pub fn render_todos(items : Array[TodoItem]) -> String {
  if items.is_empty() {
    return "(no todos)"
  }
  let lines : Array[String] = []
  for item in items {
    let prefix = match item.status {
      "pending" => "[ ]"
      "in_progress" => "[~]"
      "completed" => "[x]"
      _ => "[?]"
    }
    lines.push("\{prefix} \{item.id}. \{item.content}")
  }
  lines.join("\n")
}
