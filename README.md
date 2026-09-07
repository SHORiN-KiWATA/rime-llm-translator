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
    
    - 新建`rime.lua`导入`llm_translator`；
    
      ```
      llm_translator = require("llm_translator")
      ```
      > 如果已经存在的话会备份后在文件末尾追加
    
    - 如果检测到安装了雾凇拼音的话会新建`rime_ice.custom.yaml`写入patch，启用llm_translator并配置一些上屏规则；

      ```
      patch:
        # 1. 扩充允许输入的字符集：允许在拼音中直接输入指定的标点符号，阻止其直接上屏
        "speller/alphabet": "zyxwvutsrqponmlkjihgfedcba.,?'!:<>\\/"
        # 2. 将 Lua AI 脚本 (llm_translator) 强行插入到处理列表的第 0 位之前
        "engine/translators/@before 0": lua_translator@llm_translator
        # 3. 定义正则捕获规则：把输入当成不可分割的整体喂给 AI 脚本处理
        "recognizer/patterns/llm_pinyin": "^[a-z][a-z.,?'!:<>/\\\\]*$"
      ```

    - 如果fcitx5正在运行的话，重启以重新部署。
    
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
- 装了 [Miyu](https://github.com/SHORiN-KiWATA/Miyu) 的话，会顺带只读导入 Miyu 里配好的供应商，显示为 `[Miyu]` 节点（id 前缀 `miyu_`，列表里排在自己的节点和 `[CLI]` 节点之后），改了 Miyu 的配置下次打开自动同步；这类节点只能在这里改模型和思考强度。
- CLI 节点的编辑表单里可以改可执行文件路径和思考强度（关闭 / 低 / 中 / 高，对应各家的 effort 参数）。
- 每次请求是一次性的，不带会话、不开工具、不写磁盘。CLI 线比直连 HTTP 慢：实测 claude sonnet 约 3 秒，codex / agy / opencode 约 7~10 秒，超时可在「全局参数设置 → CLI 后端超时」调整（默认 60 秒）。
- Lua 侧走 CLI 时是调用 `rime-llm-config ask` 完成请求的，`rime-llm-config ask "拼音"` 也可以在终端里直接用来排查问题；`rime-llm-config debug` 的日志同样会记录 CLI 线的请求。

## 编辑配置

`rime-llm-config`是编辑配置的TUI工具。

> 如果你要手动编辑配置文件请编辑`~/.config/rime-llm-translator/state.json`后用`rime-llm-config sync`命令同步至`config.lua`


![](pictures/TUI/mainmenu.png)

- 激活配置

  此处可以设置具体使用哪一个配置

  ![](pictures/TUI/active.png)

- 供应商和模型

  ![](pictures/TUI/edit.png)

  最左侧一列是供应商（同时也是配置），回车可以配置供应商的显示名称、api地址、api密钥等内容，部分模型支持开关思考模式。

  > 显示名称指的是在输入法候选框里显示的名称

  ![](pictures/TUI/provider.png)

  配置可用之后右侧会出现`可用模型`列表，回车确定此配置使用的模型。

- 全局参数配置

  ![](pictures/TUI/prompt2.png)

  这里可以对系统提示词和模型参数进行配置。`历史上下文容量`指的是记录多少之前输入过的内容，用于提高ai的联想质量。

- 自定义词库

  ![](pictures/TUI/vocab.png)

  这里可以自定义词库。`常用英文词`是为了避免ai把句子中的英文视为拼音进行分词；`拼音缩写映射`可以提高首字母缩写、简拼的联想质量。

  ![](pictures/TUI/vocab3.png)

## 移除该功能

1. 删除 `~/.local/share/fcitx5/rime/rime.lua` 中的这一行（如果文件里只有这一行，直接删文件）：

    ```
    llm_translator = require("llm_translator")
    ```

2. 删除 `~/.local/share/fcitx5/rime/rime_ice.custom.yaml` 中的三条 patch（如果文件是 init 新建的，直接删文件）：

    ```
      # 1. 扩充允许输入的字符集：允许在拼音中直接输入指定的标点符号，阻止其直接上屏
      "speller/alphabet": "zyxwvutsrqponmlkjihgfedcba.,?'!:<>\\/"
      # 2. 将 Lua AI 脚本 (llm_translator) 强行插入到处理列表的第 0 位之前
      "engine/translators/@before 0": lua_translator@llm_translator
      # 3. 定义正则捕获规则：把输入当成不可分割的整体喂给 AI 脚本处理
      "recognizer/patterns/llm_pinyin": "^[a-z][a-z.,?'!:<>/\\\\]*$"
    ```

    > init 之前的原文件备份在 `~/.cache/rime-llm-translator-backup/`，直接覆盖回去也可以。

3. 移除缓存、配置和软件包：

    ```
    gio trash ~/.config/rime-llm-translator ~/.cache/rime-llm-translator ~/.cache/rime-llm-translator-backup
    yay -Rns rime-llm-translator-git
    ```

4. 重启 fcitx5（或在托盘菜单点「重新部署」）让 Rime 重新部署。
