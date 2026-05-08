///|
async fn main {
  @lib.cli_main() catch {
    err => println(err)
  }
}
