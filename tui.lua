local Object = require('core').Object
local readline = require('readline')
local prettyprint = require('pretty-print')

local TUI = Object:extend()
local Line = Object:extend()
local StaticEditor = Line:extend()

local CSI = '\027['
local ESC = {
	MOVE_CURSOR_TO = 'H', -- y ; x
	ERASE_FROM_CURSOR_TO_EOS = 'J',
	ERASE_FROM_BOS_TO_CURSOR = {'J', 1},
	ERASE_SCREEN = {'J', 2},
	ERASE_FROM_CURSOR_TO_EOL = 'K',
	ERASE_FROM_BOL_TO_CURSOR = {'K', 1},
	ERASE_LINE = {'K', 2},
	ERASE_CHAR = 'X',
}

local function buildControlSequence(char, ...)
	local numArgs = {...}
	if type(char) == "table" then
		local realChar = char[1]
		for i=2,#char do
			table.insert(numArgs, i-1, char[i])
		end
		char = realChar
	end
	assert(string.byte(char, 1) >= 64 and string.byte(char, 1) <= 126, "Control sequence final character must be between @ and ~ (received " .. tostring(char) .. ")")
	return CSI .. table.concat(numArgs, ';') .. char
end

function Line:initialize(y, startX)
	self.line = ""
	self.y = y or 1
	self.startX = 0
	self.position = startX
end

function Line:getPosition()
	return self:relativePosition(self.position)
end

function Line:relativePosition(offset)
	return self.startX + offset
end

function Line:setTo(text)
	self.line = text
	return buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, self:relativePosition(1)) .. buildControlSequence(ESC.ERASE_FROM_CURSOR_TO_EOL) .. text
end

function Line:append(text)
	local lineLength = #self.line
	self.line = self.line .. text
	return buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, self:relativePosition(lineLength+1)) .. text
end

function Line:insertAt(text, x)
	if not x then x = 1 end
	local newEnd = text .. string.sub(self.line, x)
	self.line = string.sub(self.line, 1, x - 1) .. newEnd
	return buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, self:relativePosition(x)) .. newEnd
end

function Line:deleteAt(x, numToDelete)
	if not numToDelete then numToDelete = 1 end
	local newEnd = string.sub(self.line, x + numToDelete)
	self.line = string.sub(self.line, 1, x-1) .. newEnd
	return buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, self:relativePosition(x)) .. buildControlSequence(ESC.ERASE_FROM_CURSOR_TO_EOL) .. newEnd
end

function Line:backspaceAt(x, numToDelete)
	if not numToDelete then numToDelete = 1 end
	return self:deleteAt(math.max(0, x - numToDelete), numToDelete)
end

function Line:deleteFromToEnd(xStart)
	self.line = string.sub(self.line, 1, xStart - 1)
	return buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, self:relativePosition(xStart)) .. buildControlSequence(ESC.ERASE_FROM_CURSOR_TO_EOL)
end

function Line:prepend(text)
	return self:insertAt(text, 1)
end

function Line:clear()
	return self:setTo("")
end

function Line:goTo()
	return buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, self:getPosition())
end

function StaticEditor:refreshLine()
	local command = self:setTo(self.line)
	if self.prompt then
		command = buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, 0) .. self.prompt .. command
	end
	command = command .. self:goTo()
	self.stdout:write(command)
end

function StaticEditor:refreshCursor()
	local command = self:goTo()
	self.stdout:write(command)
end

function StaticEditor:goTo()
	return buildControlSequence(ESC.MOVE_CURSOR_TO, self.y, self:getPosition())
end

function StaticEditor:insertAbove(line)
	self:output(line)
end

function StaticEditor:insert(text)
	local line = self.line
	local position = self.position
	self.position = position + #text
	if #line == position - 1 then
		if self.promptLength + #self.line < self.columns then
			local command = self:insertAt(text, position)
			self.stdout:write(command)
		else
			self:refreshLine()
		end
	else
		local command = self:insertAt(text, position) .. self:goTo()
		self.stdout:write(command)
	end
	self.history:updateLastLine(self.line)
end

function StaticEditor:moveLeft()
	if self.position > 1 then
		self.position = self.position - 1
		self:refreshCursor()
	end
end

function StaticEditor:moveRight()
	if self.position - 1 ~= #self.line then
		self.position = self.position + 1
		self:refreshCursor()
	end
end

