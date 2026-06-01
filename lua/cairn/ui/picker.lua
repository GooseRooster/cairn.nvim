-- cairn/ui/picker.lua
-- Orchestrates list, filter, and preview windows.
-- Owns all keymaps and the open/close lifecycle.

local M = {}

local win_mod = require("cairn.ui.window")
local list_mod = require("cairn.ui.list")
local flt_mod = require("cairn.ui.filter")
local prev_mod = require("cairn.ui.preview")
local marks = require("cairn.marks")

-- State -----------------------------------------------------------------------
-- Separated into two tables:
--   session  = persists across resize reopens (user context)
--   windows  = torn down and rebuilt on resize

local session = {
	config = nil,
	origin_win = nil, -- best real editing window to return to
	results = {}, -- filtered {mark, idx, score} list
	cursor = 1, -- 1-based row in results
	query = "", -- active filter query
}

local windows = {
	open = false,
	list_win = nil,
	filter_win = nil,
	prev_win = nil,
	list_buf = nil,
	filter_buf = nil,
	augroup = nil,
}

-- Origin window heuristic -----------------------------------------------------

--- Find the best real editing window to return focus to after close.
--- Skips floating windows, sidebars, and nofile/nowrite buffers.
--- Falls back to the current window if nothing better is found.
local function find_origin_win()
	local current = vim.api.nvim_get_current_win()
	local wins = vim.api.nvim_list_wins()

	local function is_real_editing_win(win)
		-- Skip floating windows (sidebars, popups, etc.)
		local cfg = vim.api.nvim_win_get_config(win)
		if cfg.relative and cfg.relative ~= "" then
			return false
		end

		local buf = vim.api.nvim_win_get_buf(win)
		local bt = vim.bo[buf].buftype

		-- Only normal buffers and help pages qualify
		return bt == "" or bt == "help"
	end

	-- Prefer the current window if it qualifies
	if is_real_editing_win(current) then
		return current
	end

	-- Otherwise walk the window list in reverse (most recently focused last)
	for i = #wins, 1, -1 do
		if is_real_editing_win(wins[i]) then
			return wins[i]
		end
	end

	return current -- last resort
end

-- Internal helpers ------------------------------------------------------------

local function is_open()
	return windows.open and windows.list_win and vim.api.nvim_win_is_valid(windows.list_win)
end

local function is_our_win(win)
	return win == windows.list_win or win == windows.filter_win or win == windows.prev_win
end

local function redraw_list()
	local lines, icon_data = list_mod.build_lines(session.results, session.config)
	list_mod.render(windows.list_buf, lines)
	list_mod.apply_highlights(windows.list_buf, session.results, icon_data)
	session.cursor = list_mod.clamp(session.cursor, session.results)
	list_mod.set_cursor(windows.list_win, session.cursor)
	list_mod.highlight_cursor(windows.list_buf, session.cursor, session.results)
end

local function update_preview()
	if not windows.prev_win then
		return
	end
	local r = session.results[session.cursor]
	if r then
		prev_mod.load(windows.prev_win, r.mark.file, r.mark.line)
	else
		prev_mod.clear(windows.prev_win)
	end
end

local function refresh(query)
	session.query = query or flt_mod.get_query()
	session.results = marks.filter(session.query)
	redraw_list()
	update_preview()
end

local function set_list_active(active)
	win_mod.set_win_active(windows.list_win, active)
	win_mod.set_win_active(windows.filter_win, not active)
end

-- Open a mark -----------------------------------------------------------------

local function open_mark(r, cmd)
	if not r then
		return
	end
	local origin = session.origin_win
	M.close()
	if origin and vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
	end
	vim.cmd((cmd or "edit") .. " " .. vim.fn.fnameescape(r.mark.file))
	vim.fn.cursor(r.mark.line, r.mark.col)
end

-- Keymaps ---------------------------------------------------------------------

local function map(buf, mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, {
		buffer = buf,
		nowait = true,
		silent = true,
		noremap = true,
		desc = "Cairn: " .. desc,
	})
end

