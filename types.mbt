///|
pub struct AgentConfig {
  api_key : String
  base_url : String
  model : String
  workspace : String
  history_path : String?
  skills_dir : String
  memory_dir : String
  context_window : Int
  max_steps : Int
  mut debug : Bool
}

///|
pub struct ToolCall {
  id : String
  name : String
  arguments : String
}

///|
pub struct Message {
  role : String
  content : String?
  tool_calls : Array[ToolCall]
  tool_call_id : String?
}

///|
pub struct ToolSpec {
  name : String
  description : String
  parameters : Json
}

///|
pub struct TokenUsage {
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
}

///|
pub struct CompletionResult {
  message : Message
  usage : TokenUsage?
}

///|
pub struct TodoItem {
  id : Int
  content : String
  status : String
}

///|
pub struct SkillMeta {
  name : String
  description : String
  tags : String?
  always : Bool
  path : String
}

///|
pub struct SkillDefinition {
  meta : SkillMeta
  body : String
}

///|
pub struct SubagentSpec {
  name : String
  description : String
  system_prompt : String
  tool_names : Array[String]
  max_turns : Int
}

///|
pub struct AgentResult {
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
pub(open) trait ModelClient {
  async complete(Self, AgentConfig, Array[Message], Array[ToolSpec]) -> CompletionResult
}
