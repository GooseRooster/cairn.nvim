-- cairn/ui/filter.lua
-- The single-line filter bar buffer.

local M = {}

local win_mod = require("cairn.ui.window")

-- State -----------------------------------------------------------------------

local _state = {
	buf = nil,
	win = nil,
	active = false,
	query = "",
	on_change = nil, -- function(query) called on every keystroke
}

-- Prefix display --------------------------------------------------------------

local INACTIVE_PREFIX = "  / "
local ACTIVE_PREFIX = "  / > "

local function set_prefix(active)
	if not vim.api.nvim_buf_is_valid(_state.buf) then
		return
	end
	vim.bo[_state.buf].modifiable = true
	local prefix = active and ACTIVE_PREFIX or INACTIVE_PREFIX
	-- Only update prefix if query is empty; otherwise rebuild full line
	local current = vim.api.nvim_buf_get_lines(_state.buf, 0, 1, false)[1] or ""
	local _, query = current:match("^(%s+/[>%s]*)(.*)$")
	local new_line = prefix .. (query or "")
	vim.api.nvim_buf_set_lines(_state.buf, 0, -1, false, { new_line })
	vim.bo[_state.buf].modifiable = false

	-- Highlight the prefix
	local ns = vim.api.nvim_create_namespace("cairn_filter")
	vim.api.nvim_buf_clear_namespace(_state.buf, ns, 0, -1)
	vim.hl.range(_state.buf, ns, win_mod.HL.filter_prefix, { 0, 0 }, { 0, #prefix })
end

-- Query extraction ------------------------------------------------------------

local function extract_query(line, active)
	local prefix = active and ACTIVE_PREFIX or INACTIVE_PREFIX
	if line:sub(1, #prefix) == prefix then
		return line:sub(#prefix + 1)
	end
	-- fallback: anything after the first > or /
	return line:match("[/>]%s*(.*)$") or ""
end

-- Buffer setup ----------------------------------------------------------------

function M.create_buf()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].swapfile = false
	-- Start with inactive prefix
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { INACTIVE_PREFIX })
	vim.bo[buf].modifiable = false
	_state.buf = buf
	return buf
end

-- Activation ------------------------------------------------------------------

--- Enter insert/active mode: make buffer writable, move cursor to end.
function M.activate(win, on_change)
	_state.win = win
	_state.active = true
	_state.on_change = on_change
	set_prefix(true)

	-- Focus the filter window and enter insert mode at end of line
	vim.api.nvim_set_current_win(win)
	vim.bo[_state.buf].modifiable = true

	-- Place cursor after prefix
	local line = vim.api.nvim_buf_get_lines(_state.buf, 0, 1, false)[1] or ""
	vim.api.nvim_win_set_cursor(win, { 1, #line })
	vim.cmd("startinsert!")

	-- Watch for changes via TextChangedI
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = _state.buf,
		group = vim.api.nvim_create_augroup("cairn_filter_change", { clear = true }),
		callback = function()
			local current = vim.api.nvim_buf_get_lines(_state.buf, 0, 1, false)[1] or ""
			-- Guard prefix: don't let the user delete it
			if #current < #ACTIVE_PREFIX then
				vim.api.nvim_buf_set_lines(_state.buf, 0, -1, false, { ACTIVE_PREFIX .. _state.query })
				local l = vim.api.nvim_buf_get_lines(_state.buf, 0, 1, false)[1]
				vim.api.nvim_win_set_cursor(win, { 1, #l })
				return
			end
			local q = extract_query(current, true)
			_state.query = q
			if _state.on_change then
				_state.on_change(q)
			end
			-- Re-apply prefix highlight since text changed
			local ns = vim.api.nvim_create_namespace("cairn_filter")
			vim.api.nvim_buf_clear_namespace(_state.buf, ns, 0, -1)
			vim.hl.range(_state.buf, ns, win_mod.HL.filter_prefix, { 0, 0 }, { 0, #ACTIVE_PREFIX })
		end,
	})
end

--- Leave insert/active mode: lock buffer, revert prefix.
function M.deactivate()
	_state.active = false
	vim.cmd("stopinsert")
	vim.bo[_state.buf].modifiable = false
	-- Clear the autocmd
	pcall(vim.api.nvim_del_augroup_by_name, "cairn_filter_change")
	set_prefix(false)
end

--- Get the current query string.
function M.get_query()
	return _state.query
end

--- Reset query to empty.
function M.reset(clear_display)
	_state.query = ""
	if clear_display and vim.api.nvim_buf_is_valid(_state.buf) then
		vim.bo[_state.buf].modifiable = true
		vim.api.nvim_buf_set_lines(_state.buf, 0, -1, false, { (_state.active and ACTIVE_PREFIX or INACTIVE_PREFIX) })
		vim.bo[_state.buf].modifiable = false
	end
end

return M
