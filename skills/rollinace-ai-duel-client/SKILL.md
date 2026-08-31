---
name: rollinace-ai-duel-client
description: 让外部 AI Agent / 机器人服务接入 Rollin Ace 棒球对战房。通过公开接口 /api/ai 创建 AI 对战房（AI vs AI 自对弈）、加入对战房（人机对战，含接收 duel_created 通知后自动 join 加入的机器人服务接入）、列出可加入的对战房、读取完整局面与当前可执行操作、执行比赛操作（掷骰 / 看·打 / 二选一 / 使用技能 / 切换好坏球）、收发房间聊天、保活与退出。当用户需要让 AI 打棒球对战、实现 AI 自对弈或人机对战、实现接收建房通知并自动对局的机器人服务、或需要按局面自动决策并执行比赛动作时，应使用本技能。
---

# Rollin Ace AI 对战接口客户端

## 何时使用

当用户需要将 AI / 外部策略程序接入「棒球对战房」时使用本技能，典型场景：

- 创建 AI 对战房（AI vs AI 自对弈，`create`）；
- 加入对战房（人机对战，`join`）；
- 主动发现可接管的对局（列出可加入的对战房，`list`）；
- 读取房间聊天与系统日志（含真人弹幕，`log`，与 `chat` 形成收发闭环）；
- 部署机器人服务：真人建房开启 AI 对战 → 服务端 HTTP 通知（`duel_created`）→ 收到后自动 `join` 加入客队并走棋；
- 读取当前完整局面（比分、出局、垒位、当前进攻方、轮到谁、可执行操作，`state`）；
- 执行比赛操作（掷骰 `roll` / 打 `swing` / 看 `read` / 二选一 `take1B`、`roll2` / 使用技能 `item` / 切换好坏球 `setBS`，`act`）；
- 以房间身份发送弹幕（`chat`，与真人端共享同一份日志流）；
- 保活与退出（`heartbeat` / `leave`）。

本技能只使用**公开契约**，请求直连客户端域名 `https://ace.yakidev.top`，路径 `/api/ai`。不要使用任何内部路径或源站地址。

## 前置条件

- agent 凭证：`agent_id` + `key`（由服务方在管理端「AI 管理」页创建 agent 获得；**key 仅创建/重置时显示一次**，服务端只存哈希，无法再查询）。
- 凭证获取方式（按优先级）：
  1. 环境变量 `AI_AGENT_ID` / `AI_AGENT_KEY`；
  2. 直接询问用户提供；
  3. 若用户声称已申请但无法提供，提示用户联系服务方获取，不要编造凭证。
- 凭证**禁止**写入代码或提交到仓库；建议通过环境变量或临时变量传入。
- 换票（`session`/`create`/`join`）携带 `agentId`+`key`（body 或请求头 `X-Agent-Id`+`X-AI-Key`）；换票成功后获得 `key`（session_key，与房间 + 阵营绑定，24 小时滑动续期），后续 `state` / `act` / `chat` / `heartbeat` / `leave` 使用。

## 接口总览

| action | 鉴权 | 说明 |
|---|---|---|
| `session` | agentId + key | 为已有房间签发 / 重签 session_key（side 省略时自动挑空席，先 away 后 home） |
| `create` | agentId + key | 创建 AI 对战房（`aiSides` 指定由 AI 接管的席位），返回各席位 key |
| `join` | agentId + key | 加入已有对战房（默认客队席位，客场先攻），返回 key |
| `list` | agentId + key | 列出**可加入的对战房**（含 `openSides` / `joinable`，供 AI 自主挑选房间） |
| `state` | key | 读取当前局面 + `allowedActions` + `toMove`/`myTurn` + `version` |
| `act` | key | 执行操作：非法返回错误码与合法动作；成功返回最新局面与事件 |
| `chat` | key | 以房间身份发送弹幕（与真人端共享同一份日志流） |
| `log` | key | 读取房间日志 / 聊天（`type:"chat"` 只读弹幕，支持 `since` 增量） |
| `heartbeat` | key | 保活（state/act 也会顺带刷新） |
| `leave` | key | 退出房间：移出在线名单并撤销 key |

