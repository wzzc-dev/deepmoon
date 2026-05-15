///|
fn trace_tool(config : AgentConfig, call : ToolCall, output : String) -> Unit {
  println("[tool] \{call.name} \{summarize_text(call.arguments, 160)}")
  if config.debug {
    println(output)
  } else {
    let compact = output.replace_all(old="\n", new=" ")
    println("[tool] output: \{summarize_text(compact, 200)}")
  }
}

///|
async fn record_usage(
  config : AgentConfig,
  session : SessionState,
  usage : TokenUsage?,
) -> Unit {
  if usage is Some(usage) {
    if session.token_tracker is Some(tracker) {
      tracker.record(config.model, usage)
    }
  }
}

///|
async fn append_session_message(
  config : AgentConfig,
  session : SessionState,
  message : Message,
) -> Unit {
  session.history.push(message)
  append_persistent_message(config, session, message)
}

///|
async fn build_model_messages(
  config : AgentConfig,
  session : SessionState,
) -> Array[Message] {
  let prompt = build_system_prompt(config, session)
  let messages = [Message::system(prompt)]
  for message in session.history {
    messages.push(message)
  }
  messages
}

///|
async fn execute_tool_batch(
  registry : ToolRegistry,
  calls : Array[ToolCall],
) -> Array[String] {
  if calls.length() <= 1 {
    let outputs : Array[String] = []
    for call in calls {
      outputs.push(registry.run_tool_call(call))
    }
    return outputs
  }
  println("[tool] running \{calls.length()} safe calls in parallel")
  let jobs : Array[async () -> String] = []
  for call in calls {
    let this_call = call
    jobs.push(async fn() { registry.run_tool_call(this_call) })
  }
  @async.all(jobs)
}

///|
async fn execute_tool_calls(
  config : AgentConfig,
  registry : ToolRegistry,
  session : SessionState,
  calls : Array[ToolCall],
) -> Unit {
  let mut index = 0
  while index < calls.length() {
    let call = calls[index]
    let safe = match registry.get(call.name) {
      Some(tool) => tool.concurrency_safe
      None => false
    }
    if safe {
      let batch : Array[ToolCall] = [call]
      let mut cursor = index + 1
      while cursor < calls.length() {
        let next_call = calls[cursor]
        if registry.get(next_call.name) is Some({ concurrency_safe: true, .. }) {
          batch.push(next_call)
          cursor += 1
        } else {
          break
        }
      }
      let outputs = execute_tool_batch(registry, batch)
      for i = 0; i < batch.length(); i = i + 1 {
        let tool_call = batch[i]
        let output = outputs[i]
        trace_tool(config, tool_call, output)
        append_session_message(
          config,
          session,
          Message::tool(tool_call.id, output),
        )
      }
      index = cursor
    } else {
      let output = registry.run_tool_call(call)
      trace_tool(config, call, output)
      append_session_message(config, session, Message::tool(call.id, output))
      index += 1
    }
  }
}

///|
pub async fn[C : ModelClient] run_agent(
  config : AgentConfig,
  client : C,
  registry : ToolRegistry,
  session : SessionState,
) -> AgentResult {
  let max_steps = config.max_steps.max(1)
  let mut step = 0
  while step < max_steps {
    if should_compact_now(config, session) {
      ignore(compact_session_history(config, client, session))
    }
    let request_messages = build_model_messages(config, session)
    let result = client.complete(
      config,
      request_messages,
      registry.tool_specs(),
    )
    record_usage(config, session, result.usage)
    append_session_message(config, session, result.message)
    if result.message.tool_calls.is_empty() {
      let final_text = match result.message.content {
        Some(text) => text
        None => ""
      }
      return { final_text, messages: session.history.copy() }
    }
    execute_tool_calls(config, registry, session, result.message.tool_calls)
    step += 1
  }
  let final_text = "Stopped after \{max_steps} tool-calling step(s)."
  let stop_message = Message::assistant(Some(final_text), [])
  append_session_message(config, session, stop_message)
  { final_text, messages: session.history.copy() }
}

///|
pub async fn[C : ModelClient] open_main_session(
  config : AgentConfig,
  client : C,
) -> SessionState {
  let skills_loader = load_skills(
    join_workspace_path(config.workspace, config.skills_dir),
  )
  let memory_store = open_memory_store(
    join_workspace_path(config.workspace, config.memory_dir),
  )
  let token_tracker = open_token_tracker(
    "\{join_workspace_path(config.workspace, config.memory_dir)}/tokens.jsonl",
  )
  let session = SessionState::new(
    default_agent_base_prompt(),
    Some(skills_loader),
    Some(memory_store),
    Some(token_tracker),
  )
  ignore(compact_startup_history(config, client, session))
  session
}
