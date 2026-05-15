///|
pub(all) struct MemoryStore {
  memory_dir : String
  memory_file : String
  user_file : String
  history_file : String
}

///|
fn current_timestamp() -> String {
  @env.now().to_string()
}

///|
fn current_date() -> String {
  let now = current_timestamp()
  if now.length() >= 10 {
    now[:10].to_owned()
  } else {
    now
  }
}

///|
fn default_memory_markdown() -> String {
  "# Long-Term Memory\n\nRecord durable goals, important facts, and ongoing constraints here.\n"
}

///|
fn default_user_markdown() -> String {
  "# User Preferences\n\nRecord durable user preferences only when they are strongly signaled.\n"
}

///|
async fn ensure_file(path : String, content : String) -> Unit {
  if !@fs.exists(path) {
    let dir = parent_dir(path)
    if dir != "." && !@fs.exists(dir) {
      @fs.mkdir(dir, recursive=true)
    }
    @fs.write_file(path, content, create_mode=OpenOrCreate)
  }
}

///|
pub async fn open_memory_store(memory_dir : String) -> MemoryStore {
  if !@fs.exists(memory_dir) {
    @fs.mkdir(memory_dir, recursive=true)
  }
  let store : MemoryStore = {
    memory_dir,
    memory_file: "\{memory_dir}/MEMORY.md",
    user_file: "\{memory_dir}/USER.md",
    history_file: "\{memory_dir}/history.jsonl",
  }
  ensure_file(store.memory_file, default_memory_markdown())
  ensure_file(store.user_file, default_user_markdown())
  ensure_file(store.history_file, "")
  store
}

///|
pub fn MemoryStore::today_episode_path(self : MemoryStore) -> String {
  "\{self.memory_dir}/\{current_date()}.md"
}

///|
pub async fn MemoryStore::read_memory(self : MemoryStore) -> String {
  @fs.read_file(self.memory_file).text() catch {
    _ => default_memory_markdown()
  }
}

///|
pub async fn MemoryStore::write_memory(
  self : MemoryStore,
  content : String,
) -> Unit {
  @fs.write_file(
    self.memory_file,
    content.trim().to_owned() + "\n",
    create_mode=OpenOrCreate,
  )
}

///|
pub async fn MemoryStore::read_user(self : MemoryStore) -> String {
  @fs.read_file(self.user_file).text() catch {
    _ => default_user_markdown()
  }
}

///|
pub async fn MemoryStore::write_user(
  self : MemoryStore,
  content : String,
) -> Unit {
  @fs.write_file(
    self.user_file,
    content.trim().to_owned() + "\n",
    create_mode=OpenOrCreate,
  )
}

///|
pub async fn MemoryStore::read_today_episode(self : MemoryStore) -> String {
  let path = self.today_episode_path()
  @fs.read_file(path).text() catch {
    _ => ""
  }
}

///|
pub async fn MemoryStore::append_episode(
  self : MemoryStore,
  content : String,
) -> Unit {
  let path = self.today_episode_path()
  let header = "# \{current_date()} Episode Memory\n"
  let existing = @fs.read_file(path).text() catch { _ => header }
  let text = existing.trim().to_owned() +
    "\n\n" +
    content.trim().to_owned() +
    "\n"
  @fs.write_file(path, text, create_mode=OpenOrCreate)
}

///|
pub async fn MemoryStore::append_message(
  self : MemoryStore,
  message : Message,
) -> Unit {
  let line = message.to_memory_json(current_timestamp()).stringify() + "\n"
  @fs.write_file(self.history_file, line, create_mode=OpenOrCreate, append=true)
}

///|
pub async fn MemoryStore::append_compact_marker(self : MemoryStore) -> Unit {
  let row = Json::object({
    "ts": Json::string(current_timestamp()),
    "type": Json::string("compact_event"),
  })
  @fs.write_file(
    self.history_file,
    row.stringify() + "\n",
    create_mode=OpenOrCreate,
    append=true,
  )
}

///|
pub async fn MemoryStore::load_unarchived_messages(
  self : MemoryStore,
) -> Array[Message] {
  let text = @fs.read_file(self.history_file).text() catch { _ => return [] }
  let mut messages : Array[Message] = []
  for line in text.split("\n") {
    let trimmed = line.trim()
    if trimmed == "" {
      continue
    }
    let value = @json.parse(trimmed) catch { _ => continue }
    match value {
      Object(obj) =>
        if obj.get("type") is Some(String("compact_event")) {
          messages = []
        } else if parse_message_json(value) is Some(message) {
          messages.push(message)
        }
      _ => ()
    }
  }
  messages
}
