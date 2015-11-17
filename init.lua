local TUI = require('./tui')

local tui

tui = TUI:new(5, function(err, line)
	if err then
		process:exit()
	else
		tui:editorOutput(line)
	end
end)
