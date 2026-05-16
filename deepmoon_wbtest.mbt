///|
test "path safety rejects absolute and parent paths" {
  assert_true(path_is_lexically_safe("README.mbt.md"))
  assert_true(path_is_lexically_safe("cmd/main/main.mbt"))
  assert_false(path_is_lexically_safe("/etc/passwd"))
  assert_false(path_is_lexically_safe("../README.mbt.md"))
  assert_false(path_is_lexically_safe("cmd/../README.mbt.md"))
}

///|
test "parse options enables debug and context window" {
  let (options, error) = parse_options([
    "--debug", "--context-window", "64000", "run", "hello",
  ])
  assert_true(error is None)
  assert_true(options is Some({ debug: true, context_window: Some(64000), .. }))
}

///|
test "command allowlist includes workflow-safe commands" {
  assert_true(command_allowed(["pwd"]))
  assert_true(command_allowed(["moon", "check", "--target", "native"]))
  assert_true(command_allowed(["moon", "info"]))
  assert_true(command_allowed(["moon", "fmt"]))
  assert_true(command_allowed(["git", "status", "--short"]))
  assert_true(command_allowed(["git", "diff"]))
  assert_true(command_allowed(["git", "ls-files"]))
  assert_false(command_allowed(["sh", "-c", "echo nope"]))
  assert_false(command_allowed(["rm", "-rf", "_build"]))
  assert_false(command_allowed(["cat", "../secret.txt"]))
  assert_false(command_allowed(["moon", "test", "--update"]))
}

///|
test "parse chat response with tool call and usage" {
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
      #|  ],
      #|  "usage": {
      #|    "prompt_tokens": 12,
      #|    "completion_tokens": 3,
      #|    "total_tokens": 15
      #|  }
      #|}
    ),
  )
  let result = parse_chat_response(response)
  assert_true(result.message.content is None)
  assert_true(
    result.message.tool_calls is [{ id: "call_1", name: "read_file", .. }],
  )
  assert_true(result.usage is Some({ prompt_tokens: 12, total_tokens: 15, .. }))
}

///|
fn test_stream_sink(out : StringBuilder) -> ModelStreamSink {
  {
    on_text_delta: async fn(text) {
      out.write_string(text)
      @async.sleep(0)
    },
    on_tool_status: async fn(_text) { @async.sleep(0) },
  }
}

///|
async test "parse chat stream text chunks and usage" {
  let out = StringBuilder::new()
  let sink = test_stream_sink(out)
  let state = ChatStreamState::new()
  assert_false(
    state.apply_sse_line(
      (
        #|data: {"choices":[{"delta":{"content":"Hello"}}],"usage":null}
      ),
      sink,
    ),
  )
  assert_false(
    state.apply_sse_line(
      (
        #|data: {"choices":[{"delta":{"content":" world"}}],"usage":null}
      ),
      sink,
    ),
  )
  assert_false(
    state.apply_sse_line(
      (
        #|data: {"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}
      ),
      sink,
    ),
  )
  assert_true(state.apply_sse_line("data: [DONE]", sink))
  let result = state.completion_result()
  assert_true(out.to_string() == "Hello world")
  assert_true(result.message.content is Some("Hello world"))
  assert_true(result.usage is Some({ prompt_tokens: 4, total_tokens: 6, .. }))
}

///|
async test "parse chat stream tool call argument chunks" {
  let out = StringBuilder::new()
  let sink = test_stream_sink(out)
  let state = ChatStreamState::new()
  ignore(
    state.apply_sse_line(
      (
        #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{"}}]}}],"usage":null}
      ),
      sink,
    ),
  )
  ignore(
    state.apply_sse_line(
      (
        #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"path\":\"README.mbt.md\"}"}}]}}],"usage":null}
      ),
      sink,
    ),
  )
  let result = state.completion_result()
  assert_true(result.message.content is None)
  assert_true(
    result.message.tool_calls
    is [
      {
        id: "call_1",
        name: "read_file",
        arguments: "{\"path\":\"README.mbt.md\"}",
      },
    ],
  )
  assert_true(out.to_string() == "")
}

///|
async test "parse chat stream ignores empty tool names" {
  let out = StringBuilder::new()
  let sink = test_stream_sink(out)
  let state = ChatStreamState::new()
  ignore(
    state.apply_sse_line(
      (
        #|data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_empty","type":"function","function":{"name":"","arguments":"{}"}}]}}],"usage":null}
      ),
      sink,
    ),
  )
  let result = state.completion_result()
  assert_true(result.message.tool_calls.is_empty())
  assert_true(result.message.content is Some(""))
  assert_true(out.to_string() == "")
}

