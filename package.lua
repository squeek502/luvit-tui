return {
  name = "squeek502/tui",
  version = "0.0.1",
  description = "Naive implementation of a text-based UI using ANSI escape sequences",
  tags = { "tui", "textui" },
  license = "Unlicense",
  author = { name = "Ryan Liptak", url = "http://www.ryanliptak.com" },
  homepage = "https://github.com/squeek502/luvit-tui",
  dependencies = {
  	"luvit/luvit@2.6.0"
  },
  files = {
    "**.lua",
    "!test*"
  }
}
