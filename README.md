# Rollin Ace 公开 API（用户接入文档）

面向接入方的公开 API 文档与示例仓库。本仓库提供两套独立的公开接口，接入方**只需要知道本仓库文档中的域名与接口**，无需关心后端实现：

| 接口 | 域名 | 说明 | 文档 |
|---|---|---|---|
| **直播/重播任务 API** | `https://gateway.yakidev.top`（统一网关） | 管理「棒球速报」的直播 / 重播自动运营任务：创建任务（`live`/`replay`，创建后自动启动）、查询任务状态、关闭任务、查询调用额度 | [docs/API_REFERENCE.md](docs/API_REFERENCE.md) |
| **AI 对战接口（AI Duel API）** | `https://ace.yakidev.top`（客户端域名，直连） | 外部 AI / 机器人服务接入棒球对战房：创建 AI 自对弈房、加入真人对战房（人机，真人建房后服务端通知机器人自动加入）、读取局面与可执行操作、执行比赛动作 | [docs/AI_DUEL_API.md](docs/AI_DUEL_API.md) |

直播/重播任务 API 能力：

- **创建任务**（直播 `live` / 重播 `replay`，创建后自动启动）
- **查询任务状态**（轮询是否结束 / 出错）
- **关闭任务**（回收资源）
- **查询调用额度**（创建前确认自身额度是否充足）

AI 对战接口能力：

- **创建 AI 对战房**（AI vs AI 自对弈，立即开局）
- **加入真人对战房**（人机对战，默认客队席位）
- **机器人服务接入**（真人建房开启 AI 对战 → 服务端 `duel_created` 通知 → 机器人自动加入并走棋）
- **读取完整局面**（比分/出局/垒位/当前进攻方/轮到谁/可执行操作）
- **执行比赛操作**（掷骰 / 看·打 / 二选一 / 使用技能 / 切换好坏球）

---

## 快速开始

### 1. 获取凭证

请求时携带以下任一凭证：

- **方式 A（注册制，推荐）**：向服务方申请注册，获得 `cliId` + `secret`
- **方式 B（JWT）**：`Authorization: Bearer <token>`

> 凭证由服务方签发，请妥善保管，**禁止硬编码进前端或提交到代码仓库**。凭证明文泄露请立即联系服务方轮换。

### 2. 调用第一个接口

```bash
BASE=https://gateway.yakidev.top
CLI_ID=<your-cli-id>
CLI_SECRET=<your-cli-secret>

# 创建一场重播任务
curl -s -X POST "$BASE/v1/rollinace-api/live/tasks" \
  -H "Content-Type: application/json" \
  -H "X-Cli-Id: $CLI_ID" \
  -H "X-Cli-Secret: $CLI_SECRET" \
  -d '{"gameId":"2021039309","board":"npb","mode":"replay"}'
```

成功返回：

```json
{ "code": 0, "taskId": "8f3a9c2e1b6d", "matchId": "L76HNWWV" }
```

> `matchId` 为直播间 ID，由服务端建房间后**异步回填**：创建请求返回时可能尚未就绪（此时为空字符串），可在后续查询任务状态接口时获取。

> **判断成功以 `code == 0` 为准，不要只看 HTTP 状态码。**

### 3. 管理任务

```bash
TASK_ID=8f3a9c2e1b6d

# 查询状态
curl -s "$BASE/v1/rollinace-api/live/tasks/$TASK_ID" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"

# 关闭任务（幂等，可重复调用）
curl -s -X DELETE "$BASE/v1/rollinace-api/live/tasks/$TASK_ID" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"

# 创建前确认自身额度是否充足
curl -s "$BASE/v1/rollinace-api/live/quota" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"
```

### 4. AI 对战接口（自对弈最小流程）

```bash
BASE=https://ace.yakidev.top
AI_AGENT_ID=<agent_id>      # agent 凭证（管理端「AI 管理」页分配）
AI_AGENT_KEY=<agent_key>    # agent 密钥（key 仅创建/重置时显示一次）

# 创建 AI 自对弈房（3 局制），得到 home/away 两把 key
ROOM=$(curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"create","agentId":"'"$AI_AGENT_ID"'","key":"'"$AI_AGENT_KEY"'","innings":3,"startInning":3}')
echo "$ROOM" | jq .
KEY_AWAY=$(echo "$ROOM" | jq -r '.keys[] | select(.side=="away") | .key')

# 客场先攻：读取局面 + 可执行操作
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"state","key":"'"$KEY_AWAY"'"}' | jq '{myTurn,allowedActions,version}'

# 轮到我时执行一步（掷骰）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"act","key":"'"$KEY_AWAY"'","op":"roll"}' | jq '{ok,event,result,allowedActions}'
```

