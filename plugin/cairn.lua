-- plugin/cairn.lua
-- Entrypoint loaded automatically by Neovim's runtime.
-- Guards against being sourced more than once.
if vim.g.loaded_cairn then
	return
end
vim.g.loaded_cairn = true

vim.api.nvim_create_user_command("Cairn", function()
	require("cairn").open_picker()
end, { desc = "Open Cairn mark picker" })
