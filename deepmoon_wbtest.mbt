///|
test "path safety rejects absolute and parent paths" {
  assert_true(path_is_lexically_safe("README.mbt.md"))
  assert_true(path_is_lexically_safe("cmd/main/main.mbt"))
  assert_false(path_is_lexically_safe("/etc/passwd"))
  assert_false(path_is_lexically_safe("../README.mbt.md"))
  assert_false(path_is_lexically_safe("cmd/../README.mbt.md"))
}

///|
test "command allowlist accepts only read-only argv" {
  assert_true(command_allowed(["pwd"]))
  assert_true(command_allowed(["moon", "check", "--target", "native"]))
  assert_true(command_allowed(["sed", "-n", "1,10p", "README.mbt.md"]))
  assert_false(command_allowed(["sh", "-c", "echo nope"]))
  assert_false(command_allowed(["rm", "-rf", "_build"]))
  assert_false(command_allowed(["cat", "../secret.txt"]))
  assert_false(command_allowed(["moon", "test", "--update"]))
}

///|
test "parse chat response with tool call" {
  let response = @json.parse(
    (
      #|{
      #|  "choices": [
      #|    {
      #|      "message": {
      #|        "role": "assistant",
      #|        "content": null,
      #|        "tool_calls": [
      #|          {
      #|            "id": "call_1",
      #|            "type": "function",
      #|            "function": {
      #|              "name": "read_file",
      #|              "arguments": "{\"path\":\"README.mbt.md\"}"
      #|            }
      #|          }
      #|        ]
      #|      }
      #|    }
      #|  ]
      #|}
    ),
  )
  let message = parse_chat_response(response)
  assert_true(message.content is None)
  assert_true(message.tool_calls is [{ id: "call_1", name: "read_file", .. }])
}

///|
struct FakeClient {
  mut calls : Int
}

///|
impl ModelClient for FakeClient with complete(self, _config, messages, _tools) {
  self.calls += 1
  if self.calls == 1 {
    Message::assistant(None, [
      {
        id: "call_1",
        name: "read_file",
        arguments: "{\"path\":\"README.mbt.md\",\"max_lines\":1}",
      },
    ])
  } else {
    assert_true(messages.last() is Some({ role: "tool", content: Some(_), .. }))
    Message::assistant(Some("done"), [])
  }
}

///|
fn test_config(history_path~ : String?) -> AgentConfig {
  {
    api_key: "test-key",
    base_url: "http://127.0.0.1",
    model: "test-model",
    workspace: @env.current_dir().unwrap_or("."),
    history_path,
    max_steps: 4,
    debug: false,
  }
}

///|
async test "agent loop executes tool call and returns final answer" {
  let fake = { calls: 0 }
  let result = run_agent(test_config(history_path=None), fake, [
    Message::system("system"),
    Message::user("read readme"),
  ])
  assert_true(result.final_text == "done")
  assert_true(fake.calls == 2)
  assert_true(result.messages.any(message => message.role == "tool"))
}

///|
async test "history appends full message jsonl" {
  let dir = "_build/deepmoon_history_test"
  let path = "\{dir}/history.jsonl"
  @fs.remove(path) catch {
    _ => ()
  }
  append_history_message(Some(path), Message::user("hello"))
  append_history_message(Some(path), Message::tool("call_1", "tool output"))
  let text = @fs.read_file(path).text()
  assert_true(text.contains("\"role\":\"user\""))
  assert_true(text.contains("\"role\":\"tool\""))
  assert_true(text.contains("\"tool_call_id\":\"call_1\""))
}
