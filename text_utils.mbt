///|
pub fn ascii_lower(text : String) -> String {
  let out = StringBuilder::new()
  for ch in text {
    out.write_char(ch.to_ascii_lowercase())
  }
  out.to_string()
}

///|
pub fn strip_wrapping_quotes(text : String) -> String {
  let trimmed = text.trim().to_owned()
  if trimmed.length() >= 2 &&
    (
      (trimmed.has_prefix("\"") && trimmed.has_suffix("\"")) ||
      (trimmed.has_prefix("'") && trimmed.has_suffix("'"))
    ) {
    trimmed[1:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
}

///|
pub fn summarize_text(text : String, limit : Int) -> String {
  if text.length() <= limit {
    text
  } else {
    text[:limit].to_owned() + "..."
  }
}
