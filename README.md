# rime-llm-translator

给Rime输入法接入大模型进行拼音联想，支持TUI图形化配置。平时正常输入，在遇到长难句或者生僻句的时候通过双击v键呼叫Ai对拼音进行处理。输入的时候不太需要考虑输入的拼音是否正确，大模型强大的预测功能会自动把误拼甚至乱序处理成正确的句子。对于句子中的英文词汇也能正常处理，甚至还能补充正确的空格和标点符号。

>甚至还能用输入法跟ai聊天。

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

缺点是大模型出token需要时间，导致联想有一点延迟，尤其在使用推理模型的时候延迟尤为明显。使用快速响应的模型或者本地部署小模型可以解决延迟问题，但是效果就一般了。我目前使用`deepseek v4 pro 关闭思考`和`gemini-3-flash-preview 最少思考`，效果很棒。

>也许可以使用特调小模型。

## 使用方法

1. 安装rime和雾凇拼音

    > 对其他基于rime的输入法方案也是生效的，例如万象拼音，但是要自己手动配置。

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

    > 配置文件在修改前会备份至`~/.cache/rime-llm-translator-backup`
    
    - 新建`rime.lua`导入`llm_translator`，并注册触发键处理器；
    
      ```
      llm_translator = require("llm_translator")
      llm_processor = llm_translator.processor
      ```
      > 如果已经存在的话会备份后在文件末尾追加；旧版只有第一行的会补上第二行
    
    - 如果检测到安装了雾凇拼音的话会新建`rime_ice.custom.yaml`写入patch，启用处理器和翻译器并配置一些上屏规则；

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
      > 旧版打过补丁的文件会原地补上第 2 行并把 alphabet 换成保留雾凇默认的版本

    - 如果fcitx5正在运行的话，重启以重新部署。

    > 触发键的工作方式：按下 `vv` 的第二个 `v` 时，处理器把这两个 `v` 从编码区拿掉，只记住此刻的拼音，AI 候选排在第一位。编码区里始终是纯拼音，所以选候选 2、分段选词、用户词典学习都和平时一样，不会再把 `vv` 带到句尾。退格、选词、上屏都会解除这次触发，想对剩余部分再用 AI 就再按一次 `vv`。没有注册处理器的旧接法（拼音以 `vv` 结尾）仍然可用，但会有 `vv` 残留的问题，升级后请重新执行一次 `rime-llm-config init`。
    
4. 配置大模型

    运行`rime-llm-config`命令进行模型配置。自带了一个 opencode zen 的公共节点，算是体验一下hhh

    > 本机装了 `claude` / `codex` / `agy` / `opencode` / `miyu` 中任意一个的话，不用填 key 也能直接用，见下面的「本机 CLI 后端」。

## 本机 CLI 后端

除了填 API 地址和密钥，也可以把本机已经登录好的编码 agent 当供应商，走它们的订阅额度：

| 节点 | 命令 | 默认模型 |
|---|---|---|
| Claude Code CLI | `claude` | sonnet |
| Codex CLI | `codex` | gpt-5.6-terra |
| Antigravity CLI | `agy` | gemini-3.8-flash-low |
| opencode CLI | `opencode` | opencode/big-pickle |
| Miyu | `miyu` | 交给 Miyu 自己的模型路由 |

- 打开 `rime-llm-config` 时会自动探测 PATH 上有哪些命令，各生成一个 `[CLI]` 节点；模型列表能问命令的就问命令（缓存一天），在「供应商和模型」里照常选模型，在「激活配置」里选中即可。
- 装了 [Miyu](https://github.com/SHORiN-KiWATA/Miyu) 的话，会顺带只读导入 Miyu 里配好的供应商，显示为 `[Miyu]` 节点（id 前缀 `miyu_`，列表里排在自己的节点和 `[CLI]` 节点之后），改了 Miyu 的配置下次打开自动同步；这类节点只能在这里改模型和思考档位。Miyu 里 `$env:NAME` 形式和逗号分隔的多把 key 会被解析后取第一把；Miyu 里给每个模型选过的思考档位也会作为默认值带过来。
- CLI 节点的编辑表单里可以改可执行文件路径；思考档位和 HTTP 节点一样，在模型列表上按 `t` 选（claude 五档、codex 五档、agy 只对 claude-* 模型开放三档）。
- 每次请求是一次性的，不带会话、不开工具、不写磁盘。CLI 线比直连 HTTP 慢：实测 claude sonnet 约 3 秒，codex / agy / opencode 约 7~10 秒，超时可在「全局参数设置 → CLI 后端超时」调整（默认 60 秒）。
- Lua 侧走 CLI 时是调用 `rime-llm-config ask` 完成请求的，`rime-llm-config ask "拼音"` 也可以在终端里直接用来排查问题；`rime-llm-config debug` 的日志同样会记录 CLI 线的请求。

## 编辑配置

`rime-llm-config`是编辑配置的TUI工具。TUI 里每次保存都会顺手把 `config.lua` 导出一遍，HTTP 线（读 `config.lua`）和 CLI 线（读 `state.json`）用的提示词和词库因此始终一致。

> 如果你要手动编辑配置文件请编辑`~/.config/rime-llm-translator/state.json`后用`rime-llm-config sync`命令同步至`config.lua`。每个节点可用的字段：`protocol`（`auto` / `openai-chat` / `anthropic` / 各 CLI）、`api_url`、`api_key`、`model`、`thinking`（按模型存档位 id，如 `{"deepseek-v4-flash": "max"}`）、`extra_body`（原样并进请求体的私有字段）、`model_temperature`（按模型覆盖发散度）。


![](pictures/TUI/mainmenu.png)

- 激活配置

  此处可以设置具体使用哪一个配置

  ![](pictures/TUI/active.png)

- 供应商和模型

  ![](pictures/TUI/edit.png)

  最左侧一列是供应商（同时也是配置），按 `i` 可以配置供应商的显示名称、api地址、api密钥和协议。协议留 `自动` 时按 URL 判断是 OpenAI Chat 还是 Anthropic Messages，走不带 anthropic 字样的 Claude 中转时手动选 Anthropic 即可。

  > 显示名称指的是在输入法候选框里显示的名称

  ![](pictures/TUI/provider.png)

  配置可用之后右侧会出现`可用模型`列表，回车确定此配置使用的模型。会思考的模型后面带 `🧠`，在模型上按 `t` 选思考档位（关闭 / 开启 / low / medium / high / max 等，按模型分别记住）。档位表来自 [models.dev](https://models.dev) 的模型目录：本机装了 Miyu 就直接复用它的缓存，否则首次打开时自动下载并缓存一天，也可以用 `rime-llm-config catalog` 手动刷新；目录里没有的模型按厂商族（DeepSeek、Gemini、MiMo、智谱、OpenRouter、Anthropic）给出默认档位。各家的私有写法（`thinking.type`、`reasoning_effort`、`reasoning.effort`、`output_config.effort`、`deepseek-chat` 与 `deepseek-reasoner` 互换、Anthropic 思考时不传 temperature）在导出 `config.lua` 时解析成每个节点的 `request_extra`，Lua 侧不再识别厂商。`rime-llm-config status` 会把当前节点解析后的请求附加字段打印出来。

- 全局参数配置

  ![](pictures/TUI/prompt2.png)

  这里可以对系统提示词和模型参数进行配置。`历史上下文容量`指的是记录多少之前输入过的内容，用于提高ai的联想质量。

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

2. 删除 `~/.local/share/fcitx5/rime/rime_ice.custom.yaml` 中的四条 patch（如果文件是 init 新建的，直接删文件）：

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
