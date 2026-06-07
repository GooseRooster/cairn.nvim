-- cairn/init.lua
-- Public API and setup(). Entry point for require("cairn").

local M = {}

M.config = {
	data_dir = vim.fn.stdpath("data") .. "/cairn",
	use_git_root = true,
	track_cursor = false,

	ui = {
		min_width_for_preview = 120, -- columns below which preview is hidden
		short_path = true, -- show filename only; set false for full relative path

		keymaps = {
			open_split = "<C-s>",
			open_vsplit = "<C-v>",
			open_tab = "<C-t>",
			delete = "<C-d>",
			move_down = "<C-j>",
			move_up = "<C-k>",
		},
	},

	keymaps = {
		add = "<leader>ma",
		remove = "<leader>md",
		picker = "<leader>mm",
		index_prefix = "<leader>",
	},
}

-- Lazy-load submodules so nothing is required until needed
local function marks()
	return require("cairn.marks")
end
local function picker()
	return require("cairn.ui.picker")
end

-- Public API ------------------------------------------------------------------

function M.add_mark()
	local file = vim.fn.expand("%:p")
	if file == "" then
		vim.notify("cairn: no file in current buffer", vim.log.levels.WARN)
		return
	end
	local _, status = marks().add(file, vim.fn.line("."), vim.fn.col("."))
	local rel = vim.fn.fnamemodify(file, ":~:.")
	if status == "updated" then
		vim.notify(("cairn: updated → %s:%d"):format(rel, vim.fn.line(".")))
	else
		local count = #marks().load()
		vim.notify(("cairn: [%d] %s:%d"):format(count, rel, vim.fn.line(".")))
	end
end

function M.remove_current()
	local file = vim.fn.expand("%:p")
	local _, removed = marks().remove_file(file)
	if removed then
		vim.notify("cairn: removed " .. vim.fn.fnamemodify(file, ":~:."))
	else
		vim.notify("cairn: current file is not marked", vim.log.levels.WARN)
	end
end

function M.goto_index(idx)
	local pruned = marks().prune_missing()
	if #pruned > 0 then
		vim.notify("cairn: removed " .. #pruned .. " missing mark(s)", vim.log.levels.WARN)
		return
	end
	local all = marks().load()
	local m = all[idx]
	if not m then
		vim.notify("cairn: no mark at index " .. idx, vim.log.levels.WARN)
		return
	end
	vim.cmd("edit " .. vim.fn.fnameescape(m.file))
	vim.fn.cursor(m.line, m.col)
end

function M.open_picker()
	local pruned = marks().prune_missing()
	if #pruned > 0 then
		vim.notify(
			"cairn: removed " .. #pruned .. " missing mark(s):\n" .. table.concat(pruned, "\n"),
			vim.log.levels.WARN
		)
	end
	picker().open(M.config)
end

function M.close_picker()
	picker().close()
end

function M.get_marks()
	return marks().load()
end

function M.clear_marks()
	marks().clear()
	vim.notify("cairn: all marks cleared")
end

-- Keymap registration ---------------------------------------------------------

function M._register_keymaps()
	local km = M.config.keymaps
	local opts = { noremap = true, silent = true }
	local function o(desc)
		return vim.tbl_extend("force", opts, { desc = desc })
	end

	if km.add and km.add ~= "" then
		vim.keymap.set("n", km.add, M.add_mark, o("Cairn: add/update mark"))
	end
	if km.remove and km.remove ~= "" then
		vim.keymap.set("n", km.remove, M.remove_current, o("Cairn: remove mark"))
	end
	if km.picker and km.picker ~= "" then
		vim.keymap.set("n", km.picker, M.open_picker, o("Cairn: open picker"))
	end

	local prefix = km.index_prefix
	if prefix and prefix ~= "" then
		for i = 1, 9 do
			vim.keymap.set("n", prefix .. i, function()
				M.goto_index(i)
			end, o(("Cairn: go to mark %d"):format(i)))
		end
	end
end

-- Setup -----------------------------------------------------------------------

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	-- Give marks module a reference to config
	require("cairn.marks")._config = M.config
	M._register_keymaps()
	if M.config.track_cursor then
		vim.api.nvim_create_autocmd("BufLeave", {
			group = vim.api.nvim_create_augroup("cairn_track_cursor", { clear = true }),
			callback = function(args)
				local file = vim.api.nvim_buf_get_name(args.buf)
				if file == "" or vim.bo[args.buf].buftype ~= "" then
					return
				end
				local win = vim.fn.bufwinid(args.buf)
				if win == -1 then
					return
				end
				local pos = vim.api.nvim_win_get_cursor(win)
				marks().update_file_position(file, pos[1], pos[2] + 1)
			end,
		})
	end
end

return M