## 操作指南

以 curl 为例（`BASE=https://ace.yakidev.top`，`AI_AGENT_ID`/`AI_AGENT_KEY` 为管理端分配的 agent 凭证，`KEY` 为 session_key）：

### 创建 AI 自对弈房

```bash
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" -d '{
  "action":"create","agentId":"$AI_AGENT_ID","key":"$AI_AGENT_KEY",
  "homeName":"AI主队","awayName":"AI客队","innings":9,"startInning":9,
  "aiSides":["home","away"],"stream":false
}'
```

必填字段：

- `agentId` + `key`：管理端分配的 agent 凭证（也可用请求头 `X-Agent-Id` + `X-AI-Key`）。

可选字段：

- `homeName` / `awayName`：队名（缺省 `AI主队` / `AI客队`）；
- `innings`：总局数 1~9（默认 9）；
- `startInning`：开局位置（默认等于 `innings`）；
- `aiSides`：由 AI 接管的席位数组（默认 `["home","away"]` 自对弈；`["away"]` 表示主队留给真人）；
- `stream`：是否出现在直播大厅（默认 `false`，避免污染大厅）；
- `liveId`：指定房间号（缺省自动生成 8 位）。

成功响应返回 `ok:true`、`liveId`、`aiSides`、`matchStatus`、`agentId` 与 `keys`（每席位的 `side`/`key`/`expiresAt`/`uid`/`agentId`）。

> **仅 `aiSides` 同时含 home 与 away 时才立即开局**（客场先攻）；否则 `matchStatus` 为 `waiting`，等真人主队进房初始化。

### 机器人服务接入（人机对战）

真人端「创建对战 → 开启 AI 对战」建房（`aiOpponent:true`）后，服务端会 **HTTP 通知机器人服务**，
机器人服务收到通知后经 `join` 加入客队并自动开局（客场先攻），随后按 `state`/`act` 循环走棋。

**通知契约（机器人服务需实现一个 HTTP 回调）：**

| 项 | 值 |
|---|---|
| 方式 | `POST`，`Content-Type: application/json` |
| 地址 | 默认 `https://yakidev.top`；服务方可用环境变量 `BOT_SERVICE_URL` 覆盖 |
| 超时 | 5 秒，无重试；通知失败不阻断建房（可用 `list` 主动轮询兜底） |

请求体（`event:"duel_created"`）：

```json
{ "event": "duel_created", "env": "prod",
  "liveId": "ABCD1234", "type": "duel", "ai": true,
  "aiSides": ["away"], "homeUid": "主队完整uid", "homeName": "主队", "awayName": "AI客队",
  "duelInnings": 9, "startInnings": 9, "matchStatus": "waiting", "createdAt": 1756500000000 }
```

**`env` 是来源环境，机器人服务必须按它选择目标环境**（`/api/ai` 基址与 agent 凭证按环境隔离）：

| 值 | 含义 | 服务端判定（接入方无需配置） |
|---|---|---|
| `glb` | 国际版环境 | 国际版部署（服务方 `IS_GLB=1`）；国际版无测试环境，优先级最高 |
| `test` | 测试环境 | 非国际版且测试部署（`IS_DEV=1`） |
| `prod` | 正式环境 | 其余（正式部署） |

用错环境的凭证会 `401 unauthorized`，或连到错误的环境。

收到通知后接入流程：

```bash
# 1) 先按 env 选定目标环境的 BASE 与该环境的 agent 凭证
# 2) join：占用客队席位（自动开局、客场先攻）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" -d '{
  "action":"join","agentId":"$AI_AGENT_ID","key":"$AI_AGENT_KEY","liveId":"ABCD1234","name":"AI客队"
}'
# 3) 之后按上文 state/act 循环走棋（key 用 join 返回的 session_key）
```

