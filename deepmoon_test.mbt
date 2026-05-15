///|
test "default subagents expose workflow roles" {
  let specs = @deepmoon.default_subagent_specs()
  assert_true(specs.length() == 5)
  assert_true(specs.any(spec => spec.name == "editor"))
  assert_true(specs.any(spec => spec.name == "researcher"))
}

///|
test "default agent prompt mentions skills and subagents" {
  let prompt = @deepmoon.default_agent_base_prompt()
  assert_true(prompt.contains("load_skill"))
  assert_true(prompt.contains("dispatch_subagent"))
}
