--
-- KITTY RUNNER
--

local fn = vim.fn
local cmd = vim.cmd
local loop = vim.loop
local nvim_set_keymap = vim.api.nvim_set_keymap
local Cfg = {
	runner_is_open = {},
}

local M = {}

local remember_command = {}

local function random_kitty_port()
	local port
	while true do
		port = "unix:/tmp/kitty" .. math.random(10000, 99999)
		-- TODO: check if that file exists?
		if not Cfg.runner_is_open[port] then
			break
		end
	end
	return port
end

local function fallback_ports(port)
	if port == "<local>" then
		port = random_kitty_port()
		vim.b.kitty_runner_port = port
		return port
	end
	if tonumber(port) ~= nil then
		return "unix:/tmp/kitty" .. port
	end
	if "" == port then
		port = nil
	end
	return port or vim.b.kitty_runner_port or Cfg.kitty_port
end

local function open_new_runner(port)
	port = fallback_ports(port)
	loop.spawn("kitty", {
		args = { "-o", "allow_remote_control=yes", "--listen-on=" .. port, "--title=" .. Cfg.runner_name },
	})
	Cfg.runner_is_open[port] = true
end
M.open_new_runner = open_new_runner

local function send_kitty_command(cmd_args, command, port)
	port = fallback_ports(port)
	local args = { "@", "--to=" .. port }
	args = vim.list_extend(args, cmd_args)
	table.insert(args, command)
	loop.spawn("kitty", {
		args = args,
	})
end

local function prepare_command(region)
	local lines
	if region[1] == 0 then
		lines = vim.api.nvim_buf_get_lines(
			0,
			vim.api.nvim_win_get_cursor(0)[1] - 1,
			vim.api.nvim_win_get_cursor(0)[1],
			true
		)
	else
		lines = vim.api.nvim_buf_get_lines(0, region[1] - 1, region[2], true)
	end
	local command = table.concat(lines, "\r") .. "\r"
	return command
end

function M.run_command(region, port, dontrem)
	port = fallback_ports(port)
	full_command = prepare_command(region)
	if not dontrem then
		remember_command[port] = full_command
	end
	-- delete visual selection marks
	vim.cmd([[delm <>]])
	if not Cfg.runner_is_open[port] then
		open_new_runner(port)
	end
	send_kitty_command(Cfg.run_cmd, full_command, port)
end

function M.re_run_command(port)
	port = fallback_ports(port)
	if remember_command[port] then
		if not Cfg.runner_is_open[port] then
			open_new_runner(port)
		end
		send_kitty_command(Cfg.run_cmd, full_command, port)
	end
end

function M.prompt_run_command(port, dontrem)
	port = fallback_ports(port)
	fn.inputsave()
	local command = fn.input("Command: ")
	fn.inputrestore()
	full_command = command .. "\r"
	if not dontrem then
		remember_command[port] = full_command
	end
	if not Cfg.runner_is_open[port] then
		open_new_runner(port)
	end
	send_kitty_command(Cfg.run_cmd, full_command, port)
end

function M.kill_runner(port)
	port = fallback_ports(port)
	if Cfg.runner_is_open[port] then
		send_kitty_command(Cfg.kill_cmd, nil, port)
	end
end

function M.clear_runner(port)
	port = fallback_ports(port)
	if Cfg.runner_is_open[port] then
		send_kitty_command(Cfg.run_cmd, "", port)
	end
end

local function define_commands()
	cmd([[command! -nargs=? KittyOpen lua require('kitty-runner').open_new_runner('<args>')]])
	cmd([[command! KittyOpenLocal lua require('kitty-runner').open_new_runner('<local>')]])
	cmd([[command! -nargs=? KittyReRunCommand lua require('kitty-runner').re_run_command('<args>')]])
	cmd(
		[[command! -nargs=? -range KittySendLines lua require('kitty-runner').run_command(vim.region(0, vim.fn.getpos("'<"), vim.fn.getpos("'>"), "l", false)[0], '<args>')]]
	)
	cmd(
		[[command! -nargs=? -range KittySendLinesOnce lua require('kitty-runner').run_command(vim.region(0, vim.fn.getpos("'<"), vim.fn.getpos("'>"), "l", false)[0], '<args>', false)]]
	)
	cmd([[command! -nargs=? KittyRunCommand lua require('kitty-runner').prompt_run_command('<args>')]])
	cmd([[command! -nargs=? KittyRunCommandOnce lua require('kitty-runner').prompt_run_command('<args>', false)]])
	cmd([[command! -nargs=? KittyClearRunner lua require('kitty-runner').clear_runner('<args>')]])
	cmd([[command! -nargs=? KittyKillRunner lua require('kitty-runner').kill_runner('<args>')]])
end

local function define_keymaps()
	nvim_set_keymap("n", "<leader>tr", ":KittyRunCommand<cr>", {})
	nvim_set_keymap("x", "<leader>ts", ":KittySendLines<cr>", {})
	nvim_set_keymap("n", "<leader>ts", ":KittySendLines<cr>", {})
	nvim_set_keymap("n", "<leader>tc", ":KittyClearRunner<cr>", {})
	nvim_set_keymap("n", "<leader>tk", ":KittyKillRunner<cr>", {})
	nvim_set_keymap("n", "<leader>tl", ":KittyReRunCommand<cr>", {})
end

function M.setup(cfg_)
	Cfg = vim.tbl_extend("force", Cfg, cfg_ or {})
	local uuid_handle = io.popen([[uuidgen|sed 's/.*/&/']])
	local uuid = uuid_handle:read("*a")
	uuid_handle:close()
	Cfg.runner_name = "vim-cmd" .. uuid
	Cfg.run_cmd = Cfg.run_cmd or { "send-text", "--match=title:" .. Cfg.runner_name }
	Cfg.kill_cmd = Cfg.kill_cmd or { "close-window", "--match=title:" .. Cfg.runner_name }
	if Cfg.use_keymaps ~= nil then
		Cfg.use_keymaps = Cfg.use_keymaps
	else
		Cfg.use_keymaps = true
	end
	math.randomseed(os.time())
	Cfg.kitty_port = random_kitty_port()
	define_commands()
	if Cfg.use_keymaps == true then
		define_keymaps()
	end
end

return M