> 换边与比赛结束由服务端自动推进，AI 只需按 `allowedActions` 循环 `state`/`act`。
> 完整说明见 [docs/AI_DUEL_API.md](docs/AI_DUEL_API.md)。

### 4.5 机器人服务接入（人机对战）

真人端「创建对战 → 开启 AI 对战」建房后，服务端会 **HTTP 通知机器人服务**，机器人服务
收到通知后自动加入对局并走棋：

```
真人建房(aiOpponent:true) ──POST 通知──▶ 机器人服务 ──/api/ai join──▶ 占客队席位、自动开局（客场先攻）
                                                                    └─▶ state/act 循环走棋直至结束
```

**通知契约**：`POST` + `Content-Type: application/json`，默认地址 `https://yakidev.top`
（服务方可用环境变量 `BOT_SERVICE_URL` 覆盖），5 秒超时、无重试；通知失败不阻断建房。
请求体：

```json
{
  "event": "duel_created",
  "env": "prod",
  "liveId": "ABCD1234", "type": "duel", "ai": true,
  "aiSides": ["away"], "homeUid": "主队完整uid", "homeName": "主队",
  "awayName": "AI客队", "duelInnings": 9, "startInnings": 9,
  "matchStatus": "waiting", "createdAt": 1756500000000
}
```

**`env` 是来源环境，机器人服务必须按它选择目标环境**（各环境的 `/api/ai` 基址与 agent 凭证相互独立）：

| 值 | 含义 | 服务端判定（接入方无需配置） |
|---|---|---|
| `glb` | 国际版环境 | 国际版部署（`IS_GLB=1`）；国际版无测试环境，优先级最高 |
| `test` | 测试环境 | 非国际版且测试部署（`IS_DEV=1`） |
| `prod` | 正式环境 | 其余（正式部署） |

收到通知后（先按 `env` 选定目标环境的基址与 agent 凭证）：
`POST /api/ai { action:"join", agentId, key, liveId, name:"AI客队" }`
占用客队席位 → 自动开局 → 按 `state`/`act` 循环走棋。
通知丢失时可用 `action:"list"` 主动拉取可加入的房间兜底。
可运行示例见 [examples/node/bot_server_demo.mjs](examples/node/bot_server_demo.mjs)。

---

## 接口总览

### 直播/重播任务 API（前缀 `/v1/rollinace-api/live`）

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST` | `/v1/rollinace-api/live/tasks` | 创建任务（直播/重播，创建后自动启动） |
| `GET` | `/v1/rollinace-api/live/tasks/{taskId}` | 查询任务状态 |
| `DELETE` | `/v1/rollinace-api/live/tasks/{taskId}` | 关闭任务（幂等） |
| `GET` | `/v1/rollinace-api/live/quota` | 查询调用额度与开放中用量 |

### AI 对战接口（`POST https://ace.yakidev.top/api/ai`，直连客户端域名）

| action | 鉴权 | 说明 |
|---|---|---|
| `session` | agentId + key | 为已有房间签发 / 重签 session_key |
| `create` | agentId + key | 创建 AI 对战房（`aiSides` 指定 AI 接管席位），返回各席位 key |
| `join` | agentId + key | 加入已有对战房（默认客队席位，客场先攻） |
| `list` | agentId + key | 列出**可加入的对战房**（含 `openSides` / `joinable`，供 AI 自主挑选房间） |
| `state` | key | 读取当前局面 + `allowedActions` + `toMove`/`myTurn` + `version` |
| `act` | key | 执行操作：非法返回错误码与合法动作；成功返回最新局面与事件 |
| `chat` | key | 以房间身份发送弹幕（与真人端共享同一份日志流） |
| `log` | key | 读取房间日志 / 聊天（`type:"chat"` 只读弹幕，支持 `since` 增量） |
| `heartbeat` | key | 保活（state/act 也会顺带刷新） |
| `leave` | key | 退出房间并撤销 key |

> 换票（`session`/`create`/`join`/`list`）用管理端分配的 `agentId`+`key`（body 或 `X-Agent-Id`+`X-AI-Key` 请求头）；会话（`state`/`act`/`chat`/`log`/`heartbeat`/`leave`）用换票返回的 `key`（与房间 + 阵营绑定，24h 滑动续期）。
> 换边与比赛结束由服务端自动推进，AI 只需按 `allowedActions` 循环 `state`/`act`。
> 人机对战（机器人服务）：真人建房开启 AI 对战（`aiOpponent:true`）后，服务端 POST 通知
> 机器人服务（`duel_created`），机器人服务收到后经 `join` 加入客队并自动开局（见上文 4.5）。
> 完整说明见 [docs/AI_DUEL_API.md](docs/AI_DUEL_API.md)。

---

## 建议的接入流程

### 直播/重播任务 API

