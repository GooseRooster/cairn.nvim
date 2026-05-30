local M = {}

-- Default configuration
M.config = {
	data_dir = vim.fn.stdpath("data") .. "/cairn",
	use_git_root = true,
	keymaps = {
		add = "<leader>ma",
		remove = "<leader>md",
		picker = "<leader>mm",
		index_prefix = "<leader>",
	},
	picker = {
		delete = "<C-d>",
		move_down = "<C-S-k>",
		move_up = "<C-S-j>",
	},
}

-- Helpers ------------------------------------------------------------------

local function get_workspace_key()
	if M.config.use_git_root then
		local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
		if vim.v.shell_error == 0 and git_root and git_root ~= "" then
			return git_root
		end
	end
	return vim.fn.getcwd()
end

local function get_data_file()
	vim.fn.mkdir(M.config.data_dir, "p")
	local key = get_workspace_key():gsub('[/\\:*?"<>|]', "_")
	return M.config.data_dir .. "/" .. key .. ".json"
end

local function load_marks()
	local path = get_data_file()
	local f = io.open(path, "r")
	if not f then
		return {}
	end
	local content = f:read("*a")
	f:close()
	local ok, data = pcall(vim.fn.json_decode, content)
	return (ok and type(data) == "table") and data or {}
end

local function save_marks(marks)
	local f = io.open(get_data_file(), "w")
	if not f then
		vim.notify("cairn: could not write marks file", vim.log.levels.ERROR)
		return
	end
	f:write(vim.fn.json_encode(marks))
	f:close()
end

local function notify(msg, level)
	vim.notify("cairn: " .. msg, level or vim.log.levels.INFO)
end

-- API ----------------------------------------------------------------------