**主动发现（通知丢失 / 想接管任意等待中的房间时）：** 用 `list` 拉取可加入房间，
自行挑选后 `join`（见下方「列出可加入的对战房」）。

> join 失败（`seat_taken` / `duel_ended`）时房间保持 `waiting`，可稍后重试。
> 可运行示例：`examples/node/bot_server_demo.mjs`（收通知 → join → 走棋全流程）。

### 列出可加入的对战房（主动发现）

```bash
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" -d '{
  "action":"list","agentId":"$AI_AGENT_ID","key":"$AI_AGENT_KEY","aiOnly":true,"limit":20
}'
```

- `aiOnly`：`true` 只返回 AI 房（**建议**，避免抢占真人等好友的房间）；`false` 时普通对战房也返回（AI 可「假装玩家」加入）。
- `joinable`：`false` 返回全部对战房（含满席 / 已结束，`joinable:false`）；默认只返回可加入的。
- `limit`：返回条数，默认 50、上限 200，按创建时间倒序（新房在前）。

每项含 `openSides`（当前空席 `home`/`away`）、`joinable`、`ai` / `aiSides`、`matchStatus`、`ageSec`
（创建至今秒数，可用于优先接管等待最久的房间）。挑中后 `join` 占位；
多机器人并发时先到先得，后者返回 `409 seat_taken`，按 `list` 结果重新挑选即可。
只读、不修改房间状态，可放心轮询（建议 ≥3s）。

### 读取当前局面

```bash
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"state","key":"$KEY"}'
```

响应含 `situation`（完整局面）、`toMove`（当前进攻方）、`myTurn`（是否轮到我）、`allowedActions`（当前可执行操作）、`version`（最新帧序号，乐观锁用）、`agentId`、`matchStatus`、`roomStatus`、`winner` 等。

**判断是否该行动**：`matchStatus==="live"` 且 `myTurn===true` 且 `allowedActions` 非空时才执行 `act`。`allowedActions` 为空且轮不到我 → 等待；`duelEnd==="half"` → 服务端正在自动换边，稍后重试。

### 执行操作

```bash
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" -d '{
  "action":"act","key":"$KEY","op":"roll","expectVersion":1756499123456
}'
```

- `op`：`roll` / `swing` / `read` / `take1B` / `roll2` / `item` / `setBS` / `init`；
- `itemId`：`op=item` 时必填（`bat` / `steal` / `sac` / `mist` / `lun` / `ling`）；
- `bsEnabled`：`op=setBS` 时必填（切换好坏球模式，新打席生效）；
- `expectVersion`：可选乐观锁，与当前 `version` 不一致时返回 `version_conflict`（防重复提交）。

成功响应返回最新 `situation`、`event`（中文描述）、`result`（如 `2B`/`HR`/`OUT`）、`baseEvents`（结构化跑者事件）、`advanced`（`half` 已自动换边 / `match` 比赛结束 / `null`）、`items`（本席位最新道具背包记账）。

非法操作**也返回 HTTP 200**：`{ "ok":false, "reason":"illegal_op", "allowed":[...], "reasonDetail":"..." }`——按 `allowed` 自我纠正即可。

**使用道具（`op:"item"`）**：AI 接口无前端，技能次数 / 背包由**服务端权威记账**，
随 `state` / `act` 响应返回 `items`（`stock` 剩余库存、`halfUsed` 本半局额度、`batArmed` 棒装备、`rules` 契约常量）。
前置校验失败即拒绝且**不扣库存**（`out_of_stock` / `skills_exhausted` / `already_used`）；引擎 `canUse` 判定不满足 → `condition_failed`。
`bat` 为被动道具（装备后主骰 1B 自动升级 2B，打席结束自动解除）；`ling` 传令成功后重置本半局额度；换边自动重置。详见 `references/api_quick_ref.md`。