local function setup_list_keymaps()
	local buf = windows.list_buf
	local km = session.config.ui.keymaps

	map(buf, "n", "j", function()
		if #session.results == 0 then
			return
		end
		session.cursor = list_mod.clamp(session.cursor + 1, session.results)
		list_mod.set_cursor(windows.list_win, session.cursor)
		list_mod.highlight_cursor(windows.list_buf, session.cursor, session.results)
		update_preview()
	end, "move down")

	map(buf, "n", "k", function()
		if #session.results == 0 then
			return
		end
		session.cursor = list_mod.clamp(session.cursor - 1, session.results)
		list_mod.set_cursor(windows.list_win, session.cursor)
		list_mod.highlight_cursor(windows.list_buf, session.cursor, session.results)
		update_preview()
	end, "move up")

	-- Open variants
	map(buf, "n", "<CR>", function()
		open_mark(session.results[session.cursor], "edit")
	end, "open mark")
	map(buf, "n", km.open_split, function()
		open_mark(session.results[session.cursor], "split")
	end, "open in horizontal split")
	map(buf, "n", km.open_vsplit, function()
		open_mark(session.results[session.cursor], "vsplit")
	end, "open in vertical split")
	map(buf, "n", km.open_tab, function()
		open_mark(session.results[session.cursor], "tabedit")
	end, "open in new tab")

	-- Delete
	map(buf, "n", "dd", function()
		local r = session.results[session.cursor]
		if not r then
			return
		end
		marks.remove_index(r.idx)
		refresh()
	end, "delete mark")

	map(buf, "n", km.delete, function()
		local r = session.results[session.cursor]
		if not r then
			return
		end
		marks.remove_index(r.idx)
		refresh()
	end, "delete mark")

	-- Reorder — cursor follows immediately, no async race
	map(buf, "n", km.move_down, function()
		local r = session.results[session.cursor]
		if not r then
			return
		end
		local all = marks.load()
		local j = r.idx + 1
		if j > #all then
			return
		end
		marks.reorder(r.idx, j)
		session.cursor = session.cursor + 1
		refresh()
	end, "move mark down")

	map(buf, "n", km.move_up, function()
		local r = session.results[session.cursor]
		if not r then
			return
		end
		local j = r.idx - 1
		if j < 1 then
			return
		end
		marks.reorder(r.idx, j)
		session.cursor = session.cursor - 1
		refresh()
	end, "move mark up")

	-- Enter filter
	local function enter_filter()
		set_list_active(false)
		flt_mod.activate(windows.filter_win, function(query)
			session.cursor = 1
			refresh(query)
		end)
	end
	map(buf, "n", "/", enter_filter, "enter filter")
	map(buf, "n", "i", enter_filter, "enter filter")

	-- Close
	map(buf, "n", "q", M.close, "close")
	map(buf, "n", "<Esc>", M.close, "close")
end

local function setup_filter_keymaps()
	local buf = windows.filter_buf
	local km = session.config.ui.keymaps

	map(buf, "i", "<Esc>", function()
		flt_mod.deactivate()
		set_list_active(true)
		vim.api.nvim_set_current_win(windows.list_win)
	end, "back to list")

	map(buf, "i", "<CR>", function()
		local r = session.results[session.cursor]
		flt_mod.deactivate()
		open_mark(r, "edit")
	end, "open best match")

	map(buf, "i", "<C-j>", function()
		if #session.results == 0 then
			return
		end
		session.cursor = list_mod.clamp(session.cursor + 1, session.results)
		list_mod.set_cursor(windows.list_win, session.cursor)
		list_mod.highlight_cursor(windows.list_buf, session.cursor, session.results)
		update_preview()
	end, "move list down from filter")

	map(buf, "i", "<C-k>", function()
		if #session.results == 0 then
			return
		end
		session.cursor = list_mod.clamp(session.cursor - 1, session.results)
		list_mod.set_cursor(windows.list_win, session.cursor)
		list_mod.highlight_cursor(windows.list_buf, session.cursor, session.results)
		update_preview()
	end, "move list up from filter")

	map(buf, "i", km.open_split, function()
		local r = session.results[session.cursor]
		flt_mod.deactivate()
		open_mark(r, "split")
	end, "open split from filter")

	map(buf, "i", km.open_vsplit, function()
		local r = session.results[session.cursor]
		flt_mod.deactivate()
		open_mark(r, "vsplit")
	end, "open vsplit from filter")
