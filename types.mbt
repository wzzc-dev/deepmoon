///|
pub(all) struct AgentConfig {
  api_key : String
  base_url : String
  model : String
  workspace : String
  history_path : String?
  max_steps : Int
  mut debug : Bool
}

///|
pub(all) struct ToolCall {
  id : String
  name : String
  arguments : String
}

///|
pub(all) struct Message {
  role : String
  content : String?
  tool_calls : Array[ToolCall]
  tool_call_id : String?
}

///|
pub(all) struct ToolSpec {
  name : String
  description : String
  parameters : Json
}

///|
pub(all) struct AgentResult {
  final_text : String
  messages : Array[Message]
}

///|
pub fn Message::system(content : String) -> Message {
  { role: "system", content: Some(content), tool_calls: [], tool_call_id: None }
}

///|
pub fn Message::user(content : String) -> Message {
  { role: "user", content: Some(content), tool_calls: [], tool_call_id: None }
}

///|
pub fn Message::assistant(
  content : String?,
  tool_calls : Array[ToolCall],
) -> Message {
  { role: "assistant", content, tool_calls, tool_call_id: None }
}

///|
pub fn Message::tool(tool_call_id : String, content : String) -> Message {
  {
    role: "tool",
    content: Some(content),
    tool_calls: [],
    tool_call_id: Some(tool_call_id),
  }
}

///|
pub fn default_system_prompt() -> String {
  (
    #|You are DeepMoon, a MoonBit native CLI coding agent.
    #|Use tools when you need to inspect this workspace or run safe read-only commands.
    #|All tools are confined to the current project directory. Never ask for file writes:
    #|this first version can only read files, search text, list directories, and run safe commands.
  )
}

///|
pub(open) trait ModelClient {
  async complete(Self, AgentConfig, Array[Message], Array[ToolSpec]) -> Message
}
