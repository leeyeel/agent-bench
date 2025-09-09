# agent-bench

## 概览

本仓库用于对比 **Pywen** 与 **Claude Code** 两个 Agent 在 **交互模式** 与 **非交互模式** 下的表现。
主要目标：

* **公平对比**：Prompt 组装、请求时机、响应内容；
* **自动化测试**：批量投喂测试用例；
* **精准控制**：通过 Hooks 与 FIFO 通知机制，可靠判断一轮测试是否完成。

---

## 功能点

* **测试用例目录**：`tests/` 下的 `.txt` 文件，每个文件是一轮测试输入。
* **两种运行方式**：

  * **交互模式**：tmux 分屏，两个 Agent 真正运行在交互 CLI 里，投喂脚本逐条输入。
  * **非交互模式**：直接命令行调用两个 Agent 的批处理接口，逐条读取文件输入并等待进程退出。
* **Case ID 机制**：

  * 用例文件名作为 `case_id`；
  * 交互模式：通过 `UserPromptSubmit` hook 和 Pywen 回调拦截 `CASE_ID`，Stop 时输出 DONE；
  * 非交互模式：进程退出即视为 DONE。

---

## 运行方式

### 1. Docker 运行（推荐）

首先创建环境变量文件 `.env`：

```bash
# 复制环境变量模板
cp .env.example .env
# 根据需要修改 .env 文件中的配置
```

#### 非交互模式（后台运行）：
```bash
docker-compose up agent-bench
```

#### 交互模式（需要用户交互）：
```bash
docker-compose --profile interactive up agent-bench-interactive
```

### 2. 本地运行

#### 安装依赖

* Python ≥ 3.10
* tmux
* pytest（用于部分用例验证）

可选：jq（调试 JSON 时使用）。

---

## 本地交互模式使用

### 1. 配置 Claude Code Hooks

`~/.claude/settings.json`：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/ABS/PATH/TO/scripts/hooks/cc_user_prompt_submit.py"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/ABS/PATH/TO/scripts/hooks/cc_stop_notify.py"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/ABS/PATH/TO/scripts/hooks/cc_stop_notify.py"
          }
        ]
      }
    ]
  }
}
```

### 2. 配置 Pywen 回调

在 Pywen 的“本轮完成”回调中调用：

```python
from scripts.pywen_done_notify import notify_pywen_done
notify_pywen_done(case_id)
```

### 3. 启动自动投喂脚本

```bash
./run_interactive_tmux.sh
```

脚本行为：

1. 启动 tmux 会话，左侧 Claude Code，右侧 Pywen；
2. 开启 **同步输入**；
3. 遍历 `tests/*.txt`，先注入 `CASE_ID=文件名`，再投喂内容并回车；
4. 阻塞等待 Claude & Pywen 各自写 `<CASE_ID> DONE`；
5. 两侧完成 → 自动进入下一条。

tmux 热键：

* `Ctrl-b S` → 切换同步输入开/关；
* `Ctrl-b ←/→` → 切换左右 pane；
* `Ctrl-b :kill-session` → 退出会话。

---

## 本地非交互模式使用

非交互模式下，Claude Code 与 Pywen 都直接作为命令行工具运行，**进程退出即视为一轮测试结束**。
这种方式更适合快速跑通用脚本，不依赖 Hooks。

### 使用方法

`./run_headless.sh`：

行为：

* 遍历 `tests/*.txt`；
* 分别调用 Claude 与 Pywen 的命令行批处理接口（非交互模式）；
* 一轮进程退出即视为测试完成。

---

## 测试用例

`tests/` 目录中提供 5 个循序渐进的测试用例：可自行添加，逐渐复杂
---

## 对比总结

* **交互模式**：

  * 真正模拟实际使用体验；
  * Hooks + FIFO 精准判定一轮结束；
  * 适合研究 agent 的 **对话流程、上下文拼接**。

* **非交互模式**：

  * 更简洁，直接跑批量测试；
  * 一轮进程退出即 DONE；
  * 适合快速 benchmark。
