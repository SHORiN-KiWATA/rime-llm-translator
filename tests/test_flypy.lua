-- Run by tests/test_flypy.py with an isolated config and a local HTTP server.
local llm = dofile("src/llm_translator.lua")
local function eq(actual, expected)
    assert(actual == expected, string.format("expected %q, got %q", tostring(expected), tostring(actual)))
end
local cfg = { vocab = { terms = { "Python", "Steam", "Visual Studio Code" }, maps = { { "mrfz", "明日方舟" } } } }
local syllables = {
    aa = "a", ai = "ai", an = "an", ah = "ang", ao = "ao", ee = "e", ei = "ei",
    en = "en", eg = "eng", er = "er", oo = "o", ou = "ou", ni = "ni", hc = "hao",
    ui = "shi", jp = "jie", vv = "zhui", iv = "chui", uv = "shui", vs = "zhong",
    is = "chong", rs = "rong", js = "jiong", qs = "qiong", xs = "xiong",
    bk = "bing", gk = "guai", ik = "chuai", uk = "shuai", vk = "zhuai",
    nl = "niang", ll = "liang", jl = "jiang", gl = "guang", vl = "zhuang",
    jx = "jia", gx = "gua", ix = "chua", uo = "shuo", bo = "bo", po = "po",
    mo = "mo", fo = "fo", lo = "luo", lt = "lve", nt = "nve", jt = "jue",
    qt = "que", xt = "xue", yt = "yue", lv = "lv", nv = "nv", jv = "ju",
    qv = "qu", xv = "xu", yv = "yu", ju = "ju", qr = "quan", xr = "xuan",
    jy = "jun", yy = "yun", dy = "dun", qq = "qiu", bw = "bei", uf = "shen",
    dg = "deng", vh = "zhang", vj = "zhan", vz = "zhou", xn = "xiao", pb = "pin",
    pm = "pian", yo = "yo", ys = "yong", bl = "biang", tw = "tei", cw = "cei", fn = "fiao",
}
local count = 0
for code, pinyin in pairs(syllables) do
    eq(llm._expand_flypy({}, code), pinyin)
    count = count + 1
end
eq(llm._expand_flypy({}, "nihcuijp"), "ni hao shi jie")
eq(llm._expand_flypy({}, "jp:moe:nihc"), "jp:moe:ni hao")
eq(llm._expand_flypy({}, "basejp:nihc"), "basejp:ni hao")
eq(llm._expand_flypy({}, "miyu:nihc"), "miyu:ni hao")
eq(llm._expand_flypy({}, "ni'hc,vv!"), "ni ' hao , zhui !")
eq(llm._expand_flypy({}, "nihcn"), "ni hao n")
eq(llm._expand_flypy({}, "bq"), "bq") -- invalid syllable survives for model correction
eq(llm._expand_flypy({}, "nihc中文123"), "ni hao 中文123")
eq(llm._expand_flypy(cfg, "woyspython"), "wo yong python")
eq(llm._expand_flypy(cfg, "woaiSteam"), "wo ai Steam")
eq(llm._expand_flypy(cfg, "nihcmrfz"), "ni hao mrfz")
local short = { vocab = { terms = { "dpi", "python" }, maps = { { "ky", "可以" } } } }
eq(llm._expand_flypy(short, "mkyi"), "ming yi") -- valid syllable wins over a term starting mid-pair
eq(llm._expand_flypy(short, "hdpi"), "hai pi")
eq(llm._expand_flypy(short, "nihcky"), "ni hao ky")
eq(llm._expand_flypy(short, "nihcfpython"), "ni hao f python") -- invalid pair may still yield to a term
eq(llm._expand_flypy(cfg, "Visual Studio Code"), "Visual Studio Code")
eq(llm._expand_flypy(cfg, ""), "")

local function context(input)
    local ctx = { input = input, caret_pos = #input, properties = {} }
    function ctx:get_property(name) return self.properties[name] or "" end
    function ctx:set_property(name, value) self.properties[name] = value end
    function ctx:is_composing() return self.input ~= "" end
    function ctx:pop_input(n)
        self.input = self.input:sub(1, self.caret_pos - n) .. self.input:sub(self.caret_pos + 1)
        self.caret_pos = self.caret_pos - n
    end
    return ctx
end
local function environment(id, input, options)
    return { engine = { context = context(input or ""), schema = {
        schema_id = id,
        config = { get_string = function(_, name) return (options or {})[name] end },
    } } }
end
local function key(char)
    return { keycode = string.byte(char), repr = function() return char == ";" and "semicolon" or char end,
        release = function() return false end,
        ctrl = function() return false end, alt = function() return false end,
        shift = function() return false end, super = function() return false end }
end
local flypy = environment("double_pinyin_flypy", "nihc;")
local full = environment("rime_ice", "nihaov")
eq(llm._input_scheme_of(flypy), "flypy")
eq(llm._input_scheme_of(full), "pinyin")
eq(llm._trigger_of({ ai_trigger = "vv" }, flypy), ";;")
eq(llm._trigger_of({ ai_trigger = "zz" }, full), "zz")
eq(llm._trigger_of({}, full), "vv")
eq(llm._trigger_of({}, environment("custom", "", { ["llm_translator/input_scheme"] = "flypy" })), ";;")
eq(llm._trigger_of({}, environment("double_pinyin_flypy", "", { ["llm_translator/trigger"] = "!!" })), "!!")
eq(llm.processor.func(key(";"), flypy), 1)
eq(flypy.engine.context.input, "nihc")
eq(flypy.engine.context:get_property("llm_armed"), "nihc")
eq(llm.processor.func(key("v"), environment("double_pinyin_flypy", "v")), 2)
eq(llm.processor.func(key("v"), environment("double_pinyin_flypy", "nihcv")), 2)
eq(llm.processor.func(key(";"), environment("double_pinyin_flypy", ";")), 2)
eq(llm.processor.func(key("v"), full), 1)
eq(full.engine.context.input, "nihao")

local yielded
_G.Candidate = function(kind, start, finish, text, comment)
    return { type = kind, start = start, _end = finish, text = text, comment = comment }
end
_G.yield = function(candidate) yielded = candidate end
local function translate(input, env)
    yielded = nil
    llm.func(input, { start = 0, _end = #input }, env or environment("double_pinyin_flypy", input))
    return yielded
end
-- Real curl -> local server: HTTP sees expanded full pinyin, candidates retain raw-code spans.
local candidate = translate("nihc", flypy)
eq(candidate.text, "你好")
eq(candidate._end, 4)
eq(translate("vv"), nil) -- zhui must not trigger the suffix compatibility path
eq(translate("test;;").text, "✅ rime-llm-translator 挂载成功!")
eq(translate("nihaovv", environment("rime_ice", "nihaovv")).text, "你好")

-- CLI and Miyu use the same expansion, without invoking installed agents.
local original_popen = io.popen
local command
io.popen = function(cmd)
    command = cmd
    return { read = function() return "你好" end, close = function() return true end }
end
-- The isolated config exposes its table so the cached config can switch backend.
flypy_test_config.active_profile = "cli"
eq(translate("jp:nihc;;").text, "你好")
assert(command:find("'jp:ni hao'", 1, true), command)
eq(translate("miyu:nihc;;").text, "你好")
assert(command:find(" chat 'ni hao'", 1, true), command)
eq(translate("base:nihc;;").text, llm._base64_encode("你好"))
assert(command:find("'ni hao'", 1, true), command)
io.popen = original_popen
print(string.format("Lua: %d syllables, mixed input, triggers, HTTP/CLI/Miyu and base64 passed", count))
