///|
pub(all) struct Tool {
  name : String
  description : String
  parameters : Json
  concurrency_safe : Bool
  execute : async (Json) -> String
}

///|
pub(all) struct ToolRegistry {
  tools : Map[String, Tool]
  order : Array[String]
}

///|
pub fn ToolRegistry::new() -> ToolRegistry {
  { tools: {}, order: [] }
}

///|
pub fn ToolRegistry::register(self : ToolRegistry, tool : Tool) -> Unit {
  if !self.tools.contains(tool.name) {
    self.order.push(tool.name)
  }
  self.tools[tool.name] = tool
}

///|
pub fn ToolRegistry::contains(self : ToolRegistry, name : String) -> Bool {
  self.tools.contains(name)
}

///|
pub fn ToolRegistry::get(self : ToolRegistry, name : String) -> Tool? {
  self.tools.get(name)
}

///|
pub fn ToolRegistry::tool_specs(self : ToolRegistry) -> Array[ToolSpec] {
  let specs : Array[ToolSpec] = []
  for name in self.order {
    if self.tools.get(name) is Some(tool) {
      specs.push({
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters,
      })
    }
  }
  specs
}

///|
pub fn ToolRegistry::filter(
  self : ToolRegistry,
  names : Array[String],
) -> ToolRegistry {
  let filtered = ToolRegistry::new()
  for name in names {
    if self.tools.get(name) is Some(tool) {
      filtered.register(tool)
    }
  }
  filtered
}

///|
fn parse_tool_arguments(arguments : String) -> Json? {
  Some(@json.parse(arguments)) catch {
    _ => None
  }
}

///|
pub async fn ToolRegistry::run_tool_call(
  self : ToolRegistry,
  call : ToolCall,
) -> String {
  guard self.tools.get(call.name) is Some(tool) else {
    return "ERROR: unknown tool `\{call.name}`"
  }
  guard parse_tool_arguments(call.arguments) is Some(args) else {
    return "ERROR: tool arguments are not valid JSON"
  }
  (tool.execute)(args)
}
