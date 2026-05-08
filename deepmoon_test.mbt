///|
test "default tool specs expose expected tools" {
  let tools = @deepmoon.default_tool_specs()
  assert_true(tools.length() == 4)
  assert_true(tools.any(tool => tool.name == "read_file"))
  assert_true(tools.any(tool => tool.name == "list_dir"))
  assert_true(tools.any(tool => tool.name == "search"))
  assert_true(tools.any(tool => tool.name == "run_command"))
}

///|
test "chat request encodes tools and messages" {
  let request = @deepmoon.build_chat_request(
    "test-model",
    [@deepmoon.Message::user("hello")],
    @deepmoon.default_tool_specs(),
  )
  let text = request.stringify()
  assert_true(text.contains("\"model\":\"test-model\""))
  assert_true(text.contains("\"messages\""))
  assert_true(text.contains("\"tools\""))
  assert_true(text.contains("\"tool_choice\":\"auto\""))
}