end

-- Window creation (separated from state init) ---------------------------------

local function create_windows(layout)
	windows.list_buf = list_mod.create_buf()
	windows.filter_buf = flt_mod.create_buf()

	windows.list_win = win_mod.open_win(
		windows.list_buf,
		vim.tbl_extend("force", layout.list, { title = "Cairn", focusable = true }),
		true
	)

	windows.filter_win = win_mod.open_win(
		windows.filter_buf,
		vim.tbl_extend("force", layout.filter, { title = nil, focusable = true }),
		false
	)

	if layout.show_preview then
		local prev_buf = vim.api.nvim_create_buf(false, true)
		windows.prev_win = win_mod.open_win(
			prev_buf,
			vim.tbl_extend("force", layout.preview, { title = "Preview", focusable = false }),
			false
		)
	else
		windows.prev_win = nil
	end
end

local function destroy_windows()
	flt_mod.deactivate()
	win_mod.close_win(windows.list_win)
	win_mod.close_win(windows.filter_win)
	win_mod.close_win(windows.prev_win)
	windows.list_win = nil
	windows.filter_win = nil
	windows.prev_win = nil
	windows.list_buf = nil
	windows.filter_buf = nil
end

local function register_autocmds()
	windows.augroup = vim.api.nvim_create_augroup("cairn_picker", { clear = true })

	vim.api.nvim_create_autocmd("WinLeave", {
		group = windows.augroup,
		callback = function()
			vim.schedule(function()
				if not windows.open then
					return
				end
				if not is_our_win(vim.api.nvim_get_current_win()) then
					M.close()
				end
			end)
		end,
	})

	-- On resize: reopen in place preserving full session state
	vim.api.nvim_create_autocmd("VimResized", {
		group = windows.augroup,
		callback = function()
			if not windows.open then
				return
			end
			vim.schedule(M._reopen)
		end,
	})
end

-- Lifecycle -------------------------------------------------------------------

--- Fresh open: resets all session state.
function M.open(config)
	if is_open() then
		return
	end

	session.config = config
	session.origin_win = find_origin_win()
	session.cursor = 1
	session.query = ""
	session.results = marks.filter("")

	win_mod.setup_highlights()
	prev_mod.setup_highlights()

	local layout = win_mod.calculate_layout(config)
	if not layout then
		vim.notify("cairn: terminal too small to open picker", vim.log.levels.WARN)
		return
	end

	create_windows(layout)
	setup_list_keymaps()
	setup_filter_keymaps()
	register_autocmds()

	windows.open = true

	vim.api.nvim_set_current_win(windows.list_win)
	redraw_list()
	update_preview()
end

--- Reopen after resize: preserves session state (cursor, query, results).
function M._reopen()
	if not windows.open then
		return
	end

	-- Tear down windows only — session survives
	if windows.augroup then
		pcall(vim.api.nvim_del_augroup_by_name, "cairn_picker")
		windows.augroup = nil
	end
	destroy_windows()
	windows.open = false

	-- Recalculate layout for new terminal dimensions
	local layout = win_mod.calculate_layout(session.config)
	if not layout then
		-- Terminal too small even after resize — just stay closed
		return
	end

	create_windows(layout)
	setup_list_keymaps()
	setup_filter_keymaps()
	register_autocmds()

	windows.open = true

	-- Restore filter state if a query was active
	if session.query ~= "" then
		flt_mod.reset(true)
		-- Re-run filter so results match stored query
		session.results = marks.filter(session.query)
	end

	vim.api.nvim_set_current_win(windows.list_win)
	redraw_list()
	update_preview()
end

--- Full close: tears down windows and clears session.
function M.close()
	if not windows.open then
		return
	end
	windows.open = false

	if windows.augroup then
		pcall(vim.api.nvim_del_augroup_by_name, "cairn_picker")
		windows.augroup = nil
	end

	destroy_windows()
	flt_mod.reset(false)

	-- Clear session
	local origin = session.origin_win
	session.origin_win = nil
	session.results = {}
	session.cursor = 1
	session.query = ""

	-- Return focus to the real editing window
	if origin and vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
	end
end

function M.is_open()
	return is_open()
end

return M
