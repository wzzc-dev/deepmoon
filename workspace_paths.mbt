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
pub fn parent_dir(path : String) -> String {
  match path.rev_split_once("/") {
    Some((dir, _)) => {
      let text = dir.to_owned()
      if text == "" {
        "."
      } else {
        text
      }
    }
    None => "."
  }
}

///|
pub fn join_workspace_path(root : String, path : String) -> String {
  if path == "" || path == "." {
    root
  } else {
    "\{root}/\{path}"
  }
}

///|
fn path_segments(path : String) -> Array[String] {
  let segments : Array[String] = []
  for part in path.split("/").to_array() {
    if part != "" && part != "." {
      segments.push(part.to_owned())
    }
  }
  segments
}

///|
async fn resolve_workspace_path_internal(
  root : String,
  path : String,
  allow_missing : Bool,
) -> String {
  guard path_is_lexically_safe(path) else {
    fail("path must be relative and must not contain ..")
  }
  let root_real = @fs.realpath(root)
  let segments = path_segments(path)
  if segments.is_empty() {
    return root_real
  }
  let mut current = root_real
  for segment in segments {
    let next = "\{current}/\{segment}"
    if @fs.exists(next) {
      let resolved = @fs.realpath(next)
      guard resolved == root_real || resolved.has_prefix("\{root_real}/") else {
        fail("path escapes workspace")
      }
      current = resolved
    } else {
      guard allow_missing else { fail("path does not exist") }
      current = next
    }
  }
  current
}

///|
pub async fn resolve_workspace_path(root : String, path : String) -> String {
  resolve_workspace_path_internal(root, path, false)
}

///|
pub async fn resolve_workspace_path_allow_missing(
  root : String,
  path : String,
) -> String {
  resolve_workspace_path_internal(root, path, true)
}
