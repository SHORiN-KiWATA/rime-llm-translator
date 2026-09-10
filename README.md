# rime-llm-translator

给Rime输入法接入大模型进行拼音联想，支持TUI图形化配置。平时正常输入，在遇到长难句或者生僻句的时候通过双击v键呼叫Ai对拼音进行处理。输入的时候不太需要考虑输入的拼音是否正确，大模型强大的预测功能会自动把误拼甚至乱序处理成正确的句子。对于句子中的英文词汇也能正常处理，甚至还能补充正确的空格和标点符号。

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

    > 配置文件在修改前会备份至`~/.cache/rime-llm-translator/backup/`
    
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

**问长问题不会卡死输入法。** Lua 那边是同步等待，等多久输入法就冻多久，所以设了两道时间：

| 设置 | 默认 | 作用 |
|---|---|---|
| 输入法等待 | 25 秒 | 到点还没答完就放行，候选变成 `⏳ 已转后台` |
| 回复超时 | 300 秒 | 交给 Miyu 的实际上限，到点取消 |

转后台之后答案用桌面通知送达，同时落一份到 `~/.cache/rime-llm-translator/last_chat.txt`。想回到一直等的老行为，把「输入法等待」设成不小于「回复超时」就行。
- 需要 Miyu 的 `ask` 支持 `--output-format` 和 `--session`（0.5.0 之后的程序驱动 CLI）。太旧的版本会被挡下并提示升级，不会把请求发出去。
- 本机同时装了包管理器版和自编译版时，会自动挑够新的那个：设置里指定的路径 → PATH → `~/.local/bin` → `/usr/local/bin` → `/usr/bin`。fcitx5 拉起的进程 PATH 里常常没有 `~/.local/bin`，所以这一步不能只信 PATH。
- 设置在 `rime-llm-config` 主菜单的「跟 Miyu 聊天」里：聊天前缀（**留空即关闭此功能**）、会话名、回复超时、输入法等待、是否允许她用工具、miyu 路径、宿主指令。
- 终端里 `rime-llm-config chat "nihao"` 可以直接试，`rime-llm-config status` 会显示当前前缀、会话和选中的 miyu 路径。

## 省 token

每按一次触发键就是一次完整请求，固定开销全在系统提示词上。程序把提示词拆成**常驻核心**和**按需片段**两截，只发用得上的那部分：

| | 旧行为 | 现在 |
|---|---|---|
| 普通一句拼音 | 提示词全文 + 整个词库 | 只发核心（约 450 字） |
| `jp:` / `call:` 等带前缀 | 同上 | 核心 + 命中的那一条前缀规则 |
| 多个前缀（`jpmoe:`） | 同上 | 核心 + 命中的几条 + 组合规则 |
| 自定义词库 | 每次全发 | 只发正文里真出现的条目 |

`# 特殊行为`那一整段（各前缀的定义 + 组合规则）占了提示词的六成，可绝大多数输入是不带前缀的纯拼音，根本用不上，所以它只在输入真带了某个前缀时才贴回去。词库同理，`mrfz` 只在拼音里出现 `mrfz` 时才发——**词库规模从此和单次成本脱钩，想加几百条都不涨价**。

> 前缀规则不再写在提示词里，是独立的配置，见下面的「前缀行为」一节。

**别把缓存前缀搞坏。** DeepSeek、OpenAI 的自动前缀缓存和 Anthropic 的 `cache_control` 都要求前缀逐字节一致，所以按需内容一律**追加在核心之后**，核心永远是同一串字节。Anthropic 线还会给核心块打上 `cache_control`（命中按 0.1x 计价）；有中转不认 `system` 的数组写法，把「标记提示词可缓存」关掉即可退回纯字符串。

另外几处：

- **上文**：`call:` / `cmd:` / `sh:` 是在提问，之前打过的字是噪音，这几个前缀不带上文（可在设置里改）。
- **输出上限**（默认关）：`max_tokens` 是上限不是预留额，正常情况按实际生成的量计费，所以这一条**省不到 token**，只是模型跑飞时的止损。开了之后无前缀的纯转换按拼音长度给上限（下限 512），带前缀和配了思考档的节点仍用配置值。风险是实打实的：不少模型默认就会思考，思考 token 也算在 `max_tokens` 里，额度小了会在吐出正文之前被截断（实测 opencode zen 的 `big-pickle` 就这样返回空）。想开就自己确认模型不吃这一套。
- **失败不重复付钱**：请求失败进 5 秒负缓存，Rime 重建候选菜单时不会把同一个失败请求反复发出去。
- **跨会话缓存**：同一句拼音再打一遍直接命中，0 token，候选注释显示 `·缓存`。只收无前缀、够长（默认 ≥8 个字母）的纯转换结果——`ta`、`shi` 这种换个上下文就是另一个词，缓存住反而是错的；`call:` 这类每次都该重新生成。存在 `~/.cache/rime-llm-translator/replies.json`。

### 看效果