> **换边与比赛结束由服务端自动推进**：`act` 检测到 `duelEnd==="half"` 自动重建新半局并翻转进攻权；检测到 `"match"` 自动写 `winner`/`endedAt` 并累计战绩。AI 无需额外调用。

### 发弹幕

```bash
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"chat","key":"$KEY","text":"加油！"}'
```

- `text` 最长 100 字，超长截断；弹幕为空 → `empty_chat`；命中敏感词 → `blocked_content`
  （附 `matches` 命中词条，换一种说法重发）。
- **与真人端共享同一份日志流**：写入房间共享日志（`type="chat"`），真人端 / 观众轮询
  `GET /api/live?liveId=<id>` 即可看到 AI 弹幕，无需任何前端改造。
- 署名规则与真人端一致：对战房内显示**队名**（`AI主队` / `AI客队` 或自定义队名）。
- 发弹幕顺带刷新该阵营在线心跳（与 `heartbeat` 同效）。

### 读取房间聊天（log）

```bash
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" -d '{
  "action":"log","key":"$KEY","type":"chat","since":1756500000000,"limit":50
}'
```

- `type`：`chat`（只要弹幕）/ `system`（只要系统日志）/ `all`（默认）。
- `since`：只返回 `ts` **严格大于**该值的条目，用于增量轮询；`limit`：取最新 N 条（默认 50、上限 200），结果保持时间正序。
- 响应 `logs:[{ ts, type, text }]`；弹幕 `text` 形如 `{队名}： {正文}`，已含署名（按队名前缀即可区分发言方）。
- 与真人端 `GET /api/live?liveId=<id>` 的 `log` 同源，可据此实现「看到观众说话 → `chat` 回应」的互动闭环。
- 只读；顺带刷新在线心跳（只挂机读聊天不会被判离线）。

### 保活 / 退出

```bash
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" -d '{"action":"heartbeat","key":"$KEY"}'
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" -d '{"action":"leave","key":"$KEY"}'
```

- `state` / `act` / `heartbeat` 均顺带刷新该阵营在线时间，**只轮询 `state` 也不会被判离线**（在线判定沿用 30s 心跳超时）。
- `leave` 移出在线名单并撤销 key；双方均离线且比赛不活跃时房间会被自动回收关闭。

## 关键约定

- 换票（`session`/`create`/`join`/`list`）用 `agentId` + `key`（= 管理端分配的 agent 凭证）；会话（`state`/`act`/`chat`/`log`/`heartbeat`/`leave`）用换票返回的 `key`。
- `key` 与房间 + 阵营绑定：跨房调用返回 403 `session_mismatch`。
- key 有效期 24 小时、**滑动续期**（每次成功调用自动续期）。
- 一切规则结算由**服务端权威引擎**完成，AI 只负责按 `allowedActions` 决策；不要在本地自行推算结果。
- 道具的库存 / 半局额度 / 棒装备由**服务端权威记账**（`state`/`act` 响应中的 `items`），AI 应按 `items` 决策使用，不要本地维护背包。
- 失败应答统一 `{ "ok":false, "reason":... }`（HTTP 200），仅鉴权类错误为 401/403；以 `ok===true` 判断成功。
- AI 每一步操作会自动广播一帧，真人端轮询 `GET /api/live?liveId=<id>` 即可同步观战。
- 服务端按 agent 记录分接口调用量，可在管理端「AI 管理」页查看；请控制轮询频率（建议 ≥1s）。

## 完整参考

接口字段、`allowedActions` 推导规则、`situation` 数据结构、错误码速查表见本技能附带的 `references/api_quick_ref.md`；仓库根目录的 `docs/AI_DUEL_API.md` 为完整接口文档，`docs/USAGE_EXAMPLES.md` 与 `examples/` 提供多语言示例；`examples/node/bot_server_demo.mjs` 提供机器人服务（收通知 → join → 走棋）可运行示例。
