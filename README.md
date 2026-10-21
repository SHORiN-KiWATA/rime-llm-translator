# rime-llm-translator

给Rime输入法接入大模型进行拼音联想，支持全拼和小鹤双拼，支持TUI图形化配置。平时正常输入，在遇到长难句或者生僻句的时候通过双击v键（全拼）或双击分号键（小鹤双拼）呼叫Ai对拼音进行处理。输入的时候不太需要考虑输入的拼音是否正确，大模型强大的预测功能会自动把误拼甚至乱序处理成正确的句子。对于句子中的英文词汇也能正常处理，甚至还能补充正确的空格和标点符号。

>甚至还能用输入法跟ai聊天，装了 [Miyu](https://github.com/SHORiN-KiWATA/Miyu) 的话还能用 `miyu:` 前缀直接找她说话。

以下是无法正常输入，但Ai可以联想出来的例子：

包含英文词汇的输入

![](pictures/usevibecoding.gif)

歌词

![](pictures/cnag.gif)

古诗词

![](pictures/shici.gif)

超长句

![](pictures/steam.gif)

甚至可以在输入法给ai指令：

![](pictures/call.gif)

问题在于延迟，延迟主要由两部分组成，其一是首 Token 延迟，其二是思考，尤其在使用高推理程度的时候延迟尤为明显。解决办法是使用首 Token 速度极快的供应商，例如 Deepseek，使用输入速度更快的 Flash 模型，并适当降低或关闭思考程度。

>得益于 Deepseek 优秀的首 Token 速度和输出速度，从 Deepseek V4.1 Flash 开始，关闭思考已经可以做到秒出，即使开启 Max 思考，也能做到极低延迟。 

## 使用方法

1. 安装rime和雾凇拼音，或安装 Rime 的小鹤双拼（方案 ID：`double_pinyin_flypy`）

    > 初始化会自动识别雾凇全拼、雾凇小鹤双拼和官方小鹤双拼。其他基于rime的输入法方案（例如万象拼音）需要手动配置。

    输入法安装方法可以看[ShorinArch_中文输入法](https://github.com/SHORiN-KiWATA/Shorin-ArchLinux-Guide/wiki/%E4%B8%AD%E6%96%87%E8%BE%93%E5%85%A5%E6%B3%95)

2. 安装`rime-llm-translator-git`

    ```
    yay -S rime-llm-translator-git
    ```

    此时会安装三个文件：

    - `/usr/share/rime-llm-translator/default_state.json` 默认配置文件。用户空间的配置文件位于`~/.config/rime-llm-translator/state.json`。

    - `/usr/share/rime-data/lua/llm_translator.lua` 功能主体。

    - `/usr/bin/rime-llm-config` 管理工具，支持TUI编辑配置文件。

3. 运行`rime-llm-config init`初始化

    初始化完成后会有使用教程提示。

    这一步会自动在`~/.local/fcitx5/rime`编辑配置文件：

    > 配置文件在修改前会备份至`~/.cache/rime-llm-translator/backup/`
    
    - 新建`rime.lua`导入`llm_translator`，并注册触发键处理器；
    
      ```
      llm_translator = require("llm_translator")
      llm_processor = llm_translator.processor
      ```
      > 如果已经存在的话会备份后在文件末尾追加；旧版只有第一行的会补上第二行
    
    - 如果检测到安装了雾凇全拼或小鹤双拼，会分别更新 `rime_ice.custom.yaml`、`double_pinyin_flypy.custom.yaml`，启用处理器和翻译器并配置一些上屏规则。已有配置会备份，重复初始化不会重复插入补丁。全拼补丁如下：

      ```
      patch:
        # 1. 扩充允许输入的字符集：保留雾凇默认（含大写与辅码引导符 `），再允许在拼音中直接输入指定标点
        "speller/alphabet": "zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA`.,?'!:<>\\/"
        # 2. 触发键处理器：截获 vv 的第二个 v，把触发词从编码区拿掉并武装 AI 翻译
        "engine/processors/@before 0": lua_processor@llm_processor
        # 3. 将 Lua AI 脚本 (llm_translator) 插入到翻译器列表的第 0 位之前
        "engine/translators/@before 0": lua_translator@llm_translator
        # 4. 定义正则捕获规则：把输入当成不可分割的整体喂给 AI 脚本处理
        "recognizer/patterns/llm_pinyin": "^[a-z][a-z.,?'!:<>/\\\\]*$"
      ```
    - 如果fcitx5正在运行的话，重启以重新部署。
    
4. 配置大模型

    运行`rime-llm-config`命令进行模型配置。自带了一个 opencode zen 的公共节点，算是体验一下hhh

    > 本机装了 `claude` / `codex` / `agy` / `opencode` / `miyu` 中任意一个的话，不用填 key 也能直接用，见下面的「本机 CLI 后端」。

    > opencode zen 从 09-19 起给免费模型加了一道「只能从 OpenCode 里用」的闸，第三方客户端一律 `403 · OpenCode's free tier can only be used from within OpenCode`。实测判据是请求得长得像 opencode 发的：流式、工具清单里有 `shell` 和 `read`、带 `x-opencode-*` 头。所以发往 `opencode.ai/zen` 的请求会自动改成这个形状（流式 + 两条永不调用的占位工具声明），其他节点一个字节都不动。这是对面服务端的策略，他们随时可能改判据，免费模型又开始报 403 的话就是这里过期了。

### 小鹤双拼

安装并在 Rime 方案选单中启用 `double_pinyin_flypy`，然后运行 `rime-llm-config init` 并重新部署。切换到「小鹤双拼」后：

| 输入 | 行为 |
| --- | --- |
| `test;;` | 显示挂载成功，无需调用模型 |
| `nihcuijp;;` | 把 `ni hao shi jie` 交给模型，联想「你好世界」 |
| `jp:nihcuijp;;` | 联想后按 `jp:` 规则输出日文 |
| `vv` | 正常输入「追」等 `zhui` 音节 |

小鹤的 `vv` 是有效编码，因此固定使用方案级的 `;;` 触发键；全拼继续使用全局设置里的触发键，默认 `vv`。初始化会为小鹤额外允许分号进入编码区，并添加：

```yaml
patch:
  "llm_translator/input_scheme": "flypy"
  "llm_translator/trigger": ";;"
```

这两项与初始化生成的处理器、翻译器、alphabet 和 recognizer 补丁一起使用。使用其他 ID 的自定义小鹤方案时，可将 `double_pinyin_flypy.custom.yaml` 中的这些补丁合并到对应方案的 `.custom.yaml`，保留自己的其他配置。可通过 `llm_translator/trigger` 单独修改触发键，同时在 alphabet 和 recognizer 中允许相应字符；`llm_translator/input_scheme: pinyin` 可以关闭该方案的双拼展开。

薄荷小鹤方案默认通过 `codeLengthLimit_processor: 25` 限制编码长度，超过后会删除末尾输入，长句无法完整交给 AI。小鹤初始化补丁会用 `"codeLengthLimit_processor": null` 停用这个限制；已初始化过的用户再次运行 `rime-llm-config init` 并重新部署即可升级。该补丁也适用于没有此处理器的官方和雾凇小鹤方案。需要恢复原方案的长度限制时，从 `double_pinyin_flypy.custom.yaml` 删除这条补丁后重新部署。

请求发送前，小鹤编码会按标准键位展开成带音节空格的全拼，支持零声母、`zh/ch/sh`、`ü` 和共用韵母键。前缀保持原样，HTTP、CLI 和 Miyu 后端共用这一步转换。自定义词库中的「常用英文词」和「拼音缩写映射」会保留原拼写；混输英文建议先加入常用英文词，或使用全大写拼写。无法识别的双字母码和末尾单个声母会原样交给模型纠错，未配置映射的简拼仍可能存在歧义。小鹤音形、形码和其他双拼布局不在当前支持范围内。

从源码安装到用户目录（无需覆盖系统文件）：

```sh
install -Dm644 src/llm_translator.lua ~/.local/share/fcitx5/rime/lua/llm_translator.lua
install -Dm755 src/rime-llm-config ~/.local/bin/rime-llm-config
install -Dm644 src/default_state.json ~/.local/bin/default_state.json
~/.local/bin/rime-llm-config init
~/.local/bin/rime-llm-config
```

本地回归验证：`python3 -m unittest discover -s tests -v`，需要 Python 3、Lua 和 curl，测试仅使用临时目录及本地 HTTP 服务。

## 本机 CLI 后端

除了填 API 地址和密钥，也可以把本机已经登录好的编码 agent 当供应商，走它们的订阅额度：

| 节点            | 命令       | 默认模型                 |
| --------------- | ---------- | ------------------------ |
| Claude Code CLI | `claude`   | sonnet                   |
| Codex CLI       | `codex`    | gpt-5.6-terra            |
| Antigravity CLI | `agy`      | gemini-3.8-flash-low     |
| opencode CLI    | `opencode` | opencode/big-pickle      |
| Miyu            | `miyu`     | 交给 Miyu 自己的模型路由 |

- 打开 `rime-llm-config` 时会自动探测 PATH 上有哪些命令，各生成一个 `[CLI]` 节点；模型列表能问命令的就问命令（缓存一天），在「供应商和模型」里照常选模型，在「激活配置」里选中即可。
- 装了 [Miyu](https://github.com/SHORiN-KiWATA/Miyu) 的话，会顺带只读导入 Miyu 里配好的供应商，显示为 `[Miyu]` 节点（id 前缀 `miyu_`，列表里排在自己的节点和 `[CLI]` 节点之后），改了 Miyu 的配置下次打开自动同步；这类节点只能在这里改模型和思考档位。Miyu 里 `$env:NAME` 形式和逗号分隔的多把 key 会被解析后取第一把；Miyu 里给每个模型选过的思考档位也会作为默认值带过来。
- CLI 节点的编辑表单里可以改可执行文件路径；思考档位和 HTTP 节点一样，在模型列表上按 `t` 选（claude 五档、codex 五档、agy 只对 claude-* 模型开放三档）。
- 每次请求是一次性的，不带会话、不开工具、不写磁盘。CLI 线比直连 HTTP 慢：实测 claude sonnet 约 3 秒，codex / agy / opencode 约 7~10 秒，超时可在「全局参数设置 → CLI 后端超时」调整（默认 60 秒）。
- Lua 侧走 CLI 时是调用 `rime-llm-config ask` 完成请求的，`rime-llm-config ask "拼音"` 也可以在终端里直接用来排查问题；`rime-llm-config debug` 的日志同样会记录 CLI 线的请求。

## 前缀行为

例如 `jp:woshizhongguoren` → 私は中国人です。冒号前面那几个字母决定这次要模型做什么。

程序要按前缀决定注入什么提示词：`rime-llm-config` 主菜单 →「前缀行为」。

- 内置了如下前缀

  `call:` 和 AI 对话

  `eng:` 输出英文译文

  `jp:` 输出日文译文

  `cmd:` 输出命令

  `sh:` 输出 Shell 脚本

  `moe:` 以猫娘预期输出

## 跟 Miyu 聊天

装了 [Miyu](https://github.com/SHORiN-KiWATA/Miyu) 的话，拼音以 `miyu:` 开头时不走当前供应商，而是直接把这句话发给 Miyu，她的回答作为第一个候选上屏。跟 `call:` 是两回事：`call:` 是让**当前节点**的模型帮你解决问题，`miyu:` 是找 **Miyu** 本人说话，两条线不会混。

```
miyu:xianzaijidian        →  晚上10点15分。
miyu:wogangcaishuolesm    →  你说的是测试一下。
```

- 说的话进的是 Miyu 的一个固定会话（默认叫 `rime`，不存在就建），所以**前后文是连着的**，可以接着上一句问。想清空重开：`miyu session clear rime`。
- 用哪个模型交给 Miyu 自己决定，跟着她的全局模型池走。想给这个会话单独定一个：`miyu session models rime <序号或模型名>`，`default` 恢复跟随全局。
- 冒号后面的内容原样交给 Miyu，不参与提示词里 `cn:` / `jp:` / `moe:` 那套前缀组合。
- 发给她的宿主指令里带了拼音还原的注意点（英文词、纯首字母简拼、前后鼻音、数字读音、断句和书名号）和自定义词库，所以 `mrfz` 这种简拼她也认。
- 默认不给她工具、要求短答案纯文本，实测一问一答 4 到 15 秒。

## 编辑配置

`rime-llm-config`是编辑配置的TUI工具。TUI 里每次保存都会顺手把 `config.lua` 导出一遍，HTTP 线（读 `config.lua`）和 CLI 线（读 `state.json`）用的提示词和词库因此始终一致。

![](pictures/TUI/mainmenu.png)

- 激活配置

  此处可以设置具体使用哪一个配置

  ![](pictures/TUI/active.png)

- 供应商和模型

  ![](pictures/TUI/edit.png)

  最左侧一列是供应商（同时也是配置），按 `i` 可以配置供应商的显示名称、api地址、api密钥和协议。协议留 `自动` 时按 URL 判断是 OpenAI Chat 还是 Anthropic Messages，走不带 anthropic 字样的 Claude 中转时手动选 Anthropic 即可。

  > 显示名称指的是在输入法候选框里显示的名称

  ![](pictures/TUI/provider.png)

  配置可用之后右侧会出现`可用模型`列表，回车确定此配置使用的模型。会思考的模型后面带 `[思考]` 标记，在模型上按 `t` 选思考档位（关闭 / 开启 / low / medium / high / max 等，按模型分别记住）。档位表来自 [models.dev](https://models.dev) 的模型目录：本机装了 Miyu 就直接复用它的缓存，否则首次打开时自动下载并缓存一天，也可以用 `rime-llm-config catalog` 手动刷新；目录里没有的模型按厂商族（DeepSeek、Gemini、MiMo、智谱、OpenRouter、Anthropic）给出默认档位。各家的私有写法（`thinking.type`、`reasoning_effort`、`reasoning.effort`、`output_config.effort`、`deepseek-chat` 与 `deepseek-reasoner` 互换、Anthropic 思考时不传 temperature）在导出 `config.lua` 时解析成每个节点的 `request_extra`，Lua 侧不再识别厂商。`rime-llm-config status` 会把当前节点解析后的请求附加字段打印出来。

- 全局参数配置

  ![](pictures/TUI/prompt2.png)

  这里可以对系统提示词和模型参数进行配置。`历史上下文容量`指的是记录多少之前输入过的内容，用于提高ai的联想质量。

  提示词这里只放**核心**（职责 / 注意点 / 严格遵守）。`call:` `jp:` `moe:` 这类前缀的行为规则搬到了「前缀行为」里单独配置，见下一节。`base:`：base64 是确定性计算，模型算既慢又容易错，所以这一条被程序接管了。收到 `base:` 时先把这两个字从前缀里摘掉，模型只负责把拼音变成中文，编码由程序做，结果不会错。组合照样成立，`base:jp:woshizhongguoren` 得到的是「私は中国人です」的 base64，连写的 `basejp:` 和 `jpbase:` 也认。

- 自定义词库

  ![](pictures/TUI/vocab.png)

  这里可以自定义词库。`常用英文词`是为了避免ai把句子中的英文视为拼音进行分词；`拼音缩写映射`可以提高首字母缩写、简拼的联想质量。

  ![](pictures/TUI/vocab3.png)

## 移除该功能

1. 删除 `~/.local/share/fcitx5/rime/rime.lua` 中的这两行（如果文件里只有这两行，直接删文件）：

    ```
    llm_translator = require("llm_translator")
    llm_processor = llm_translator.processor
    ```

2. 删除 `~/.local/share/fcitx5/rime/rime_ice.custom.yaml` 中的四条 patch；小鹤双拼还需要从 `double_pinyin_flypy.custom.yaml` 删除对应的 alphabet、processor、translator、recognizer 以及 `llm_translator/input_scheme`、`llm_translator/trigger`、`codeLengthLimit_processor` 补丁（如果文件是 init 新建的，直接删文件）：

    ```
      # 1. 扩充允许输入的字符集：保留雾凇默认（含大写与辅码引导符 `），再允许在拼音中直接输入指定标点
      "speller/alphabet": "zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA`.,?'!:<>\\/"
      # 2. 触发键处理器：截获 vv 的第二个 v，把触发词从编码区拿掉并武装 AI 翻译
      "engine/processors/@before 0": lua_processor@llm_processor
      # 3. 将 Lua AI 脚本 (llm_translator) 插入到翻译器列表的第 0 位之前
      "engine/translators/@before 0": lua_translator@llm_translator
      # 4. 定义正则捕获规则：把输入当成不可分割的整体喂给 AI 脚本处理
      "recognizer/patterns/llm_pinyin": "^[a-z][a-z.,?'!:<>/\\\\]*$"
    ```

    > init 之前的原文件备份在 `~/.cache/rime-llm-translator/backup/`，直接覆盖回去也可以。

3. 移除缓存、配置和软件包：

    ```
    gio trash ~/.config/rime-llm-translator ~/.cache/rime-llm-translator
    yay -Rns rime-llm-translator-git
    ```

    > 调试日志在 `~/.cache/rime-llm-translator/debug.log`，请求时的临时文件在 `$XDG_RUNTIME_DIR/rime-llm-translator/`，都会随上面两个目录或重启一起消失。

4. 重启 fcitx5（或在托盘菜单点「重新部署」）让 Rime 重新部署。