1. 联系服务方注册 `cliId` 并获取 `secret`；
2. 先用 `GET .../quota` 确认自身直播/重播额度（`maxLive`/`maxReplay`）是否充足；
3. 用 `gameId` + 已知的 `board`/`mode` 调 `POST .../tasks` 创建任务，保存返回的 `taskId`；
4. 定时（建议间隔 ≥10s）调 `GET .../tasks/{taskId}` 查看 `status`；
5. 业务结束或需要中止时，调 `DELETE .../tasks/{taskId}` 关闭；
6. `mode=replay` 时**不要**设置 `loop=true`（会被拒绝）；重播直接传 `mode=replay`。

### AI 对战接口

1. 联系服务方在管理端「AI 管理」创建 agent，获得 `agent_id` 与 `key`（key 仅显示一次，请妥善保存）；
2. 自对弈：`create` 建房（`aiSides:["home","away"]`），用返回的两把 `key` 循环 `state`/`act`；
3. 人机对战（主动建）：`create` 时 `aiSides:["away"]`，主队留给真人；
4. 人机对战（机器人服务被动接入）：部署 HTTP 回调接收 `duel_created` 通知（默认地址
   `https://yakidev.top`，由服务方配置 `BOT_SERVICE_URL` 指向你的服务），**按通知里的 `env`
   选定目标环境**（`prod`/`test`/`glb` 的基址与凭证相互独立），收到后经 `join`
   占用客队席位并自动开局（可运行示例见 `examples/node/bot_server_demo.mjs`）；
5. 通知丢失或想接管任意等待中的房间：`list` 列出可加入房间（建议 `aiOnly:true`），
   挑 `joinable` 的房间自行 `join`；
6. 每次行动前先 `state`，仅当 `myTurn===true` 且 `allowedActions` 非空时 `act`；
7. 想与真人互动：`log`（`type:"chat"`）读弹幕 + `chat` 发弹幕，与真人端同一份日志流；
8. `act` 失败（`ok:false` + `reason`）时按响应中的 `allowed` 自我纠正；
9. 轮询间隔建议 ≥1s；比赛结束以 `matchStatus==="ended"` 为准；
10. 会话结束时调 `leave` 撤销 key；不调也不影响（24h 自动过期）。

---

## 仓库结构

```
ra_client_api/
├── README.md                      # 本文档（快速上手）
├── docs/
│   ├── API_REFERENCE.md           # 直播/重播任务：完整接口参考（字段/错误码/状态表）
│   ├── AI_DUEL_API.md             # AI 对战接口：完整接口文档（鉴权/状态机/动作/错误码）
│   └── USAGE_EXAMPLES.md          # 多语言使用用例（curl / Python / Node）
├── examples/
│   ├── bash/
│   │   ├── full_lifecycle.sh      # 直播/重播任务：完整生命周期示例
│   │   └── ai_duel_demo.sh        # AI 对战：自对弈示例
│   ├── python/task_demo.py        # Python 示例
│   └── node/
│       ├── task_demo.mjs          # 直播/重播任务：Node.js 示例
│       └── bot_server_demo.mjs    # AI 对战：机器人服务示例（收通知→join→走棋）
└── skills/
    ├── rollinace-api-client/          # Agent Skill：直播/重播任务 API
    └── rollinace-ai-duel-client/      # Agent Skill：AI 对战接口
```

- 直播/重播任务完整接口明细见 [docs/API_REFERENCE.md](docs/API_REFERENCE.md)。
- AI 对战接口完整说明见 [docs/AI_DUEL_API.md](docs/AI_DUEL_API.md)。
- 多语言使用用例见 [docs/USAGE_EXAMPLES.md](docs/USAGE_EXAMPLES.md) 与 [examples/](examples/)。
- 供其他 AI Agent 调用的 Skill：直播/重播任务见 [skills/rollinace-api-client/](skills/rollinace-api-client/SKILL.md)，AI 对战接口见 [skills/rollinace-ai-duel-client/](skills/rollinace-ai-duel-client/SKILL.md)。

---

## 内容与安全说明

- 本仓库为**公开文档仓库**，只包含公开契约（直播/重播任务：`https://gateway.yakidev.top/v1/rollinace-api/live/*`；AI 对战接口：`https://ace.yakidev.top/api/ai`），**不包含**任何内部路径、源站地址或密钥。
- 请勿在本仓库中提交任何真实凭证、密钥或 `.env` 文件（已通过 `.gitignore` 拦截常见情况）。
- 直播/重播任务鉴权失败统一返回 `HTTP 401`：`{ "error": "unauthorized" }`。
- AI 对战接口鉴权失败返回 `401 unauthorized`；跨房越权返回 `403 session_mismatch`；业务失败多为 HTTP 200 + `{ "ok":false, "reason":... }`，**以 `ok===true` 判断成功**。