///|
test "parse chat response ignores empty tool names" {
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
      #|            "id": "call_empty",
      #|            "type": "function",
      #|            "function": {
      #|              "name": "",
      #|              "arguments": "{}"
      #|            }
      #|          }
      #|        ]
      #|      }
      #|    }
      #|  ]
      #|}
    ),
  )
  let result = parse_chat_response(response)
  assert_true(result.message.tool_calls.is_empty())
}

///|
test "empty stream completion requires non-stream fallback" {
  assert_true(
    completion_needs_non_stream_fallback({
      message: Message::assistant(Some(""), []),
      usage: None,
    }),
  )
  assert_true(
    completion_needs_non_stream_fallback({
      message: Message::assistant(None, []),
      usage: None,
    }),
  )
  assert_false(
    completion_needs_non_stream_fallback({
      message: Message::assistant(Some("ok"), []),
      usage: None,
    }),
  )
  assert_false(
    completion_needs_non_stream_fallback({
      message: Message::assistant(None, [
        { id: "call_1", name: "read_file", arguments: "{}" },
      ]),
      usage: None,
    }),
  )
}

///|
struct FakeClient {
  mut calls : Int
}

///|
impl ModelClient for FakeClient with complete(self, _config, messages, _tools) {
  self.calls += 1
  if self.calls == 1 {
    {
      message: Message::assistant(None, [
        {
          id: "call_1",
          name: "read_file",
          arguments: "{\"path\":\"README.mbt.md\",\"max_lines\":1}",
        },
      ]),
      usage: Some({
        prompt_tokens: 1000,
        completion_tokens: 20,
        total_tokens: 1020,
      }),
    }
  } else {
    assert_true(messages.last() is Some({ role: "tool", content: Some(_), .. }))
    {
      message: Message::assistant(Some("done"), []),
      usage: Some({ prompt_tokens: 50, completion_tokens: 5, total_tokens: 55 }),
    }
  }
}

///|
fn restore_env_var(name : String, old_value : String?) -> Unit {
  match old_value {
    Some(value) => @env.set_env_var(name, value)
    None => @env.unset_env_var(name)
  }
}

///|
test "build config prefers deepmoon env vars and defaults" {
  let old_deepmoon_key = @env.get_env_var("deepmoon_key")
  let old_openai_key = @env.get_env_var("OPENAI_API_KEY")
  let old_deepmoon_api = @env.get_env_var("deepmoon_api")
  let old_openai_api = @env.get_env_var("OPENAI_BASE_URL")
  let old_model = @env.get_env_var("OPENAI_MODEL")
  @env.set_env_var("deepmoon_key", "deepmoon-secret")
  @env.set_env_var("OPENAI_API_KEY", "openai-secret")
  @env.set_env_var("deepmoon_api", "https://deepmoon.example/v1")
  @env.set_env_var("OPENAI_BASE_URL", "https://openai.example/v1")
  @env.set_env_var("OPENAI_MODEL", "demo-model")
  let (config, error) = build_config(CliOptions::new())
  restore_env_var("deepmoon_key", old_deepmoon_key)
  restore_env_var("OPENAI_API_KEY", old_openai_key)
  restore_env_var("deepmoon_api", old_deepmoon_api)
  restore_env_var("OPENAI_BASE_URL", old_openai_api)
  restore_env_var("OPENAI_MODEL", old_model)
  assert_true(error is None)
  assert_true(
    config
    is Some(
      {
        api_key: "deepmoon-secret",
        base_url: "https://deepmoon.example/v1",
        model: "demo-model",
        skills_dir: "skills",
        memory_dir: ".deepmoon/memory",
        context_window: 32000,
        ..,
      }
    ),
  )
}

///|
fn test_config(history_path~ : String?) -> AgentConfig {
  {
    api_key: "test-key",
    base_url: "http://127.0.0.1",
    model: "test-model",
    workspace: @env.current_dir().unwrap_or("."),
    history_path,
    skills_dir: "skills",
    memory_dir: "_build/deepmoon_memory_test",
    context_window: 32000,
    max_steps: 4,
    debug: false,
  }
}

///|
fn test_session() -> SessionState {
  SessionState::new(default_agent_base_prompt(), None, None, None)
}

///|
async test "agent loop executes tool call and returns final answer" {
  let fake : FakeClient = { calls: 0 }
  let session = test_session()
  session.history.push(Message::user("read readme"))
  let registry = build_tool_registry(
    test_config(history_path=None),
    session,
    fake,
  )
  let result = run_agent(
    test_config(history_path=None),
    fake,
    registry,
    session,
  )
  assert_true(result.final_text == "done")
  assert_true(fake.calls == 2)
  assert_true(result.messages.any(message => message.role == "tool"))
}