function StaticEditor:getHistory(delta)
	local history = self.history
	local length = #history
	local index = self.historyIndex
	if length > 1 then
		index = index + delta
		if index < 1 then
			index = 1
		elseif index > length then
			index = length
		end
		if index == self.historyIndex then return end
		local line = self.history[index]
		self.line = line
		self.historyIndex = index
		self.position = #line + 1
		self:refreshLine()
	end
end

function StaticEditor:backspace()
	local line = self.line
	local position = self.position
	if position > 1 and #line > 0 then
		self.position = position - 1
		local command = self:backspaceAt(position) .. self:goTo()
		self.history:updateLastLine(self.line)
		self.stdout:write(command)
	end
end

function StaticEditor:delete()
	local line = self.line
	local position = self.position
	if position > 0 and #line > 0 then
		local command = self:deleteAt(position) .. self:goTo()
		self.history:updateLastLine(self.line)
		self.stdout:write(command)
	end
end

function StaticEditor:swap()
	local line = self.line
	local position = self.position
	if position > 1 then
		position = math.min(#line, position)
		self.line = string.sub(line, 1, position - 2)
						 .. string.sub(line, position, position)
						 .. string.sub(line, position - 1, position - 1)
						 .. string.sub(line, position + 1)
		if position <= #line then
			self.position = position + 1
		end
		self.history:updateLastLine(self.line)
		self:refreshLine()
	end
end

function StaticEditor:deleteLine()
	self.line = ''
	self.position = 1
	self.history:updateLastLine(self.line)
	self:refreshLine()
end

function StaticEditor:deleteEnd()
	local command = self:deleteFromToEnd(self.position)
	self.history:updateLastLine(self.line)
	self.stdout:write(command)
end

function StaticEditor:moveHome()
	self.position = 1
	self:refreshCursor()
end

function StaticEditor:moveEnd()
	self.position = #self.line + 1
	self:refreshCursor()
end

function StaticEditor.findLeft(line, position, wordPattern)
	local pattern = wordPattern .. "$"
	if position == 1 then return 1 end
	local s
	repeat
		local start = string.sub(line, 1, position - 1)
		s = string.find(start, pattern)
		if not s then
			position = position - 1
		end
	until s or position == 1
	return s or position
end

function StaticEditor:deleteWord()
	local wordEnd = self.position
	local wordStart = self.findLeft(self.line, wordEnd, self.wordPattern)
	local wordLength = wordEnd - wordStart
	self.position = self.position - wordLength
	local command = self:deleteAt(wordStart, wordLength) .. self:goTo()
	self.stdout:write(command)
end

function StaticEditor:jumpLeft()
	self.position = self.findLeft(self.line, self.position, self.wordPattern)
	self:refreshCursor()
end

function StaticEditor:jumpRight()
	local _, e = string.find(self.line, self.wordPattern, self.position)
	self.position = e and e + 1 or #self.line + 1
	self:refreshCursor()
end

function StaticEditor:clearScreen()
	self.stdout:write(buildControlSequence(ESC.ERASE_SCREEN))
	self:refreshLine()
end

function StaticEditor:beep()
	self.stdout:write('\x07')
end

function StaticEditor:complete()
	if not self.completionCallback then
		return self:beep()
	end
	local line = self.line
	local position = self.position
	local res = self.completionCallback(string.sub(line, 1, position))
	if not res then
		return self:beep()
	end
	local typ = type(res)
	if typ == "string" then
		self.line = res .. string.sub(line, position + 1)
		self.position = #res + 1
		self.history:updateLastLine(self.line)
	elseif typ == "table" then
		print()
		print(unpack(res))
	end
	self:refreshLine()
end

function StaticEditor.escapeKeysForDisplay(keys)
	return string.gsub(keys, '[%c\\\128-\255]', function(c)
		local b = string.byte(c, 1)
		if b < 10 then return '\\00' .. b end
		if b <= 31 then return '\\0' .. b end
		if b == 92 then return '\\\\' end
		if b >= 128 and b <= 255 then return '\\' .. b end
	end)
end

-- an array of tables so that the iteration order is consistent
-- each entry is an array with two entries: a table and a function
-- the table can contain any number of the following:
--   numbers (to be compared to the char value),
--   strings (to be compared to the input string that has been truncated to the same length),
--   functions (to be called with the (key, char) values and returns either the consumed keys or nil)
-- the function recieves the Editor instance as the first parameter and the consumedKeys as the second
--   its returns will be propagated to Editor:onKey if either of them are non-nil
--   note: the function is only called if the key handler is the one doing the consuming
StaticEditor.keyHandlers =
{
	-- Enter
	{{13}, function(self)
		local history = self.history
		local line = self.line
		-- Only record new history if it's non-empty and new
		if #line > 0 and history[#history - 1] ~= line then
			history[#history] = line
		else
			history[#history] = nil
		end
		return self.line
	end},
	-- Tab
	{{9}, function(self)
		self:complete()
	end},
	-- Control-C
	{{3}, function(self)
		if #self.line > 0 then
			self:deleteLine()
		else
			return false, "SIGINT in readLine"
		end
	end},
	-- Backspace, Control-H
	{{127, 8}, function(self)
		self:backspace()
	end},
	-- Control-D
	{{4}, function(self)
		if #self.line > 0 then
			self:delete()
		else
			self.history:updateLastLine()
			return nil, "EOF in readLine"
		end
	end},
	-- Control-T
	{{20}, function(self)
		self:swap()
	end},
	-- Up Arrow, Control-P
	{{'\027[A', 16}, function(self)
		self:getHistory(-1)
	end},
	-- Down Arrow, Control-N
	{{'\027[B', 14}, function(self)
		self:getHistory(1)
	end},
	-- Right Arrow, Control-F
	{{'\027[C', 6}, function(self)
		self:moveRight()
	end},
	-- Left Arrow, Control-B
	{{'\027[D', 2}, function(self)
		self:moveLeft()
	end},
	-- Home Key, Home for terminator, Home for CMD.EXE, Control-A
	{{'\027[H', '\027OH', '\027[1~', 1}, function(self)
		self:moveHome()
	end},
	-- End Key, End for terminator, End for CMD.EXE, Control-E
	{{'\027[F', '\027OF', '\027[4~', 5}, function(self)
		self:moveEnd()
	end},
	-- Control-U
	{{21}, function(self)
		self:deleteLine()
	end},
	-- Control-K
	{{11}, function(self)
		self:deleteEnd()
	end},
	-- Control-L
	{{12}, function(self)
		self:clearScreen()
	end},
	-- Control-W
	{{23}, function(self)
		self:deleteWord()
	end},
	-- Delete Key
	{{'\027[3~'}, function(self)
		self:delete()
	end},
	-- Control Left Arrow, Alt Left Arrow (iTerm.app), Alt Left Arrow (Terminal.app)
	{{'\027[1;5D', '\027\027[D', '\027b'}, function(self)
		self:jumpLeft()
	end},
	-- Control Right Arrow, Alt Right Arrow (iTerm.app), Alt Right Arrow (Terminal.app)
	{{'\027[1;5C', '\027\027[C', '\027f'}, function(self)
		self:jumpRight()
	end},
	-- Alt Up Arrow (iTerm.app), Page Up
	{{'\027\027[A', '\027[5~'}, function(self)
		self:getHistory(-10)
	end},
	-- Alt Down Arrow (iTerm.app), Page Down
	{{'\027\027[B', '\027[6~'}, function(self)
		self:getHistory(10)
	end},
	-- Printable characters
	{{function(key, char) return char > 31 and key:sub(1,1) or nil end}, function(self, consumedKeys)
		self:insert(consumedKeys)
	end},
}

function StaticEditor:onKey(key)
	local char = string.byte(key, 1)
	local consumedKeys = nil

	for _, keyHandler in ipairs(self.keyHandlers) do
		local handledKeys = keyHandler[1]
		local handlerFn = keyHandler[2]
		for _, handledKey in ipairs(handledKeys) do
			if type(handledKey) == "number" then
				consumedKeys = handledKey == char and key:sub(1,1) or nil
			elseif type(handledKey) == "string" then
				-- test against the first key using the same strlen as the handled key
				local testKey = (type(handledKey) == "string" and #key >= #handledKey) and key:sub(1,#handledKey) or nil
				consumedKeys = (testKey and testKey == handledKey) and testKey or nil
			elseif type(handledKey) == "function" then
				consumedKeys = handledKey(key, char)
			end
			if consumedKeys ~= nil then
				local ret, err = handlerFn(self, consumedKeys)
				if err ~= nil or ret ~= nil then
					return ret, err
				end
				break
			end
		end
		if consumedKeys ~= nil then break end
	end

	if consumedKeys ~= nil then
		assert(#consumedKeys > 0)
		if #consumedKeys < #key then
			local unconsumedKeys = key:sub(#consumedKeys+1)
			if #unconsumedKeys > 0 then
				self:onKey(unconsumedKeys)
			end
		end
	else
		self:insertAbove(string.format("Unhandled key(s): %s", self.escapeKeysForDisplay(key)))
	end
	return true
end

function StaticEditor:readLine(prompt, callback)
	local onKey, finish

	self.prompt = prompt
	self.promptLength = #prompt
	self.startX = self.promptLength
	self.columns = self.stdout.get_winsize and self.stdout:get_winsize() or 80

	function onKey(err, key)
		local r, out, reason = pcall(function ()
			assert(not err, err)
			return self:onKey(key)
		end)
		if r then
			if out == true then return end
			return finish(nil, out, reason)
		else
			return finish(out)
		end
	end

	function finish(...)
		self.stdin:read_stop()
		self.stdin:set_mode(0)
		return callback(...)
	end

	self.line = ""
	self.position = 1
	self:refreshLine()
	self.history:add(self.line)
	self.historyIndex = #self.history

	self.stdin:set_mode(1)
	self.stdin:read_start(onKey)
end

function StaticEditor:initialize(options)
	self.meta.super.initialize(self)
	options = options or {}
	assert(options.stdin, "stdin is required")
	assert(options.stdout, "stdout is required")
	self.wordPattern = options.wordPattern or "%w+"
	self.history = options.history or readline.History.new()
	self.completionCallback = options.completionCallback
	self.stdin = options.stdin
	self.stdout = options.stdout
end

function StaticEditor:output(...)
	if self.outputLine then
		local args = {...}
		for k,v in ipairs(args) do
			args[k] = tostring(v)
		end
		self.stdout:write(self.outputLine:setTo(table.concat(args, "\t")))
	end
end

function StaticEditor:outputAppend(...)
	if self.outputLine then
		local args = {...}
		for k,v in ipairs(args) do
			args[k] = tostring(v)
		end
		self.stdout:write(self.outputLine:append(table.concat(args, "\t")))
	end
end

function TUI:initialize(numLines, onLine, options)
	if not options then options = {} end
	self.numLines = numLines
	self.writeQueue = {}
	self.readyToWrite = true
	self.stdout = options.stdout or prettyprint.stdout
	self.stdin = options.stdin or prettyprint.stdin
	self.editor = StaticEditor:new({stdout = self, stdin = self.stdin})
	self.editor.y = numLines + 2
	self.prompt = options.prompt or "> "
	self.lines = {}
	for i=1,numLines do
		local line = Line:new(i)
		self.stdout:write('\n')
		table.insert(self.lines, line)
	end
	self.editorOutputLine = Line:new(numLines + 1)
	self.stdout:write('\n')
	self.editor.outputLine = self.editorOutputLine
	local function onReadLine(err, line, ...)
		if line then
			if onLine(nil, line) ~= false then
				self.editor:readLine(self.prompt, onReadLine)
			end
		else
			if err ~= nil then
				onLine(err, ...)
			else
				onLine(...)
			end
		end
	end
	self.editor:readLine(self.prompt, onReadLine)
	self.masterLine = self.editor
end

function TUI:getLine(lineNum)
	return self.lines[lineNum]
end

function TUI:setLine(lineNum, text)
	local targetLine = self:getLine(lineNum)
	local command = targetLine:setTo(text)
	self:doAndReturn(command)
end

function TUI:appendLine(lineNum, text)
	local targetLine = self:getLine(lineNum)
	local command = targetLine:append(text)
	self:doAndReturn(command)
end

function TUI:editorOutput(text)
	self.editor:output(text)
end

function TUI:editorOutputAppend(text)
	self.editor:outputAppend(text)
end

function TUI:doAndReturn(command)
	local previousLine = self.masterLine
	self:write(command .. previousLine:goTo())
end

function TUI:_write(text)
	self.stdout:write(text, function()
		self.readyToWrite = true
		self:write()
	end)
	self.readyToWrite = false
end

function TUI:write(text)
	if not text then text = '' end
	if self.readyToWrite then
		self:_write(self:flushWriteQueue() .. text)
	else
		table.insert(self.writeQueue, text)
	end
end

function TUI:flushWriteQueue()
	local fullText = table.concat(self.writeQueue)
	self.writeQueue = {}
	return fullText
end

function TUI:get_winsize()
	return self.stdout.get_winsize and self.stdout:get_winsize() or 80
end

TUI.Line = Line
TUI.buildControlSequence = buildControlSequence
TUI.CSI = CSI
TUI.ESC = ESC

return TUI
