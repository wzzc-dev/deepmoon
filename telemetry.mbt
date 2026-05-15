///|
pub(all) struct TokenTracker {
  log_path : String
  mut last_prompt_tokens : Int
}

///|
pub async fn open_token_tracker(log_path : String) -> TokenTracker {
  let dir = parent_dir(log_path)
  if dir != "." && !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
  if !@fs.exists(log_path) {
    @fs.write_file(log_path, "", create_mode=OpenOrCreate)
  }
  { log_path, last_prompt_tokens: 0 }
}

///|
pub async fn TokenTracker::record(
  self : TokenTracker,
  model : String,
  usage : TokenUsage,
) -> Unit {
  self.last_prompt_tokens = usage.prompt_tokens
  let row = Json::object({
    "ts": Json::string(@env.now().to_string()),
    "model": Json::string(model),
    "prompt_tokens": Json::number(
      usage.prompt_tokens.to_double(),
      repr=usage.prompt_tokens.to_string(),
    ),
    "completion_tokens": Json::number(
      usage.completion_tokens.to_double(),
      repr=usage.completion_tokens.to_string(),
    ),
    "total_tokens": Json::number(
      usage.total_tokens.to_double(),
      repr=usage.total_tokens.to_string(),
    ),
  })
  @fs.write_file(
    self.log_path,
    row.stringify() + "\n",
    create_mode=OpenOrCreate,
    append=true,
  )
}

///|
pub fn TokenTracker::should_compact(
  self : TokenTracker,
  context_window : Int,
) -> Bool {
  self.last_prompt_tokens > context_window * 7 / 10
}