```
rime-llm-config usage           # 累计请求数、输入/输出 token、缓存命中率、最近 10 次
rime-llm-config usage --reset   # 清零重新数
```

数字取自每次响应里的 `usage` 字段（DeepSeek 的 `prompt_cache_hit_tokens`、OpenAI 系的 `prompt_tokens_details.cached_tokens`、Anthropic 的 `cache_read_input_tokens` 都认），`rime-llm-config debug` 的日志里也会逐条记录。

以上开关都在 `rime-llm-config` 主菜单的「省 token 与缓存」里。程序自带的默认提示词也按这套结构重写过（1514 字 → 899 字），老用户的提示词不会被动；想换成新版：菜单里勾「恢复精简版默认提示词」，或者 `rime-llm-config reset-prompt`（会先备份 `state.json`）。

## 前缀行为

`jp:woshizhongguoren` → 私は中国人です。冒号前面那几个字母决定这次要模型做什么。

以前这些规则是写在提示词里的几行字，程序不认识它们。现在**程序要按前缀决定注入什么**，前缀就成了一等公民，所以拆成了独立配置：`rime-llm-config` 主菜单 →「前缀行为」。

- **前缀规则**：一张 `前缀 → 规则` 的表，加一条 `kr:` 就是加一条，不用管 markdown 格式。
- **前缀组合规则**：讲 `jpmoe:` 这类组合怎么理解，只在一次命中两个及以上前缀时才发。
- **未知前缀兜底**：遇到表里没有的前缀（`kr:` `fr:`）发这一条，`{p}` 会被替换成实际的前缀。留空则关闭。
- **规则注入位置**：见下。

> 老配置会**自动迁移**：第一次运行时把提示词里的规则段切出来填进这张表，提示词只留核心，`state.json` 先备份。你自己改过措辞的规则原样保留，没改过的（跟自带版本一字不差）换成重写后的版本。

### 规则写法：约束输出，别描述过程

这是实测踩出来的坑。老的 `jp:` 规则是「将拼音转换成中文**再次翻译**为日文后输出」——字面上就是两步，模型会老老实实把两步都输出：

```
jp:wwoxiangchishousi  →  我想吃寿司
                          私は寿司が食べたいです     ← 中间结果也上屏了
```

改成「**只输出**日文译文。不要输出中间的中文」之后，同样的输入 6/6 干净。自带的七条规则都按这个原则重写过了。

### 规则注入位置

同一条规则放在上下文的不同位置，约束力差很多。实测（deepseek-flash，`jp:` `kr:` `eng:` `cmd:` 共 33 次采样）：

| 位置 | 命中 | 说明 |
|---|---|---|
| 输入之后（默认） | **33/33** | 规则紧跟在拼音后面 |
| 输入之前 | 27/33 | |
| 系统提示词末尾 | 12/15 | 未知前缀兜底几乎完全失效 |

差距集中在**没有预定义规则的前缀**上。`kr:woshizhongguoren` 这一条，规则放输入前 6 次错 5 次，放输入后 6 次全对——开头那句「你是中文拼音输入法引擎」定性太强，规则离输入越远越压不住。已经预定义好的 `jp:` `eng:` 三种位置都是满分，所以你要是只用自带的那几个前缀，这一项怎么设都行。

顺带一个好处：规则放进 user 消息之后，**system 就只剩恒定的核心了**，缓存前缀稳定性拉满。

## 编辑配置

`rime-llm-config`是编辑配置的TUI工具。TUI 里每次保存都会顺手把 `config.lua` 导出一遍，HTTP 线（读 `config.lua`）和 CLI 线（读 `state.json`）用的提示词和词库因此始终一致。

> 如果你要手动编辑配置文件请编辑`~/.config/rime-llm-translator/state.json`后用`rime-llm-config sync`命令同步至`config.lua`。每个节点可用的字段：`protocol`（`auto` / `openai-chat` / `anthropic` / 各 CLI）、`api_url`、`api_key`、`model`、`thinking`（按模型存档位 id，如 `{"deepseek-v4-flash": "max"}`）、`extra_body`（原样并进请求体的私有字段）、`model_temperature`（按模型覆盖发散度）。全局设置里跟 Miyu 聊天相关的字段：`miyu_prefix`、`miyu_session`、`miyu_timeout`、`miyu_wait`、`miyu_tools`、`miyu_binary`、`miyu_prompt`。全局设置里跟省 token 相关的字段：`prefix_inject`、`vocab_inject`（`auto` 按需 / `always` 全发）、`no_history_prefixes`、`adaptive_max_tokens`、`prompt_cache_mark`、`reply_cache_disk`、`reply_cache_min_len`、`reply_cache_max`。前缀行为是顶层的 `prefixes` 对象：`rules`（`[{key, rule}, …]`，有序）、`combo`、`fallback`（含 `{p}` 占位符），注入位置是 `settings.prefix_position`（`user_after` / `user_before` / `system`）。


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