///|
struct StreamingFakeClient {
  mut calls : Int
}

///|
impl ModelClient for StreamingFakeClient with complete(
  self,
  _config,
  _messages,
  _tools,
) {
  self.calls += 1
  {
    message: Message::assistant(Some("fallback"), []),
    usage: Some({ prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }),
  }
}

///|
impl ModelClient for StreamingFakeClient with complete_stream(
  self,
  _config,
  _messages,
  _tools,
  sink,
) {
  self.calls += 1
  sink.text_delta("stream")
  sink.text_delta("ed")
  {
    message: Message::assistant(Some("streamed"), []),
    usage: Some({ prompt_tokens: 2, completion_tokens: 3, total_tokens: 5 }),
  }
}

///|
async test "agent stream emits deltas and records final message" {
  let fake : StreamingFakeClient = { calls: 0 }
  let session = test_session()
  session.history.push(Message::user("say hello"))
  let registry = build_tool_registry(
    test_config(history_path=None),
    session,
    fake,
  )
  let out = StringBuilder::new()
  let result = run_agent_stream(
    test_config(history_path=None),
    fake,
    registry,
    session,
    test_stream_sink(out),
  )
  assert_true(fake.calls == 1)
  assert_true(out.to_string() == "streamed")
  assert_true(result.final_text == "streamed")
  assert_true(result.messages.last() is Some({ content: Some("streamed"), .. }))
}

///|
test "repl input helper supports commands multiline and eof submit" {
  assert_true(
    repl_read_result_from_lines(["/exit"], eof=false) is ReplCommand("/exit"),
  )
  assert_true(
    repl_read_result_from_lines(["hello"], eof=false) is ReplMessage("hello"),
  )
  assert_true(
    repl_read_result_from_lines(["hello\\"], eof=false) is ReplNeedMore,
  )
  assert_true(
    repl_read_result_from_lines(["hello\\", "world", ""], eof=false)
    is ReplMessage("hello\nworld"),
  )
  assert_true(repl_read_result_from_lines([""], eof=false) is ReplNeedMore)
  assert_true(
    repl_read_result_from_lines(["draft"], eof=true) is ReplMessage("draft"),
  )
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

///|
async test "skills loader parses frontmatter and always flag" {
  let dir = @fs.tmpdir(prefix="deepmoon_skills_test")
  @fs.mkdir("\{dir}/demo-skill", recursive=true)
  @fs.write_file(
    "\{dir}/demo-skill/SKILL.md",
    (
      #|---
      #|name: demo-skill
      #|description: Demo skill
      #|always: true
      #|tags: demo,tests
      #|---
      #|Use this skill for demo tasks.
    ),
    create_mode=OpenOrCreate,
  )
  let loader = load_skills(dir)
  assert_true(
    loader.get("demo-skill") is Some({ meta: { always: true, .. }, .. }),
  )
  assert_true(loader.summary([]).contains("demo-skill"))
}

///|
async test "memory store resets unarchived messages after compact marker" {
  let dir = @fs.tmpdir(prefix="deepmoon_memory_store_test")
  let store = open_memory_store(dir)
  store.append_message(Message::user("old"))
  store.append_compact_marker()
  store.append_message(Message::assistant(Some("new"), []))
  let messages = store.load_unarchived_messages()
  assert_true(messages.length() == 1)
  assert_true(messages[0].content is Some("new"))
}

///|
async test "web fetch blocks local addresses" {
  let args = @json.parse("{\"url\":\"http://127.0.0.1:8000\"}")
  let result = web_fetch_tool(test_config(history_path=None), args)
  assert_true(result.contains("blocked local or private host"))
}

///|
test "update todos enforces single in progress item" {
  let session = test_session()
  let error = update_todos_tool(
    session,
    @json.parse(
      (
        #|{
        #|  "todos": [
        #|    {"id": 1, "content": "one", "status": "in_progress"},
        #|    {"id": 2, "content": "two", "status": "in_progress"}
        #|  ]
        #|}
      ),
    ),
  )
  assert_true(error.contains("only one todo"))
  let ok = update_todos_tool(
    session,
    @json.parse(
      (
        #|{
        #|  "todos": [
        #|    {"id": 1, "content": "one", "status": "completed"},
        #|    {"id": 2, "content": "two", "status": "in_progress"}
        #|  ]
        #|}
      ),
    ),
  )
  assert_true(ok.contains("todos updated"))
  assert_true(session.todos.length() == 2)
}
