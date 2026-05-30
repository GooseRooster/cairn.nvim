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

local state = {
	open = false,
	-- window ids
	list_win = nil,
	filter_win = nil,
	prev_win = nil,
	-- buffer ids
	list_buf = nil,
	filter_buf = nil,
	-- current data
	results = {}, -- filtered {mark, idx, score} list
	cursor = 1, -- 1-based row in results
	-- config ref
	config = nil,
	-- augroup for cleanup
	augroup = nil,
}

-- Internal helpers ------------------------------------------------------------

local function is_open()
	return state.open and state.list_win and vim.api.nvim_win_is_valid(state.list_win)
end

local function redraw_list()
	local lines = list_mod.build_lines(state.results)
	list_mod.render(state.list_buf, lines)
	list_mod.apply_highlights(state.list_buf, state.results)
	-- Clamp and reapply cursor
	state.cursor = list_mod.clamp(state.cursor, state.results)
	list_mod.set_cursor(state.list_win, state.cursor)
	list_mod.highlight_cursor(state.list_buf, state.cursor, state.results)
end

local function update_preview()
	if not state.prev_win then
		return
	end
	local r = state.results[state.cursor]
	if r then
		prev_mod.load(state.prev_win, r.mark.file, r.mark.line)
	else
		prev_mod.clear(state.prev_win)
	end
end

local function refresh(query)
	state.results = marks.filter(query or flt_mod.get_query())
	redraw_list()
	update_preview()
end

local function set_list_active(active)
	win_mod.set_win_active(state.list_win, active)
	win_mod.set_win_active(state.filter_win, not active)
end

-- Open a mark -----------------------------------------------------------------

local function open_mark(r, cmd)
	if not r then
		return
	end
	M.close()
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
	local buf = state.list_buf
	local km = state.config.ui.keymaps

	-- Navigation
	map(buf, "n", "j", function()
		if #state.results == 0 then
			return
		end
		state.cursor = list_mod.clamp(state.cursor + 1, state.results)
		list_mod.set_cursor(state.list_win, state.cursor)
		list_mod.highlight_cursor(state.list_buf, state.cursor, state.results)
		update_preview()
	end, "move down")

	map(buf, "n", "k", function()
		if #state.results == 0 then
			return
		end
		state.cursor = list_mod.clamp(state.cursor - 1, state.results)
		list_mod.set_cursor(state.list_win, state.cursor)
		list_mod.highlight_cursor(state.list_buf, state.cursor, state.results)
		update_preview()
	end, "move up")

	-- Open variants
	map(buf, "n", "<CR>", function()
		open_mark(state.results[state.cursor], "edit")
	end, "open mark")

	map(buf, "n", km.open_split, function()
		open_mark(state.results[state.cursor], "split")
	end, "open in horizontal split")

	map(buf, "n", km.open_vsplit, function()
		open_mark(state.results[state.cursor], "vsplit")
	end, "open in vertical split")

	map(buf, "n", km.open_tab, function()
		open_mark(state.results[state.cursor], "tabedit")
	end, "open in new tab")

	-- Delete: d and dd both work naturally since buffer is nofile/nomodifiable
	-- We intercept d in normal mode
	map(buf, "n", "dd", function()
		local r = state.results[state.cursor]
		if not r then
			return
		end
		marks.remove_index(r.idx)
		refresh()
	end, "delete mark")

	map(buf, "n", km.delete, function()
		local r = state.results[state.cursor]
		if not r then
			return
		end
		marks.remove_index(r.idx)
		refresh()
	end, "delete mark")

	-- Reorder — no race condition, we own the cursor
	map(buf, "n", km.move_down, function()
		local r = state.results[state.cursor]
		if not r then
			return
		end
		local all = marks.load()
		local j = r.idx + 1
		if j > #all then
			return
		end
		marks.reorder(r.idx, j)
		-- Keep cursor on the moved mark
		state.cursor = state.cursor + 1
		refresh()
	end, "move mark down")

	map(buf, "n", km.move_up, function()
		local r = state.results[state.cursor]
		if not r then
			return
		end
		local j = r.idx - 1
		if j < 1 then
			return
		end
		marks.reorder(r.idx, j)
		state.cursor = state.cursor - 1
		refresh()
	end, "move mark up")

	-- Enter filter mode
	map(buf, "n", "/", function()
		set_list_active(false)
		flt_mod.activate(state.filter_win, function(query)
			state.cursor = 1
			refresh(query)
		end)
	end, "enter filter")

	map(buf, "n", "i", function()
		set_list_active(false)
		flt_mod.activate(state.filter_win, function(query)
			state.cursor = 1
			refresh(query)
		end)
	end, "enter filter")

	-- Close
	map(buf, "n", "q", M.close, "close")
	map(buf, "n", "<Esc>", M.close, "close")
end

