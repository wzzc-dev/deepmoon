///|
pub struct HttpModelClient {}

///|
pub fn HttpModelClient::new() -> HttpModelClient {
  HttpModelClient::{  }
}

///|
fn strip_trailing_slashes(value : String) -> String {
  let mut current = value
  while current.has_suffix("/") {
    match current.strip_suffix("/") {
      Some(next) => current = next.to_owned()
      None => break
    }
  }
  current
}

///|
fn chat_completions_url(config : AgentConfig) -> String {
  "\{strip_trailing_slashes(config.base_url)}/chat/completions"
}

///|
pub impl ModelClient for HttpModelClient with complete(
  _self,
  config,
  messages,
  tools,
) {
  let request = build_chat_request(config.model, messages, tools).stringify()
  let headers : Map[String, String] = {
    "Authorization": "Bearer \{config.api_key}",
    "Content-Type": "application/json",
  }
  let (response, body) = @http.post(
    chat_completions_url(config),
    request,
    headers~,
  )
  let response_text = body.text()
  if config.debug {
    println("[http] POST /chat/completions -> \{response.code}")
    println(response_text)
  }
  guard response.code >= 200 && response.code < 300 else {
    fail(
      "chat completions request failed with HTTP \{response.code}: \{response_text}",
    )
  }
  let json = @json.parse(response_text)
  parse_chat_response(json)
}

///|
pub impl ModelClient for HttpModelClient with complete_stream(
  _self,
  config,
  messages,
  tools,
  sink,
) {
  let request = build_chat_request_with_stream(
    config.model,
    messages,
    tools,
    stream=true,
  ).stringify()
  let headers : Map[String, String] = {
    "Authorization": "Bearer \{config.api_key}",
    "Content-Type": "application/json",
  }
  let client = @http.post_stream(chat_completions_url(config), headers~)
  defer client.close()
  client.write(request)
  let response = client.end_request()
  if config.debug {
    println("[http] POST /chat/completions stream -> \{response.code}")
  }
  guard response.code >= 200 && response.code < 300 else {
    let response_text = client.read_all().text()
    fail(
      "chat completions stream request failed with HTTP \{response.code}: \{response_text}",
    )
  }
  let state = ChatStreamState::new()
  let mut done = false
  while !done {
    match client.read_until("\n") {
      None => break
      Some(line) => {
        if config.debug {
          let compact = line.trim().to_owned()
          if compact != "" {
            println("[http-stream] \{compact}")
          }
        }
        done = state.apply_sse_line(line, sink)
      }
    }
  }
  state.completion_result()
}
