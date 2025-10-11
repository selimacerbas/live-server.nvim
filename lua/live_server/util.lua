local uv = vim.loop

local U = {}

function U.notify(msg, opts, level)
    if opts and opts.notify == false then return end
    vim.notify(msg, (level and vim.log.levels[level]) or vim.log.levels.INFO, { title = "live-server.nvim" })
end

function U.joinpath(...)
    local sep = package.config:sub(1, 1)
    return table.concat({ ... }, sep)
end

function U.dirname(p)
    return p:match("^(.*)[/\\]") or "."
end

function U.basename(p)
    return (p:gsub("[/\\]+$", "")):match("([^/\\]+)$") or p
end

function U.find_git_root()
    local cwd = uv.cwd()
    local sep = package.config:sub(1, 1)
    local cur = cwd
    while cur and #cur > 0 do
        local candidate = U.joinpath(cur, ".git")
        if uv.fs_stat(candidate) then return cur end
        local parent = cur:match(("^(.*)%s[^%s]+$"):format(sep, sep))
        if not parent or parent == cur then break end
        cur = parent
    end
    return nil
end

function U.url_decode(s)
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

function U.url_encode(s)
    return (tostring(s):gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

function U.html_escape(s)
    local map = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;' }
    return (tostring(s):gsub("[&<>\"]", map):gsub("'", map["'"]))
end

function U.path_has_prefix(path, prefix)
    if not path or not prefix then return false end
    if #prefix == 1 and (prefix == "/" or prefix == "\\") then return true end
    local norm_p = path:gsub("[/\\]+", "/")
    local norm_x = prefix:gsub("[/\\]+", "/")
    return norm_p:sub(1, #norm_x) == norm_x
end

-- Browser open (nvim 0.10+), with portable fallbacks
function U.open_browser(url)
    if vim.ui and vim.ui.open then
        local ok = pcall(vim.ui.open, url)
        if ok then return end
    end
    local sys = (jit and jit.os) or vim.loop.os_uname().sysname
    if sys == "Windows" or sys == "Windows_NT" then
        vim.schedule(function() vim.fn.jobstart({ "cmd.exe", "/c", "start", "", url }, { detach = true }) end)
    elseif sys == "OSX" or sys == "Darwin" then
        vim.schedule(function() vim.fn.jobstart({ "open", url }, { detach = true }) end)
    else
        vim.schedule(function() vim.fn.jobstart({ "xdg-open", url }, { detach = true }) end)
    end
end

-- Telescope present?
local function has_telescope()
    local ok = pcall(require, "telescope")
    return ok
end

-- generic list picker
function U.pick_list(opts, cb)
    local title = (opts and opts.title) or "Select"
    local items = (opts and opts.items) or {}
    if has_telescope() then
        local pickers      = require("telescope.pickers")
        local finders      = require("telescope.finders")
        local conf         = require("telescope.config").values
        local actions      = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        pickers.new({}, {
            prompt_title = title,
            finder = finders.new_table({ results = items }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _map)
                actions.select_default:replace(function()
                    local entry = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    local val = entry and (entry.value or entry[1] or entry.text)
                    cb(val)
                end)
                return true
            end,
        }):find()
    else
        vim.ui.select(items, { prompt = title }, cb)
    end
end

-- specialized port picker
function U.pick_port(opts, cb)
    local default = tostring((opts and opts.default) or 4070)
    local known = {}
    for _, p in ipairs(opts.known_ports or {}) do table.insert(known, tostring(p)) end
    table.sort(known, function(a, b) return tonumber(a) < tonumber(b) end)
    local list = {}
    for _, p in ipairs(known) do table.insert(list, p) end
    table.insert(list, "Other…")

    local function finish_with_port(p)
        if not p then return cb(nil) end
        p = tonumber(p)
        if not p or p <= 0 or p > 65535 then
            return U.notify("Invalid port.", { notify = true }, "ERROR")
        end
        cb(p)
    end

    U.pick_list({ title = "Pick Port (default " .. default .. ")", items = list }, function(choice)
        if not choice then return cb(nil) end
        if choice == "Other…" then
            vim.ui.input({ prompt = "Port: ", default = default }, finish_with_port)
        else
            finish_with_port(choice)
        end
    end)
end

return U
