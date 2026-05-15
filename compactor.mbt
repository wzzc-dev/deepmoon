///|
fn history_to_transcript(messages : Array[Message]) -> String {
  let lines : Array[String] = []
  for message in messages {
    if message.tool_calls.is_empty() {
      let content = match message.content {
        Some(text) => summarize_text(text, 600)
        None => ""
      }
      lines.push("[\{message.role}] \{content}")
    } else {
      let tool_names = message.tool_calls.map(call => call.name).join(", ")
      lines.push("[assistant:tool_calls] \{tool_names}")
    }
  }
  lines.join("\n")
}

///|
fn extract_tag(text : String, tag : String) -> String? {
  let start_tag = "<\{tag}>"
  let end_tag = "</\{tag}>"
  match text.split(start_tag).to_array() {
    [_before, after, ..] =>
      match after.split(end_tag).to_array() {
        [body, ..] => Some(body.trim().to_owned())
        _ => None
      }
    _ => None
  }
}

///|
async fn build_compact_prompt(
  session : SessionState,
  old_messages : Array[Message],
) -> String {
  let memory = match session.memory_store {
    Some(store) => store.read_memory()
    None => "(no memory store)"
  }
  let user = match session.memory_store {
    Some(store) => store.read_user()
    None => "(no user preferences)"
  }
  let episode = match session.memory_store {
    Some(store) => store.read_today_episode()
    None => "(no episode memory)"
  }
  default_compact_prompt()
  .replace_all(old="{current_memory}", new=memory.trim())
  .replace_all(old="{current_user}", new=user.trim())
  .replace_all(old="{today_episode}", new=episode.trim())
  .replace_all(
    old="{old_conversation}",
    new=history_to_transcript(old_messages),
  )
}

///|
fn fallback_compact_needed(
  config : AgentConfig,
  session : SessionState,
) -> Bool {
  if session.history.length() > 24 {
    return true
  }
  let mut body_size = 0
  for message in session.history {
    body_size += message.to_history_json().stringify().length()
  }
  body_size > config.context_window * 6
}

///|
pub fn should_compact_now(config : AgentConfig, session : SessionState) -> Bool {
  if session.force_compact {
    return true
  }
  match session.token_tracker {
    Some(tracker) => tracker.should_compact(config.context_window)
    None => fallback_compact_needed(config, session)
  }
}

///|
pub async fn[C : ModelClient] compact_session_history(
  config : AgentConfig,
  client : C,
  session : SessionState,
) -> Bool {
  guard session.memory_store is Some(store) else {
    session.force_compact = false
    return false
  }
  guard session.history.length() > 10 else {
    session.force_compact = false
    return false
  }
  let recent : Array[Message] = []
  let old_messages : Array[Message] = []
  let split_at = session.history.length() - 10
  for i = 0; i < session.history.length(); i = i + 1 {
    if i < split_at {
      old_messages.push(session.history[i])
    } else {
      recent.push(session.history[i])
    }
  }
  let prompt = build_compact_prompt(session, old_messages)
  let result = client.complete(config, [Message::user(prompt)], [])
  if result.usage is Some(usage) {
    if session.token_tracker is Some(tracker) {
      tracker.record(config.model, usage)
    }
  }
  let content = match result.message.content {
    Some(text) => text
    None => ""
  }
  if extract_tag(content, "episode") is Some(episode) && episode != "" {
    store.append_episode(episode)
  }
  if extract_tag(content, "updated_memory") is Some(memory) && memory != "" {
    store.write_memory(memory)
  }
  if extract_tag(content, "updated_user") is Some(user) && user != "" {
    store.write_user(user)
  }
  store.append_compact_marker()
  session.history = recent
  session.force_compact = false
  true
}

///|
pub async fn[C : ModelClient] compact_startup_history(
  config : AgentConfig,
  client : C,
  session : SessionState,
) -> Bool {
  guard session.memory_store is Some(store) else { return false }
  let old_messages = store.load_unarchived_messages()
  guard old_messages.length() > 1 else { return false }
  let prompt = build_compact_prompt(session, old_messages)
  let result = client.complete(config, [Message::user(prompt)], [])
  if result.usage is Some(usage) {
    if session.token_tracker is Some(tracker) {
      tracker.record(config.model, usage)
    }
  }
  let content = match result.message.content {
    Some(text) => text
    None => ""
  }
  if extract_tag(content, "episode") is Some(episode) && episode != "" {
    store.append_episode(episode)
  }
  if extract_tag(content, "updated_memory") is Some(memory) && memory != "" {
    store.write_memory(memory)
  }
  if extract_tag(content, "updated_user") is Some(user) && user != "" {
    store.write_user(user)
  }
  store.append_compact_marker()
  true
}
