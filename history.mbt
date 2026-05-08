///|
fn parent_dir(path : String) -> String {
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
pub async fn ensure_history_path(path : String) -> Unit {
  let dir = parent_dir(path)
  if dir != "." && !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
}

///|
pub async fn append_history_message(path : String?, message : Message) -> Unit {
  match path {
    None => ()
    Some(path) => {
      ensure_history_path(path)
      let line = message.to_history_json().stringify() + "\n"
      @fs.write_file(path, line, create_mode=OpenOrCreate, append=true)
    }
  }
}

///|
pub fn default_history_path() -> String {
  ".deepmoon/sessions/\{@env.now()}.jsonl"
}
