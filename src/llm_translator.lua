-- ==============================================================================
-- 文件名：llm_translator.lua
-- 功能：基于 LLM 的拼音长句整句翻译引擎
--   · translator：把武装好的拼音整段交给大模型，结果作为第一个候选
--   · processor ：截获触发键（默认 vv）的最后一个字符，把触发词从编码区拿掉并
--                 记下当时的拼音（context property），编码区里永远只有纯拼音
--   · HTTP 线走 curl，协议只有 openai-chat / anthropic 两种；厂商差异（思考档、
--     改模型名）全部由 rime-llm-config 在导出 config.lua 时解析成 request_extra
--   · CLI 线（claude / codex / agy / opencode / miyu）交给 rime-llm-config ask
--
-- rime.lua 里写：
--   llm_translator = require("llm_translator")
--   llm_processor  = llm_translator.processor
-- 方案 patch 里写：
--   "engine/processors/@before 0":  lua_processor@llm_processor
--   "engine/translators/@before 0": lua_translator@llm_translator
-- ==============================================================================

local PROP_ARMED = "llm_armed"
local kRejected, kAccepted, kNoop = 0, 1, 2

-- ==============================================================================
-- JSON（编码 + 解码，够用即可：对象 / 数组 / 字符串 / 数字 / 布尔 / null）
-- ==============================================================================
local json = {}
do
    local escape_map = {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
        ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    }
    local function escape_char(c)
        return escape_map[c] or string.format("\\u%04x", string.byte(c))
    end
    local function encode_string(s)
        return '"' .. string.gsub(s, '[%c"\\]', escape_char) .. '"'
    end
    local function is_array(t)
        if t[1] ~= nil then return true end
        return next(t) == nil and getmetatable(t) == json.array_mt
    end
    json.array_mt = {}
    json.null = setmetatable({}, { __tostring = function() return "null" end })

    local function encode_value(v, out)
        local tv = type(v)
        if v == nil or v == json.null then
            out[#out + 1] = "null"
        elseif tv == "boolean" then
            out[#out + 1] = v and "true" or "false"
        elseif tv == "number" then
            if v ~= v or v == math.huge or v == -math.huge then
                out[#out + 1] = "null"
            elseif math.type and math.type(v) == "integer" then
                out[#out + 1] = string.format("%d", v)
            elseif v == math.floor(v) and math.abs(v) < 1e15 then
                out[#out + 1] = string.format("%d", v)
            else
                out[#out + 1] = string.format("%.14g", v)
            end
        elseif tv == "string" then
            out[#out + 1] = encode_string(v)
        elseif tv == "table" then
            if is_array(v) then
                out[#out + 1] = "["
                for i = 1, #v do
                    if i > 1 then out[#out + 1] = "," end
                    encode_value(v[i], out)
                end
                out[#out + 1] = "]"
            else
                out[#out + 1] = "{"
                local first = true
                local keys = {}
                for k in pairs(v) do keys[#keys + 1] = tostring(k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    if not first then out[#out + 1] = "," end
                    first = false
                    out[#out + 1] = encode_string(k)
                    out[#out + 1] = ":"
                    encode_value(v[k], out)
                end
                out[#out + 1] = "}"
            end
        else
            error("json: cannot encode " .. tv)
        end
    end

    function json.encode(v)
        local out = {}
        encode_value(v, out)
        return table.concat(out)
    end

    -- ---------- decode ----------
    local function utf8_char(cp)
        if utf8 and utf8.char then return utf8.char(cp) end
        if cp < 0x80 then return string.char(cp) end
        if cp < 0x800 then
            return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))
        end
        if cp < 0x10000 then
            return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
        end
        return string.char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
    end

    local unescape_map = {
        ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
    }

    local decode_value

    local function skip_ws(s, i)
        local _, e = string.find(s, "^[ \t\r\n]*", i)
        return e + 1
    end

    local function decode_string(s, i)
        -- s:sub(i, i) == '"'
        local out = {}
        local j = i + 1
        while true do
            local c = string.sub(s, j, j)
            if c == "" then error("json: unterminated string") end
            if c == '"' then
                return table.concat(out), j + 1
            elseif c == "\\" then
                local e = string.sub(s, j + 1, j + 1)
                if e == "u" then
                    local hex = string.sub(s, j + 2, j + 5)
                    if not string.match(hex, "^%x%x%x%x$") then error("json: bad \\u escape") end
                    local cp = tonumber(hex, 16)
                    j = j + 6
                    if cp >= 0xD800 and cp <= 0xDBFF then
                        local hex2 = string.match(s, "^\\u(%x%x%x%x)", j)
                        if hex2 then
                            local lo = tonumber(hex2, 16)
                            if lo >= 0xDC00 and lo <= 0xDFFF then
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                                j = j + 6
                            end
                        end
                    end
                    out[#out + 1] = utf8_char(cp)
                else
                    local r = unescape_map[e]
                    if not r then error("json: bad escape \\" .. e) end
                    out[#out + 1] = r
                    j = j + 2
                end
            else
                -- 吃掉一整段普通字符
                local k = string.find(s, '["\\]', j)
                if not k then error("json: unterminated string") end
                out[#out + 1] = string.sub(s, j, k - 1)
                j = k
            end
        end
    end

    local function decode_number(s, i)
        local num = string.match(s, "^-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if not num or num == "" then error("json: bad number at " .. i) end
        local v = tonumber(num)
        if not v then error("json: bad number " .. num) end
        return v, i + #num
    end

    function decode_value(s, i)
        i = skip_ws(s, i)
        local c = string.sub(s, i, i)
        if c == "{" then
            local obj = {}
            i = skip_ws(s, i + 1)
            if string.sub(s, i, i) == "}" then return obj, i + 1 end
            while true do
                i = skip_ws(s, i)
                if string.sub(s, i, i) ~= '"' then error("json: expected key at " .. i) end
                local key
                key, i = decode_string(s, i)
                i = skip_ws(s, i)
                if string.sub(s, i, i) ~= ":" then error("json: expected ':' at " .. i) end
                local val
                val, i = decode_value(s, i + 1)
                obj[key] = val
                i = skip_ws(s, i)
                local d = string.sub(s, i, i)
                if d == "," then i = i + 1
                elseif d == "}" then return obj, i + 1
                else error("json: expected ',' or '}' at " .. i) end
            end
        elseif c == "[" then
            local arr = setmetatable({}, json.array_mt)
            i = skip_ws(s, i + 1)
            if string.sub(s, i, i) == "]" then return arr, i + 1 end
            while true do
                local val
                val, i = decode_value(s, i)
                arr[#arr + 1] = val
                i = skip_ws(s, i)
                local d = string.sub(s, i, i)
                if d == "," then i = i + 1
                elseif d == "]" then return arr, i + 1
                else error("json: expected ',' or ']' at " .. i) end
            end
        elseif c == '"' then
            return decode_string(s, i)
        elseif c == "t" and string.sub(s, i, i + 3) == "true" then
            return true, i + 4
        elseif c == "f" and string.sub(s, i, i + 4) == "false" then
            return false, i + 5
        elseif c == "n" and string.sub(s, i, i + 3) == "null" then
            return json.null, i + 4
        elseif c == "-" or string.match(c, "%d") then
            return decode_number(s, i)
        end
        error("json: unexpected character '" .. c .. "' at " .. i)
    end

    function json.decode(s)
        local v, i = decode_value(s, 1)
        i = skip_ws(s, i)
        if i <= #s then error("json: trailing garbage at " .. i) end
        return v
    end
end

-- ==============================================================================
-- 配置：带 2 秒缓存的 config.lua 读取（每个按键都会经过这里）
-- ==============================================================================
local config_cache = { cfg = nil, err = nil, at = -1 }

local function config_path()
    local dir = os.getenv("RIME_LLM_CONFIG_DIR")
    if not dir or dir == "" then
        local home = os.getenv("HOME")
        if not home then return nil, "系统环境变量 HOME 无法读取" end
        dir = home .. "/.config/rime-llm-translator"
    end
    return dir .. "/config.lua"
end

local function load_config(force)
    local now = os.time()
    if not force and config_cache.at >= 0 and now - config_cache.at < 2 then
        return config_cache.cfg, config_cache.err
    end
    local cfg, err
    local path, perr = config_path()
    if not path then
        err = perr
    else
        local f = io.open(path, "r")
        if not f then
            err = "未生成: " .. path .. " (请运行 rime-llm-config 并点击 Save)"
        else
            f:close()
            local chunk, lerr = loadfile(path)
            if not chunk then
                err = "配置语法错误: " .. tostring(lerr)
            else
                local ok, res = pcall(chunk)
                if ok and type(res) == "table" then cfg = res else err = "配置格式错误" end
            end
        end
    end
    config_cache = { cfg = cfg, err = err, at = now }
    return cfg, err
end

local function trigger_of(cfg)
    local trigger = cfg and cfg.ai_trigger
    if type(trigger) ~= "string" or trigger == "" then trigger = "vv" end
    return trigger
end

-- ==============================================================================
-- 小工具
-- ==============================================================================
local function shell_quote(str)
    return "'" .. string.gsub(str or "", "'", "'\\''") .. "'"
end

local function trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function strip_think(s)
    s = string.gsub(s, "<think>.-</think>", "")
    s = string.gsub(s, "<think>.*", "")
    return trim(s)
end

local function short(s, n)
    return (string.gsub(string.sub(s or "", 1, n or 40), "[\r\n]", " "))
end

local function dir_exists(path)
    if not path or path == "" then return false end
    local ok = os.rename(path, path)
    return ok == true
end

-- 找一个能写临时文件的目录：优先 XDG_RUNTIME_DIR 下的私有目录，其次配置目录里的 tmp
local function pick_tmp_dir(cfg)
    local dirs = cfg and cfg.tmp_dirs or {}
    for _, d in ipairs(dirs) do
        if dir_exists(d) then return d end
    end
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime and dir_exists(runtime) then return runtime end
    return "/tmp"
end

local tmp_seq = 0
local function tmp_path(dir, suffix)
    tmp_seq = tmp_seq + 1
    return string.format("%s/rime-llm-%d-%d-%d%s", dir, os.time(), tmp_seq, math.random(1000000), suffix)
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function debug_log(cfg, lines)
    local flag = cfg and cfg.debug_flag
    if not flag then return end
    local f = io.open(flag, "r")
    if not f then return end
    f:close()
    local log = io.open(cfg.debug_log or "/tmp/rime_llm_debug.log", "a")
    if not log then return end
    log:write("========== " .. os.date("%Y-%m-%d %H:%M:%S") .. " ==========\n")
    for _, l in ipairs(lines) do log:write(l, "\n") end
    log:write("==================================================\n\n")
    log:close()
end

-- ==============================================================================
-- 上屏历史（按字节容量的滑动窗口）与回复缓存
-- ==============================================================================
local commit_history = {}
local current_history_bytes = 0

local function push_history(text, max_bytes)
    table.insert(commit_history, text)
    current_history_bytes = current_history_bytes + #text
    while current_history_bytes > max_bytes and #commit_history > 0 do
        local removed = table.remove(commit_history, 1)
        current_history_bytes = current_history_bytes - #removed
    end
end

local REPLY_CACHE_SIZE = 16
local reply_cache = { order = {}, map = {} }

local function cache_get(key)
    return reply_cache.map[key]
end

local function cache_put(key, value)
    if reply_cache.map[key] == nil then
        table.insert(reply_cache.order, key)
        if #reply_cache.order > REPLY_CACHE_SIZE then
            local old = table.remove(reply_cache.order, 1)
            reply_cache.map[old] = nil
        end
    end
    reply_cache.map[key] = value
end

-- ==============================================================================
-- 后端：CLI（rime-llm-config ask）
-- ==============================================================================
local CLI_PROTOCOLS = { ["claude-code"] = true, codex = true, antigravity = true, opencode = true, miyu = true }

local function ask_cli_backend(cfg, profile_id, profile, send_text, history_text)
    local tool = cfg.config_tool
    if not tool or tool == "" then
        tool = "rime-llm-config"
    else
        local f = io.open(tool, "r")
        if f then f:close() else tool = "rime-llm-config" end
    end
    local cmd = string.format(
        "%s ask --profile %s --history %s %s 2>/dev/null",
        shell_quote(tool), shell_quote(profile_id), shell_quote(history_text or ""), shell_quote(send_text)
    )
    local handle = io.popen(cmd)
    if not handle then return nil, "io.popen 崩溃" end
    local response = handle:read("*a") or ""
    handle:close()
    if response == "" then return nil, "无响应 (" .. (profile.binary or "CLI") .. ")" end
    if string.sub(response, 1, 4) == "ERR:" then
        return nil, short(string.sub(response, 6), 60)
    end
    return trim(response), nil
end

-- ==============================================================================
-- 后端：HTTP（curl，参数走 -K 配置文件，命令行上不出现密钥和正文）
-- ==============================================================================
local function effective_protocol(profile)
    local p = profile.protocol or ""
    if p == "anthropic" or p == "openai-chat" then return p end
    local url = string.lower(profile.api_url or "")
    if string.find(url, "anthropic", 1, true) or string.find(url, "/messages$") then return "anthropic" end
    return "openai-chat"
end

local function build_body(cfg, profile, protocol, system_prompt, user_content)
    local body = { model = profile.model }
    local max_tokens = profile.max_tokens or cfg.max_tokens or 4000
    body.max_tokens = max_tokens
    if protocol == "anthropic" then
        body.system = system_prompt
        body.messages = { { role = "user", content = user_content } }
    else
        body.messages = {
            { role = "system", content = system_prompt },
            { role = "user", content = user_content },
        }
    end
    -- temperature：profile 里 false 表示不传（Anthropic 思考模式要求）；nil 用全局
    if profile.temperature ~= false then
        local temp = profile.temperature
        if temp == nil then temp = cfg.temperature end
        if temp ~= nil then body.temperature = temp end
    end
    -- request_extra：rime-llm-config 解析好的厂商私有字段（思考档等），覆盖同名键
    local extra = profile.request_extra
    if type(extra) == "string" and extra ~= "" then
        local ok, obj = pcall(json.decode, extra)
        if ok and type(obj) == "table" then
            for k, v in pairs(obj) do body[k] = v end
        end
    end
    return body
end

local function curl_config_quote(s)
    return '"' .. string.gsub(string.gsub(s or "", "\\", "\\\\"), '"', '\\"') .. '"'
end

local function http_request(cfg, profile, protocol, body_json)
    local dir = pick_tmp_dir(cfg)
    local body_path = tmp_path(dir, ".json")
    local conf_path = tmp_path(dir, ".curl")
    if not write_file(body_path, body_json) then
        return nil, "无法写入临时文件: " .. dir
    end
    local lines = {
        "url = " .. curl_config_quote(profile.api_url),
        "request = \"POST\"",
        "header = \"Content-Type: application/json\"",
        "data = " .. curl_config_quote("@" .. body_path),
    }
    if protocol == "anthropic" then
        lines[#lines + 1] = "header = " .. curl_config_quote("x-api-key: " .. profile.api_key)
        lines[#lines + 1] = "header = \"anthropic-version: 2023-06-01\""
    else
        lines[#lines + 1] = "header = " .. curl_config_quote("Authorization: Bearer " .. profile.api_key)
    end
    if not write_file(conf_path, table.concat(lines, "\n") .. "\n") then
        os.remove(body_path)
        return nil, "无法写入临时文件: " .. dir
    end
    local cmd = string.format(
        "curl -sSL --connect-timeout %s --max-time %s -K %s 2>&1",
        tostring(cfg.connect_timeout or 2.0), tostring(cfg.max_time or 30.0), shell_quote(conf_path)
    )
    local handle = io.popen(cmd)
    local response = nil
    if handle then
        response = handle:read("*a")
        handle:close()
    end
    os.remove(body_path)
    os.remove(conf_path)
    if not handle then return nil, "网络组件 io.popen 崩溃" end
    return response or "", nil
end

-- 从响应 JSON 里取正文；返回 (text, err)
local function extract_reply(protocol, response)
    local ok, data = pcall(json.decode, response)
    if not ok or type(data) ~= "table" then
        return nil, "解析失败: " .. short(response, 40)
    end
    if type(data.error) == "table" then
        local msg = data.error.message or data.error.msg or data.error.type
        return nil, "API 错误: " .. short(tostring(msg or "?"), 60)
    elseif type(data.error) == "string" then
        return nil, "API 错误: " .. short(data.error, 60)
    end
    local parts = {}
    if protocol == "anthropic" then
        if type(data.content) == "table" then
            for _, block in ipairs(data.content) do
                if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
                    parts[#parts + 1] = block.text
                end
            end
        end
    else
        local choice = type(data.choices) == "table" and data.choices[1]
        local message = type(choice) == "table" and choice.message
        local content = type(message) == "table" and message.content
        if type(content) == "string" then
            parts[#parts + 1] = content
        elseif type(content) == "table" then
            for _, block in ipairs(content) do
                if type(block) == "table" and type(block.text) == "string" then
                    parts[#parts + 1] = block.text
                end
            end
        end
    end
    local text = strip_think(table.concat(parts, ""))
    if text == "" then return nil, "空回复" end
    return text, nil
end

local function ask_http_backend(cfg, profile, send_text, history_text)
    if not profile.api_url or profile.api_url == "" then return nil, "API 地址为空，请配置" end
    if not profile.api_key or profile.api_key == "" then return nil, "API Key 为空，请配置" end
    if not profile.model or profile.model == "" then return nil, "模型为空，请配置" end

    local protocol = effective_protocol(profile)
    local system_prompt = (cfg.prompt or "") .. (cfg.vocab_prompt or "")
    local user_content = send_text
    if history_text ~= "" then
        user_content = string.format("【历史输入】：%s\n【当前用户输入（如果由call开头说明是指令）】：%s", history_text, send_text)
    end
    local body = build_body(cfg, profile, protocol, system_prompt, user_content)
    local body_json = json.encode(body)

    local response, err = http_request(cfg, profile, protocol, body_json)
    debug_log(cfg, {
        "【节点模型】 " .. (profile.name or "Unknown") .. " (" .. tostring(body.model) .. ", " .. protocol .. ")",
        "【发出的 JSON】", body_json, "",
        "【收到的 Raw 返回】", tostring(response or err or "nil"),
    })
    if err then return nil, err end
    if response == "" then return nil, "⏳ 请求超时无响应" end
    return extract_reply(protocol, response)
end

-- ==============================================================================
-- translator
-- ==============================================================================
local function yield_error(seg, text, msg)
    yield(Candidate("llm", seg.start, seg._end, text, "❌ " .. tostring(msg)))
end

local function translator_func(input, seg, env)
    local ctx = env.engine.context
    local cfg, cfg_err = load_config()
    local trigger = trigger_of(cfg)

    -- 1) processor 武装：编码区是纯拼音，property 记着武装时的拼音
    -- 2) 兼容旧接法（没装 processor）：拼音以触发词结尾
    local send_text
    local armed = ctx:get_property(PROP_ARMED)
    if armed ~= "" and armed == input then
        send_text = input
    elseif #input > #trigger and string.sub(input, -#trigger) == trigger then
        send_text = string.sub(input, 1, -#trigger - 1)
    else
        return
    end

    if send_text == "test" then
        yield(Candidate("llm", seg.start, seg._end, "✅ rime-llm-translator 挂载成功!", "连通测试"))
        return
    end
    if not cfg then
        yield_error(seg, send_text, cfg_err)
        return
    end

    send_text = string.gsub(send_text, "[\\/]", "、")
    if #send_text == 0 then return end

    local profile_id = cfg.active_profile or ""
    local profile = cfg.profiles and cfg.profiles[profile_id]
    if not profile then
        yield_error(seg, send_text, "找不到节点: " .. tostring(profile_id))
        return
    end

    local history_text = table.concat(commit_history, "")
    local cache_key = table.concat({ profile_id, tostring(profile.model), tostring(profile.request_extra), send_text, history_text }, "\0")
    local cached = cache_get(cache_key)
    if cached then
        yield(Candidate("llm", seg.start, seg._end, cached, "✨ " .. (profile.name or "AI")))
        return
    end

    local text, err
    if CLI_PROTOCOLS[profile.protocol or ""] then
        text, err = ask_cli_backend(cfg, profile_id, profile, send_text, history_text)
    else
        text, err = ask_http_backend(cfg, profile, send_text, history_text)
    end

    if text and text ~= "" then
        cache_put(cache_key, text)
        yield(Candidate("llm", seg.start, seg._end, text, "✨ " .. (profile.name or "AI")))
    else
        yield_error(seg, send_text, err or "未知错误")
    end
end

local function translator_init(env)
    env.llm_commit_conn = env.engine.context.commit_notifier:connect(function(ctx)
        local text = ctx:get_commit_text()
        if text and text ~= "" and string.match(text, "%S") then
            local cfg = load_config()
            local max_bytes = (cfg and tonumber(cfg.max_history_bytes)) or 240
            push_history(text, max_bytes)
        end
    end)
end

local function translator_fini(env)
    if env.llm_commit_conn then env.llm_commit_conn:disconnect() end
end

-- ==============================================================================
-- processor：截获触发词的最后一个字符
-- ==============================================================================
local function processor_func(key, env)
    if key:release() then return kNoop end
    if key:ctrl() or key:alt() or key:shift() or key:super() then return kNoop end
    local ctx = env.engine.context
    if not ctx:is_composing() then return kNoop end

    local cfg = load_config()
    local trigger = trigger_of(cfg)
    -- 单字符触发词沿用旧接法（拼音以它结尾），不截获，免得 lv / nv 打不出来
    if #trigger < 2 then return kNoop end
    if key:repr() ~= string.sub(trigger, -1) then return kNoop end

    local input = ctx.input
    local caret = ctx.caret_pos
    local head = string.sub(input, 1, caret)
    local tail = string.sub(input, caret + 1)
    local prefix = string.sub(trigger, 1, -2)
    if #head <= #prefix or string.sub(head, -#prefix) ~= prefix then return kNoop end

    local armed_text = string.sub(head, 1, #head - #prefix) .. tail
    if armed_text == "" then return kNoop end

    ctx:set_property(PROP_ARMED, armed_text)
    ctx:pop_input(#prefix)   -- 触发 update → 重新翻译，translator 看到 property 后发请求
    return kAccepted
end

local function processor_init(env)
    local ctx = env.engine.context
    -- 编码区一变、不再等于武装时的拼音，就解除武装（退格、Esc、上屏后的 Clear 都会走到这里）
    env.llm_update_conn = ctx.update_notifier:connect(function(c)
        local armed = c:get_property(PROP_ARMED)
        if armed ~= "" and c.input ~= armed then c:set_property(PROP_ARMED, "") end
    end)
    -- 选了候选（含分段选词）就解除武装；想对剩余部分再用 AI 就再按一次触发词
    env.llm_select_conn = ctx.select_notifier:connect(function(c)
        if c:get_property(PROP_ARMED) ~= "" then c:set_property(PROP_ARMED, "") end
    end)
end

local function processor_fini(env)
    if env.llm_update_conn then env.llm_update_conn:disconnect() end
    if env.llm_select_conn then env.llm_select_conn:disconnect() end
end

-- ==============================================================================
-- 导出：顶层是 translator（兼容旧的 rime.lua 写法），.processor 是处理器
-- ==============================================================================
return {
    init = translator_init,
    func = translator_func,
    fini = translator_fini,
    processor = { init = processor_init, func = processor_func, fini = processor_fini },
    -- 供离线测试使用
    _json = json,
    _build_body = build_body,
    _extract_reply = extract_reply,
    _effective_protocol = effective_protocol,
}
