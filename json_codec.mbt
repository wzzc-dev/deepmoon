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
  json_obj([
    ("model", Json::string(model)),
    ("messages", Json::array(messages.map(message => message.to_chat_json()))),
    ("tools", Json::array(tools.map(tool => tool.to_chat_json()))),
    ("tool_choice", Json::string("auto")),
  ])
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
pub fn parse_chat_response(value : Json) -> Message raise {
  guard json_get(value, "choices") is Some(Array([choice, ..])) else {
    fail("chat response does not contain choices[0]")
  }
  guard json_get(choice, "message") is Some(message) else {
    fail("chat response does not contain choices[0].message")
  }
  let content = json_string_field(message, "content")
  let tool_calls : Array[ToolCall] = []
  if json_get(message, "tool_calls") is Some(Array(calls)) {
    for call in calls {
      if parse_tool_call(call) is Some(parsed) {
        tool_calls.push(parsed)
      }
    }
  }
  Message::assistant(content, tool_calls)
}

///|
fn string_schema(description : String) -> Json {
  json_obj([
    ("type", Json::string("string")),
    ("description", Json::string(description)),
  ])
}

///|
fn integer_schema(description : String) -> Json {
  json_obj([
    ("type", Json::string("integer")),
    ("description", Json::string(description)),
  ])
}

///|
fn array_of_strings_schema(description : String) -> Json {
  json_obj([
    ("type", Json::string("array")),
    ("description", Json::string(description)),
    ("items", json_obj([("type", Json::string("string"))])),
  ])
}

///|
fn object_schema(
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

///|
pub fn default_tool_specs() -> Array[ToolSpec] {
  let read_props : Map[String, Json] = {
    "path": string_schema("Relative path to read within the workspace"),
    "start_line": integer_schema("1-based first line to include"),
    "max_lines": integer_schema("Maximum number of lines to return"),
  }
  let list_props : Map[String, Json] = {
    "path": string_schema("Relative directory path within the workspace"),
  }
  let search_props : Map[String, Json] = {
    "pattern": string_schema("Regular expression pattern for rg"),
    "path": string_schema("Relative path to search, defaulting to ."),
    "glob": string_schema("Optional rg glob, such as *.mbt"),
  }
  let command_props : Map[String, Json] = {
    "argv": array_of_strings_schema("Command argv, not a shell string"),
  }
  [
    {
      name: "read_file",
      description: "Read a text file in the workspace with optional line bounds.",
      parameters: object_schema(read_props, ["path"]),
    },
    {
      name: "list_dir",
      description: "List entries in a workspace directory.",
      parameters: object_schema(list_props, ["path"]),
    },
    {
      name: "search",
      description: "Search workspace text using rg.",
      parameters: object_schema(search_props, ["pattern"]),
    },
    {
      name: "run_command",
      description: "Run an allowed read-only command with argv, never through a shell.",
      parameters: object_schema(command_props, ["argv"]),
    },
  ]
}
