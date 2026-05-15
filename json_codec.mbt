///|
fn json_obj(pairs : Array[(String, Json)]) -> Json {
  let obj : Map[String, Json] = {}
  for pair in pairs {
    let (key, value) = pair
    obj[key] = value
  }
  Json::object(obj)
}

///|
fn json_string_array(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}

///|
fn json_content(content : String?) -> Json {
  match content {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
pub fn ToolCall::to_chat_json(self : ToolCall) -> Json {
  json_obj([
    ("id", Json::string(self.id)),
    ("type", Json::string("function")),
    (
      "function",
      json_obj([
        ("name", Json::string(self.name)),
        ("arguments", Json::string(self.arguments)),
      ]),
    ),
  ])
}

///|
pub fn Message::to_chat_json(self : Message) -> Json {
  let fields : Array[(String, Json)] = [
    ("role", Json::string(self.role)),
    ("content", json_content(self.content)),
  ]
  if self.tool_calls.length() > 0 {
    fields.push(
      (
        "tool_calls",
        Json::array(self.tool_calls.map(call => call.to_chat_json())),
      ),
    )
  }
  if self.tool_call_id is Some(id) {
    fields.push(("tool_call_id", Json::string(id)))
  }
  json_obj(fields)
}

///|
pub fn Message::to_history_json(self : Message) -> Json {
  self.to_chat_json()
}

///|
pub fn Message::to_memory_json(self : Message, ts : String) -> Json {
  let fields : Array[(String, Json)] = [("ts", Json::string(ts))]
  match self.to_chat_json() {
    Object(obj) =>
      for pair in obj.to_array() {
        fields.push(pair)
      }
    _ => ()
  }
  json_obj(fields)
}

///|
pub fn ToolSpec::to_chat_json(self : ToolSpec) -> Json {
  json_obj([
    ("type", Json::string("function")),
    (
      "function",
      json_obj([
        ("name", Json::string(self.name)),
        ("description", Json::string(self.description)),
        ("parameters", self.parameters),
      ]),
    ),
  ])
}

///|
pub fn build_chat_request(
  model : String,
  messages : Array[Message],
  tools : Array[ToolSpec],
) -> Json {
  let fields : Array[(String, Json)] = [
    ("model", Json::string(model)),
    ("messages", Json::array(messages.map(message => message.to_chat_json()))),
  ]
  if !tools.is_empty() {
    fields.push(("tools", Json::array(tools.map(tool => tool.to_chat_json()))))
    fields.push(("tool_choice", Json::string("auto")))
  }
  json_obj(fields)
}

///|
fn json_get(value : Json, key : String) -> Json? {
  match value {
    Object(obj) => obj.get(key)
    _ => None
  }
}

///|
fn json_string_field(value : Json, key : String) -> String? {
  match json_get(value, key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn json_int_field(value : Json, key : String) -> Int? {
  match json_get(value, key) {
    Some(Number(number, ..)) => Some(number.to_int())
    _ => None
  }
}

///|
fn parse_tool_call(value : Json) -> ToolCall? {
  guard json_string_field(value, "id") is Some(id) else { return None }
  guard json_get(value, "function") is Some(fn_json) else { return None }
  guard json_string_field(fn_json, "name") is Some(name) else { return None }
  let arguments = match json_string_field(fn_json, "arguments") {
    Some(arguments) => arguments
    None => "{}"
  }
  Some({ id, name, arguments })
}

///|
pub fn parse_message_json(value : Json) -> Message? {
  guard json_string_field(value, "role") is Some(role) else { return None }
  let content = json_string_field(value, "content")
  let tool_calls : Array[ToolCall] = []
  if json_get(value, "tool_calls") is Some(Array(calls)) {
    for call in calls {
      if parse_tool_call(call) is Some(parsed) {
        tool_calls.push(parsed)
      }
    }
  }
  let tool_call_id = json_string_field(value, "tool_call_id")
  Some({ role, content, tool_calls, tool_call_id })
}

///|
fn parse_usage_json(value : Json) -> TokenUsage? {
  guard json_int_field(value, "prompt_tokens") is Some(prompt_tokens) else {
    return None
  }
  guard json_int_field(value, "completion_tokens") is Some(completion_tokens) else {
    return None
  }
  let total_tokens = match json_int_field(value, "total_tokens") {
    Some(total) => total
    None => prompt_tokens + completion_tokens
  }
  Some({ prompt_tokens, completion_tokens, total_tokens })
}

///|
pub fn parse_chat_response(value : Json) -> CompletionResult raise {
  guard json_get(value, "choices") is Some(Array([choice, ..])) else {
    fail("chat response does not contain choices[0]")
  }
  guard json_get(choice, "message") is Some(message) else {
    fail("chat response does not contain choices[0].message")
  }
  guard parse_message_json(message) is Some(parsed_message) else {
    fail("chat response message is malformed")
  }
  let usage = match json_get(value, "usage") {
    Some(usage_json) => parse_usage_json(usage_json)
    None => None
  }
  { message: parsed_message, usage }
}

///|
pub fn boolean_schema(description : String) -> Json {
  json_obj([
    ("type", Json::string("boolean")),
    ("description", Json::string(description)),
  ])
}

///|
pub fn string_schema(description : String) -> Json {
  json_obj([
    ("type", Json::string("string")),
    ("description", Json::string(description)),
  ])
}

///|
pub fn integer_schema(description : String) -> Json {
  json_obj([
    ("type", Json::string("integer")),
    ("description", Json::string(description)),
  ])
}

///|
pub fn array_of_strings_schema(description : String) -> Json {
  json_obj([
    ("type", Json::string("array")),
    ("description", Json::string(description)),
    ("items", json_obj([("type", Json::string("string"))])),
  ])
}

///|
pub fn object_schema(
  properties : Map[String, Json],
  required : Array[String],
) -> Json {
  json_obj([
    ("type", Json::string("object")),
    ("properties", Json::object(properties)),
    ("required", json_string_array(required)),
    ("additionalProperties", Json::boolean(false)),
  ])
}