local function setup_filter_keymaps()
	local buf = state.filter_buf

	-- <Esc>: back to normal/list mode, keep filter results
	map(buf, "i", "<Esc>", function()
		flt_mod.deactivate()
		set_list_active(true)
		vim.api.nvim_set_current_win(state.list_win)
	end, "back to list")

	-- <CR> in insert: open best match
	map(buf, "i", "<CR>", function()
		local r = state.results[1] -- top result
		flt_mod.deactivate()
		open_mark(r, "edit")
	end, "open best match")

	-- <C-j>/<C-k> in insert: navigate list without leaving filter
	map(buf, "i", "<C-j>", function()
		if #state.results == 0 then
			return
		end
		state.cursor = list_mod.clamp(state.cursor + 1, state.results)
		list_mod.set_cursor(state.list_win, state.cursor)
		list_mod.highlight_cursor(state.list_buf, state.cursor, state.results)
		update_preview()
	end, "move list down from filter")

	map(buf, "i", "<C-k>", function()
		if #state.results == 0 then
			return
		end
		state.cursor = list_mod.clamp(state.cursor - 1, state.results)
		list_mod.set_cursor(state.list_win, state.cursor)
		list_mod.highlight_cursor(state.list_buf, state.cursor, state.results)
		update_preview()
	end, "move list up from filter")

	-- <C-CR> or <C-s>/<C-v> splits from filter
	local km = state.config.ui.keymaps
	map(buf, "i", km.open_split, function()
		local r = state.results[state.cursor]
		flt_mod.deactivate()
		open_mark(r, "split")
	end, "open split from filter")

	map(buf, "i", km.open_vsplit, function()
		local r = state.results[state.cursor]
		flt_mod.deactivate()
		open_mark(r, "vsplit")
	end, "open vsplit from filter")
end

-- Lifecycle -------------------------------------------------------------------

function M.open(config)
	if is_open() then
		return
	end

	state.config = config
	win_mod.setup_highlights()
	prev_mod.setup_highlights()

	local layout = win_mod.calculate_layout(config)
	if not layout then
		vim.notify("cairn: terminal too small to open picker", vim.log.levels.WARN)
		return
	end

	-- Create buffers
	state.list_buf = list_mod.create_buf()
	state.filter_buf = flt_mod.create_buf()

	-- Create windows
	state.list_win = win_mod.open_win(
		state.list_buf,
		vim.tbl_extend("force", layout.list, { title = "Cairn", focusable = true }),
		true
	)

	state.filter_win = win_mod.open_win(
		state.filter_buf,
		vim.tbl_extend("force", layout.filter, { title = nil, focusable = true }),
		false
	)

	if layout.show_preview then
		-- Preview uses a temporary empty buf; preview.lua swaps it on load
		local prev_buf = vim.api.nvim_create_buf(false, true)
		state.prev_win = win_mod.open_win(
			prev_buf,
			vim.tbl_extend("force", layout.preview, { title = "Preview", focusable = false }),
			false
		)
	else
		state.prev_win = nil
	end

	-- Initial data load
	state.cursor = 1
	state.results = marks.filter("")

	-- Setup keymaps
	setup_list_keymaps()
	setup_filter_keymaps()

	-- Focus list window
	vim.api.nvim_set_current_win(state.list_win)

	-- Render initial state
	redraw_list()
	update_preview()

	state.open = true

	-- Autocmd: close if we lose focus to an unrelated window
	state.augroup = vim.api.nvim_create_augroup("cairn_picker", { clear = true })
	vim.api.nvim_create_autocmd("WinLeave", {
		group = state.augroup,
		callback = function()
			-- Allow moving between our own windows freely
			local cur = vim.api.nvim_get_current_win()
			local ours = {
				[state.list_win] = true,
				[state.filter_win] = true,
				[state.prev_win] = true,
			}
			if not ours[cur] then
				vim.schedule(M.close)
			end
		end,
	})

	-- Autocmd: close on VimResized (layout would be stale)
	vim.api.nvim_create_autocmd("VimResized", {
		group = state.augroup,
		once = true,
		callback = M.close,
	})
end

function M.close()
	if not state.open then
		return
	end
	state.open = false

	flt_mod.deactivate()

	-- Clear augroup
	if state.augroup then
		pcall(vim.api.nvim_del_augroup_by_name, "cairn_picker")
		state.augroup = nil
	end

	-- Close windows (buffers are wiped automatically via bufhidden=wipe)
	win_mod.close_win(state.list_win)
	win_mod.close_win(state.filter_win)
	win_mod.close_win(state.prev_win)

	state.list_win = nil
	state.filter_win = nil
	state.prev_win = nil
	state.list_buf = nil
	state.filter_buf = nil
	state.results = {}
	state.cursor = 1

	flt_mod.reset(false)
end

function M.is_open()
	return is_open()
end

return M
