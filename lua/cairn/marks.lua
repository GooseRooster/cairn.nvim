-- cairn/marks.lua
-- Pure data layer.

local M = {}

-- Will be set by init.lua after setup()
M._config = nil

local function cfg()
	return M._config
end

-- Workspace key ---------------------------------------------------------------

local function get_workspace_key()
	if cfg().use_git_root then
		local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
		if vim.v.shell_error == 0 and git_root and git_root ~= "" then
			git_root = git_root:gsub("\r$", "") -- strip CRLF artifact from Windows shells
			git_root = git_root:gsub("^/(%a)/", "%1:/") -- /d/path → d:/path (git-for-Windows)
			-- Reject non-path output (e.g. cmd.exe ECHO ON echoes the command as line [1])
			if git_root:match("^/") or git_root:match("^%a:[/\\]") then
				return git_root
			end
		end
	end
	return vim.fn.getcwd()
end

local function get_data_file()
	vim.fn.mkdir(cfg().data_dir, "p")
	local key = get_workspace_key():gsub('[/\\:*?"<>|]', "_")
	return cfg().data_dir .. "/" .. key .. ".json"
end

-- IO --------------------------------------------------------------------------

function M.load()
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

function M.save(marks)
	local f = io.open(get_data_file(), "w")
	if not f then
		vim.notify("cairn: could not write marks file", vim.log.levels.ERROR)
		return false
	end
	f:write(vim.fn.json_encode(marks))
	f:close()
	return true
end

-- CRUD ------------------------------------------------------------------------

--- Add or update a mark for the given file at line/col.
--- Returns (marks, "added"|"updated")
function M.add(file, line, col)
	local marks = M.load()
	for _, m in ipairs(marks) do
		if m.file == file then
			m.line = line
			m.col = col
			M.save(marks)
			return marks, "updated"
		end
	end
	table.insert(marks, { file = file, line = line, col = col })
	M.save(marks)
	return marks, "added"
end

--- Remove mark by file path.
--- Returns (marks, removed:bool)
function M.remove_file(file)
	local marks = M.load()
	local new, removed = {}, false
	for _, m in ipairs(marks) do
		if m.file == file then
			removed = true
		else
			table.insert(new, m)
		end
	end
	if removed then
		M.save(new)
	end
	return new, removed
end

--- Remove mark by 1-based index.
function M.remove_index(idx)
	local marks = M.load()
	if not marks[idx] then
		return marks, false
	end
	table.remove(marks, idx)
	M.save(marks)
	return marks, true
end

--- Swap marks at 1-based indices i and j.
--- Returns (marks, success:bool)
function M.reorder(i, j)
	local marks = M.load()
	if not marks[i] or not marks[j] then
		return marks, false
	end
	marks[i], marks[j] = marks[j], marks[i]
	M.save(marks)
	return marks, true
end

--- Clear all marks for this workspace.
function M.clear()
	M.save({})
end

--- Remove marks whose files no longer exist on disk.
--- Returns a list of pruned file paths (empty if nothing was removed).
function M.prune_missing()
	local all = M.load()
	local kept, pruned = {}, {}
	for _, m in ipairs(all) do
		if vim.fn.filereadable(m.file) == 1 then
			kept[#kept + 1] = m
		else
			pruned[#pruned + 1] = m.file
		end
	end
	if #pruned > 0 then
		M.save(kept)
	end
	return pruned
end

--- Update line/col for an already-marked file (no-op if the file is not marked).
function M.update_file_position(file, line, col)
	local all = M.load()
	for _, m in ipairs(all) do
		if m.file == file then
			m.line = line
			m.col  = col
			return M.save(all)
		end
	end
end

-- Fuzzy filter ----------------------------------------------------------------

--- Score a single mark against a query string.
--- Returns nil if no match, otherwise a numeric score (higher = better).
--- Strategy: exact path match > prefix match > subsequence match.
local function score(mark, query)
	if query == "" then
		return 1
	end
	local rel = vim.fn.fnamemodify(mark.file, ":~:.")
	local rel_lower = rel:lower()
	local q = query:lower()

	-- Exact substring
	local exact_pos = rel_lower:find(q, 1, true)
	if exact_pos then
		-- Bonus for matching at start of filename component
		return exact_pos == 1 and 1000 or (500 - exact_pos)
	end

	-- Subsequence
	local si, qi = 1, 1
	local q_len = #q
	while si <= #rel_lower and qi <= q_len do
		if rel_lower:sub(si, si) == q:sub(qi, qi) then
			qi = qi + 1
		end
		si = si + 1
	end
	if qi > q_len then
		return 100 - si -- matched, but penalise longer paths
	end

	return nil -- no match
end

--- Filter and sort marks by query. Returns list of {mark, idx, score} tables.
function M.filter(query)
	local marks = M.load()
	local results = {}
	for i, m in ipairs(marks) do
		local s = score(m, query)
		if s then
			table.insert(results, { mark = m, idx = i, score = s })
		end
	end
	if query ~= "" then
		table.sort(results, function(a, b)
			return a.score > b.score
		end)
	end
	return results
end

return M
