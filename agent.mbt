///|
fn summarize(text : String, limit : Int) -> String {
  if text.length() <= limit {
    text
  } else {
    text[:limit].to_owned() + "..."
  }
}

///|
fn trace_tool(config : AgentConfig, call : ToolCall, output : String) -> Unit {
  println("[tool] \{call.name} \{summarize(call.arguments, 160)}")
  if config.debug {
    println(output)
  } else {
    let compact = output.replace_all(old="\n", new=" ")
    println("[tool] output: \{summarize(compact, 200)}")
  }
}

///|
pub async fn[C : ModelClient] run_agent(
  config : AgentConfig,
  client : C,
  initial_messages : Array[Message],
) -> AgentResult {
  let messages = initial_messages.copy()
  let tools = default_tool_specs()
  let max_steps = config.max_steps.max(1)
  let mut step = 0
  while step < max_steps {
    let assistant = client.complete(config, messages, tools)
    messages.push(assistant)
    append_history_message(config.history_path, assistant)
    if assistant.tool_calls.is_empty() {
      let final_text = match assistant.content {
        Some(text) => text
        None => ""
      }
      return { final_text, messages }
    }
    for call in assistant.tool_calls {
      let output = run_tool(config, call) catch { _ => "ERROR: tool failed" }
      trace_tool(config, call, output)
      let tool_message = Message::tool(call.id, output)
      messages.push(tool_message)
      append_history_message(config.history_path, tool_message)
    }
    step += 1
  }
  let final_text = "Stopped after \{max_steps} tool-calling step(s)."
  let stop_message = Message::assistant(Some(final_text), [])
  messages.push(stop_message)
  append_history_message(config.history_path, stop_message)
  { final_text, messages }
}
