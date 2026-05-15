///|
pub(all) struct SkillsLoader {
  definitions : Map[String, SkillDefinition]
  order : Array[String]
}

///|
pub fn SkillsLoader::empty() -> SkillsLoader {
  { definitions: {}, order: [] }
}

///|
fn parse_frontmatter_line(meta : Map[String, String], line : String) -> Unit {
  let parts = line.split(":").to_array()
  guard parts.length() >= 2 else { return }
  let key = parts[0].trim().to_owned()
  let value = strip_wrapping_quotes(parts[1:].join(":"))
  if key != "" {
    meta[key] = value
  }
}

///|
fn parse_frontmatter(text : String) -> (Map[String, String], String) {
  let lines = text.split("\n").to_array()
  guard lines.length() >= 3 && lines[0].trim() == "---" else {
    return ({}, text)
  }
  let meta : Map[String, String] = {}
  let mut body_start = -1
  for i = 1; i < lines.length(); i = i + 1 {
    if lines[i].trim() == "---" {
      body_start = i + 1
      break
    }
    parse_frontmatter_line(meta, lines[i].to_owned())
  }
  guard body_start >= 0 else { return ({}, text) }
  (meta, lines[body_start:].to_owned().join("\n").trim().to_owned())
}

///|
fn meta_bool(meta : Map[String, String], key : String) -> Bool {
  match meta.get(key) {
    Some(value) => ascii_lower(value) == "true"
    None => false
  }
}

///|
fn meta_string(meta : Map[String, String], key : String) -> String? {
  match meta.get(key) {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn skill_name_from_path(path : String) -> String {
  match parent_dir(path).rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => parent_dir(path)
  }
}

///|
async fn collect_skill_files(dir : String, out : Array[String]) -> Unit {
  if !@fs.exists(dir) {
    return
  }
  let entries = @fs.readdir(
    dir,
    include_hidden=true,
    include_special=false,
    sort=true,
  ) catch {
    _ => return
  }
  for entry in entries {
    let child = "\{dir}/\{entry}"
    if entry == "SKILL.md" {
      out.push(child)
    } else {
      collect_skill_files(child, out)
    }
  }
}

///|
pub async fn load_skills(skills_root : String) -> SkillsLoader {
  let files : Array[String] = []
  collect_skill_files(skills_root, files)
  files.sort()
  let loader = SkillsLoader::empty()
  for path in files {
    let text = @fs.read_file(path).text() catch { _ => continue }
    let (meta_map, body) = parse_frontmatter(text)
    let name = match meta_string(meta_map, "name") {
      Some(value) => value
      None => skill_name_from_path(path)
    }
    if loader.definitions.contains(name) {
      continue
    }
    let definition : SkillDefinition = {
      meta: {
        name,
        description: match meta_string(meta_map, "description") {
          Some(value) => value
          None => "No description"
        },
        tags: meta_string(meta_map, "tags"),
        always: meta_bool(meta_map, "always"),
        path,
      },
      body,
    }
    loader.order.push(name)
    loader.definitions[name] = definition
  }
  loader
}

///|
pub fn SkillsLoader::names(self : SkillsLoader) -> Array[String] {
  self.order.copy()
}

///|
pub fn SkillsLoader::get(
  self : SkillsLoader,
  name : String,
) -> SkillDefinition? {
  self.definitions.get(name)
}

///|
pub fn SkillsLoader::always_names(self : SkillsLoader) -> Array[String] {
  let names : Array[String] = []
  for name in self.order {
    if self.definitions.get(name) is Some({ meta: { always: true, .. }, .. }) {
      names.push(name)
    }
  }
  names
}

///|
pub fn SkillsLoader::summary(
  self : SkillsLoader,
  loaded : Array[String],
) -> String {
  if self.order.is_empty() {
    return "(no skills available)"
  }
  let lines : Array[String] = []
  for name in self.order {
    guard self.definitions.get(name) is Some(definition) else { continue }
    let mut line = "- \{definition.meta.name}: \{definition.meta.description}"
    if definition.meta.always {
      line += " [always]"
    } else if loaded.contains(name) {
      line += " [loaded]"
    }
    if definition.meta.tags is Some(tags) {
      line += " [tags: \{tags}]"
    }
    lines.push(line)
  }
  lines.join("\n")
}