function M.add_mark()
	local file = vim.fn.expand("%:p")
	if file == "" then
		notify("no file in current buffer", vim.log.levels.WARN)
		return
	end
	local line = vim.fn.line(".")
	local col = vim.fn.col(".")
	local marks = load_marks()

	for _, m in ipairs(marks) do
		if m.file == file then
			m.line = line
			m.col = col
			save_marks(marks)
			notify(("updated → %s:%d"):format(vim.fn.fnamemodify(file, ":~:."), line))
			return
		end
	end

	table.insert(marks, { file = file, line = line, col = col })
	save_marks(marks)
	notify(("[%d] %s:%d"):format(#marks, vim.fn.fnamemodify(file, ":~:."), line))
end

function M.remove_current()
	local file = vim.fn.expand("%:p")
	local marks = load_marks()
	local new, removed = {}, false

	for _, m in ipairs(marks) do
		if m.file == file then
			removed = true
		else
			table.insert(new, m)
		end
	end

	if removed then
		save_marks(new)
		notify("removed " .. vim.fn.fnamemodify(file, ":~:."))
	else
		notify("current file is not marked", vim.log.levels.WARN)
	end
end

function M.goto_index(idx)
	local marks = load_marks()
	local m = marks[idx]
	if not m then
		notify("no mark at index " .. idx, vim.log.levels.WARN)
		return
	end
	vim.cmd("edit " .. vim.fn.fnameescape(m.file))
	vim.fn.cursor(m.line, m.col)
end

function M.get_marks()
	return load_marks()
end

function M.clear_marks()
	save_marks({})
	notify("all marks cleared")
end

-- Telescope picker ---------------------------------------------------------

function M.picker()
	local ok_telescope, _ = pcall(require, "telescope")
	if not ok_telescope then
		notify("telescope.nvim is required for the picker", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	local marks = load_marks()
	if #marks == 0 then
		notify("no marks for this workspace")
		return
	end

	local function build_entries(raw)
		local entries = {}
		for i, m in ipairs(raw) do
			table.insert(entries, {
				idx = i,
				file = m.file,
				line = m.line,
				col = m.col,
				rel = vim.fn.fnamemodify(m.file, ":~:."),
			})
		end
		return entries
	end

	local function make_finder(entries)
		return finders.new_table({
			results = entries,
			entry_maker = function(e)
				return {
					value = e,
					display = ("[%d] %s:%d"):format(e.idx, e.rel, e.line),
					ordinal = e.rel,
					path = e.file,
					lnum = e.line,
				}
			end,
		})
	end

	pickers
		.new({}, {
			prompt_title = "Cairn Marks",
			finder = make_finder(build_entries(marks)),
			sorter = conf.generic_sorter({}),

			previewer = previewers.new_buffer_previewer({
				title = "Preview",
				define_preview = function(self, entry)
					conf.buffer_previewer_maker(entry.path, self.state.bufnr, {
						bufname = self.state.bufname,
						winid = self.state.winid,
						preview = { fileencoding = "utf-8" },
						callback = function(bufnr)
							pcall(vim.api.nvim_buf_call, bufnr, function()
								vim.cmd("norm! " .. entry.lnum .. "G")
								vim.hl.range(
									bufnr,
									0,
									"TelescopePreviewLine",
									{ entry.lnum - 1, 0 },
									{ entry.lnum - 1, -1 }
								)
							end)
						end,
					})
				end,
			}),

			attach_mappings = function(prompt_bufnr, map)
				-- <CR>: open file at marked line
				actions.select_default:replace(function()
					local sel = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					vim.cmd("edit " .. vim.fn.fnameescape(sel.value.file))
					vim.fn.cursor(sel.value.line, sel.value.col)
				end)

				-- Delete mark
				map({ "i", "n" }, M.config.picker.delete, function()
					local sel = action_state.get_selected_entry()
					local current = load_marks()
					table.remove(current, sel.value.idx)
					save_marks(current)
					local picker = action_state.get_current_picker(prompt_bufnr)
					picker:refresh(make_finder(build_entries(current)), { reset_prompt = false })
				end)

				-- Move mark down
				map({ "i", "n" }, M.config.picker.move_down, function()
					local sel = action_state.get_selected_entry()
					local current = load_marks()
					local i, j = sel.value.idx, sel.value.idx + 1
					if j > #current then
						return
					end
					current[i], current[j] = current[j], current[i]
					save_marks(current)
					local picker = action_state.get_current_picker(prompt_bufnr)
					picker:refresh(make_finder(build_entries(current)), { reset_prompt = false })
				end)

				-- Move mark up
				map({ "i", "n" }, M.config.picker.move_up, function()
					local sel = action_state.get_selected_entry()
					local current = load_marks()
					local i, j = sel.value.idx, sel.value.idx - 1
					if j < 1 then
						return
					end
					current[i], current[j] = current[j], current[i]
					save_marks(current)
					local picker = action_state.get_current_picker(prompt_bufnr)
					picker:refresh(make_finder(build_entries(current)), { reset_prompt = false })
				end)

				return true
			end,
		})
		:find()
end

-- Keymap registration ------------------------------------------------------

function M._register_keymaps()
	local km = M.config.keymaps
	local opts = { noremap = true, silent = true }

	vim.keymap.set("n", km.add, M.add_mark, vim.tbl_extend("force", opts, { desc = "Cairn: add/update mark" }))
	vim.keymap.set("n", km.remove, M.remove_current, vim.tbl_extend("force", opts, { desc = "Cairn: remove mark" }))
	vim.keymap.set("n", km.picker, M.picker, vim.tbl_extend("force", opts, { desc = "Cairn: open picker" }))

	local prefix = km.index_prefix
	for i = 1, 9 do
		vim.keymap.set("n", prefix .. i, function()
			M.goto_index(i)
		end, vim.tbl_extend("force", opts, { desc = ("Cairn: go to mark %d"):format(i) }))
	end
end

-- Setup --------------------------------------------------------------------

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	M._register_keymaps()
end

return M
