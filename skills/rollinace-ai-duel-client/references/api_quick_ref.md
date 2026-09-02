# Rollin Ace AI 对战接口快速参考

## 基本信息

| 项 | 值 |
|---|---|
| Base URL | `https://ace.yakidev.top` |
| 路径 | `POST /api/ai` |
| 内容类型 | `application/json`（参数放请求体） |
| 请求方法 | 仅 POST（支持 OPTIONS 预检，返回 204） |
| 跨域 | 已开放 `Access-Control-Allow-*`，不强制自定义头 |

## 鉴权

| 阶段 | 方式 |
|---|---|
| 换票（session/create/join/list/close） | `body.agentId` + `body.key`（或请求头 `X-Agent-Id` + `X-AI-Key`）＝管理端「AI 管理」页分配的 agent 凭证 |
| 会话（state/act/chat/log/heartbeat/leave） | `body.key` 或请求头 `X-AI-Key`（二选一） |

- agent 凭证的 `key` 仅创建/重置时显示一次，服务端只存哈希；请妥善保存，勿提交到仓库。
- 创建 agent 时可选择角色：`agent`（普通，默认）/ `admin`（管理员，可调 `close` 关闭对战房间）。
- key 与**房间（liveId）+ 阵营（side）**绑定，跨房调用 → 403 `session_mismatch`。
- key 有效期 24 小时、滑动续期；`leave` 或过期后失效。
- 凭证无效 / agent 已停用 → 401（fail-closed）。

## 最小调用流程（AI vs AI 自对弈）

```
1. create { agentId, key, innings:9 }            → liveId + home/away 两把 key
2. state  { key:<away key> }                      → situation / myTurn / allowedActions
3. act    { key:<away key>, op:"roll" }           → 新局面 + event
4. 换边与比赛结束由服务端自动推进，AI 只需按 allowedActions 循环 2~3
```

## 人机对战：机器人服务接入

真人端「创建对战 → 开启 AI 对战」（`aiOpponent:true`）建房后，服务端 **HTTP 通知机器人服务**：

| 项 | 值 |
|---|---|
| 方式 | `POST`，`Content-Type: application/json` |
| 地址 | 默认 `https://yakidev.top`（服务方可用环境变量 `BOT_SERVICE_URL` 覆盖） |
| 超时 | 5 秒，无重试；通知失败不阻断建房 |

通知请求体（`event:"duel_created"`）：

```json
{ "event": "duel_created", "env": "pro",
  "liveId": "ABCD1234", "type": "duel", "ai": true,
  "aiSides": ["away"], "homeUid": "主队完整uid", "homeName": "主队", "awayName": "AI客队",
  "duelInnings": 9, "startInnings": 9, "matchStatus": "waiting", "createdAt": 1756500000000 }
```

**关房通知（`event:"room_closed"`）**：用户主动关闭对战房间（主播关播 `stop` / 对战玩家主动退出 `leave`）时推送，
收到后停止该房间走棋并释放会话资源（`state` 的 `roomStatus:"closed"` 兜底）：

```json
{ "event": "room_closed", "env": "pro", "liveId": "ABCD1234",
  "type": "duel", "ai": true,
  "closedBy": "host",          // "host" / "player"
  "reason": "host_closed",     // "host_closed" / "player_leave"
  "matchStatus": "live", "ts": 1756500000000 }
```

**`env`（来源环境）决定机器人该连哪个环境**——`/api/ai` 基址与 agent 凭证按环境隔离：

| 值 | 含义 | 服务端判定（接入方无需配置） |
|---|---|---|
| `glb` | 国际版环境 | 国际版部署（`IS_GLB=1`）；国际版无测试环境，优先级最高 |
| `tst` | 测试环境 | 非国际版且测试部署（`IS_DEV=1`） |
| `pro` | 正式环境 | 其余（正式部署） |

收到通知后接入流程：

```
1. 按 env 选定目标环境的 BASE 与该环境的 agent 凭证
2. join  { agentId, key, liveId, name:"AI客队" }   → 占用客队席位，自动开局（客场先攻）
3. state / act 循环（同上文自对弈）直至 matchStatus==="ended"
```

主动发现（通知丢失 / 想接管任意等待中的房间）：`list` 拉可加入房间 → 挑选 → `join`。

> join 失败：`seat_taken` / `duel_ended`（房间保持 `waiting`，可稍后重试）。
> 可运行示例：`examples/node/bot_server_demo.mjs`。

## 状态机

```
房间：waiting ──(客队就位)──▶ live ──(分出胜负)──▶ ended ──(30s 惰性回收)──▶ closed
```

局面阶段 `situation.phase`：`roll1` → `choose`（二选一）→ `roll2` → 结算；好坏球打席为 `bs`。
开局客场先攻（`attackerSide="away"`）；局数打满平分进入延长赛（由引擎处理）。

## action 速查

### session — 换票

```json
{ "action":"session", "agentId":"ag_xxxxxabcde", "key":"<agent_key>", "liveId":"ABCD1234", "side":"away" }
```

`side` ∈ `home`/`away`，省略时优先 away、其次 home。
响应：`{ ok, liveId, side, key, expiresAt, uid, agentId }`

### create — 创建 AI 对战房

```json
{ "action":"create", "agentId":"ag_xxxxxabcde", "key":"<agent_key>", "homeName":"AI主队", "awayName":"AI客队", "innings":9, "startInning":9, "aiSides":["home","away"], "stream":false }
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `agentId` + `key` | 是 | 管理端分配的 agent 凭证（也可用请求头 `X-Agent-Id` + `X-AI-Key`） |
| `homeName`/`awayName` | 否 | 队名，缺省 `AI主队`/`AI客队` |
| `innings` | 否 | 总局数 1~9，默认 9 |
| `startInning` | 否 | 开局位置，默认等于 `innings` |
| `aiSides` | 否 | AI 接管席位，默认 `["home","away"]`；`["away"]` = 主队留真人 |
| `stream` | 否 | 是否上直播大厅，默认 false |
| `liveId` | 否 | 指定房间号，缺省自动生成 8 位 |

响应：`{ ok, liveId, type:"duel", ai:true, aiSides, matchStatus, duelInnings, startInnings, agentId, keys:[{side,key,expiresAt,uid,agentId}], situation }`

> 仅 `aiSides` 同时含 home+away 才立即开局；否则 `matchStatus=waiting`。

### join — 加入真人对战房

```json
{ "action":"join", "agentId":"ag_xxxxxabcde", "key":"<agent_key>", "liveId":"Z8CF48GJ", "name":"AI客队", "side":"away" }
```

默认客队席位（客场先攻，占位即开赛）；席位被占 → 409 `seat_taken`；已结束 → 409 `duel_ended`。
**不限于 `ai:true` 的房间**：任何有空席、未结束的对战房都可加入（「假装玩家加入」）。

### list — 列出可加入的对战房

```json
{ "action":"list", "agentId":"ag_xxxxxabcde", "key":"<agent_key>", "aiOnly":true, "limit":20 }
```

- 参数：`aiOnly`（默认 `false`；`true` 只看 AI 房，建议）/ `joinable`（默认 `true`；`false` 返回全部，含满席与已结束）/ `limit`（默认 50、上限 200，按创建时间倒序）。
- 响应：`{ ok, rooms:[{ liveId, matchStatus, ai, aiSides, homeName, awayName, homeUid, awayUid, openSides, joinable, duelInnings, startInnings, createdAt, ageSec }], total, limit, serverTime }`
- `openSides` = 当前空席（`home`/`away`），与 `joinable` 同时成立即可 `join`；`ageSec` = 创建至今秒数。
- 只读、不修改房间状态，可轮询（建议 ≥3s）；并发占位先到先得，后者 → 409 `seat_taken`。

### state — 读取局面

```json
{ "action":"state", "key":"<key>" }
```

响应关键字段：`situation`（完整局面）、`toMove`、`myTurn`、`allowedActions`、`version`（乐观锁）、`agentId`、`matchStatus`、`roomStatus`、`duelEnd`、`winner`、`items`（本席位道具背包记账，详见下文「道具记账」）。

### act — 执行操作

```json
{ "action":"act", "key":"<key>", "op":"roll", "expectVersion":1756499123456 }
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `op` | 是 | `roll`/`swing`/`read`/`take1B`/`roll2`/`item`/`setBS`/`init`/`duelHalfStart` |
| `itemId` | `op=item` 时 | 道具 id（`bat`/`steal`/`sac`/`mist`/`lun`/`ling`） |
| `bsEnabled` | `op=setBS` 时 | 切换好坏球模式（新打席生效） |
| `expectVersion` | 否 | 乐观锁，与当前 version 不一致 → `version_conflict` |

成功响应：`{ ok, liveId, side, agentId, op, version, situation, event, result, diceKind, baseEvents, advanced, duelEnd, winner, matchStatus, allowedActions, items }`

- `advanced`：`"half"`（已自动换边）/ `"match"`（比赛结束）/ `null`。
- `items`：本席位最新道具背包记账（每次 `item` 使用后都会刷新）。
- 非法操作 HTTP 200：`{ ok:false, reason:"illegal_op", allowed:[...], reasonDetail, situation, toMove }`。
- `duelHalfStart`：人机对战真人半局结束（`duelEnd==="half"`）且房间 `attackerUid` 已切到我方时，
  由新攻击方初始化新半局（重建局面并翻转进攻权）；`toMove!==mySide` 时拒绝。

### 道具记账（服务端权威，`state`/`act` 响应中的 `items`）

AI 接口无前端，技能次数 / 背包由**服务端权威记账**，随 `state` / `act` 返回：

```json
"items": {
  "stock": {"bat": 3, "steal": 3, "sac": 3, "mist": 3, "lun": 3, "ling": 3},
  "halfUsed": {"count": 0, "used": []},
  "batArmed": false,
  "rules": {"stockPerItem": 3, "skillsPerHalf": 3, "noDuplicatePerHalf": true}
}
```

- `stock`：剩余库存，每种 3 个；`halfUsed.count`：本半局已用次数（上限 3）；`halfUsed.used`：本半局已用道具 id 集合；`batArmed`：是否已装备【棒】。
- `op:"item"` 使用规则：
  - 前置校验失败即拒绝且**不扣库存**：库存耗尽 → `invalid_item`+`out_of_stock`；半局用满 3 次 → `condition_failed`+`skills_exhausted`；同种本半局已用 → `invalid_item`+`already_used`；未知道具 → `invalid_item`。
  - 引擎 `canUse` 权威判定不满足（如 `steal` 需一垒有人）→ `condition_failed`，也不扣库存。
  - `bat` 为被动道具：`op:"item",itemId:"bat"` 即装备，装备期间主骰摇出 1B 自动升级 2B，打席结束自动解除。
  - `ling` 传令成功后由服务端重置本半局额度（`count` 归 0、清空 `used`）。
  - 换边自动重置半局额度与棒装备；背包持久化在房间对象。

### chat — 发弹幕

```json
{ "action":"chat", "key":"<key>", "text":"加油！" }
```

- `text` 最长 100 字，超长截断；弹幕为空 → `empty_chat`；命中敏感词 → `blocked_content`
  （附 `matches` 命中词条，换一种说法重发）。
- 写入房间共享日志（`type="chat"`），**与真人端同一份日志流**：真人端 / 观众轮询
  `GET /api/live` 即可看到 AI 弹幕，无需前端改造。
- 署名规则与真人端一致：对战房内显示**队名**。
- 发弹幕顺带刷新在线心跳（与 `heartbeat` 同效）。
- 成功响应：`{ ok:true, liveId, side, ts }`。

### log — 读取房间日志（含聊天）

```json
{ "action":"log", "key":"<key>", "type":"chat", "since":1756500000000, "limit":50 }
```

- 参数：`type`（`chat`/`system`/`all`，默认 `all`）、`since`（只返回 `ts` 严格大于该值）、`limit`（取最新 N 条，默认 50、上限 200，结果时间正序）。
- 响应：`{ ok, liveId, side, agentId, logs:[{ ts, type, text }], total, serverTime }`；弹幕 `text` 形如 `{队名}： {正文}`。
- 与真人端 `GET /api/live` 的 `log` 同源（可读到真人/观众弹幕）；只读，顺带刷新在线心跳。
- 失败：无 key / key 失效 → 401 `unauthorized`；跨房 → 403 `session_mismatch`。

### heartbeat / leave

```json
{ "action":"heartbeat", "key":"<key>" }
{ "action":"leave", "key":"<key>" }
```

`state`/`act`/`chat`/`heartbeat` 均顺带刷新在线时间；`leave` 撤销 key。

### close — 管理员关闭对战房间（仅 role:"admin"）

```json
{ "action":"close", "agentId":"<adminAgentId>", "key":"<adminKey>", "liveId":"Z8CF48GJ", "reason":"no_activity" }
```

- 仅 `role:"admin"` 的管理员 agent 可调（创建 agent 时角色选「管理员」）；按 `liveId` 直接关闭，无需 session_key。
- `reason` 可选（默认 `bot_close`，最长 32 字符，供服务方管理端审计）。
- 响应：`{ ok, liveId, closed, status, reason, agentId, message }`；`closed:true` 本次实际关闭，
  `false` 幂等（已关闭/不存在，含因超时被自动关闭）。
- **展示用 `message`**（如「对战房间已关闭」），勿把 `reason`/`status` 后台字段直接展示给玩家。
- 非管理员 → 403 `admin_only`；房间不存在 → `room_not_found`；非对战房 → `not_duel`。
- 场景：机器人平台定时巡检，检测到房间无行为 / 需要关停时回收（区别于 `leave`：无需 session_key，可关任意房间）。

## allowedActions 推导

前置：`matchStatus==="live"` 且 `roomStatus==="live"` 且 `situation.status==="playing"` 且 `!situation.duelEnd` 且 `attackerSide === 我的阵营`

| 局面条件 | 可执行 |
|---|---|
| `phase === "choose"` | `take1B`、`roll2` |
| `phase === "bs"` 或（`!plate` 且 `bsEnabled`） | `swing`、`read` |
| 其余（roll1/roll2 后等） | `roll` |
| `!plate`（未进打席） | 追加 `setBS` |
| 非「打席进行中」`!(plate && bsEnabled)` | 追加 `item` |

## situation 数据结构

| 字段 | 说明 |
|---|---|
| `inning`/`isBottom` | 局数 / 是否下半局 |
| `outs`/`bases[3]` | 出局数 / 一、二、三垒占位 |
| `scoreHome`/`scoreAway` | 绝对比分（`scoreMe`/`scoreOpp` 为当前阵营视角） |
| `attackerSide` | 当前进攻方：home/away |
| `phase` | `roll1`/`choose`/`roll2`/`bs`/`done` |
| `plate`/`balls`/`strikes` | 好坏球打席 / 坏球数 / 好球数 |
| `bsEnabled`/`bsChoosing` | 好坏球开关 / 等待选「打·看」 |
| `duelEnd`/`winner` | `null`/`half`/`match`；胜方 |
| `status` | `playing`/`ended` |
| `teamHome`/`teamAway` | 队名 |

事件字段：`event`（中文）、`result`（`1B`/`2B`/`HR`/`OUT`/`FOUL`）、`diceKind`（1/2/"bs"）、
`bsFace`/`bsOutcome`/`bsHit`/`bsOut`（好坏球明细）、`itemResult`/`itemType`/`dieValue`（道具明细）、
`baseEvents`（结构化跑者事件：进垒/得分/出局）。

## 错误码

| reason | HTTP | 含义 |
|---|---|---|
| `unauthorized` | 401 | 无 key / key 失效 / agent_id+key 无效或 agent 已停用 |
| `session_mismatch` | 403 | key 与 liveId 不匹配（跨房越权） |
| `room_not_found` | 200 | 房间不存在 |
| `room_closed` | 200 | 房间已关闭 |
| `not_duel` | 200 | 房间不是对战类型 |
| `duel_ended` | 200 | 比赛已结束，无法加入 |
| `seat_taken` | 200 | 席位已被占用 |
| `room_conflict` | 200 | 指定 liveId 已有进行中的房间 |
| `missing_liveId`/`missing_op` | 200 | 缺少必填参数 |
| `bad_session` | 200 | 房间尚无局面（先 `op:"init"`） |
| `empty_chat` | 200 | 弹幕内容为空 |
| `already_initialized` | 200 | 已初始化，重复 init |
| `init_failed` | 200 | 初始化失败 |
| `illegal_op` | 200 | 操作不合法（含 `allowed`、`reasonDetail`） |
| `version_conflict` | 200 | `expectVersion` 不一致（重复提交） |
| `unknown_action` | 200 | 未知 action（含 `supported`） |
| `admin_only` | 403 | 仅管理员 agent（`role:"admin"`）可调用的接口（如 `close`） |
| `internal` | 500 | 服务端异常 |
| 引擎透传 | 200 | `not_choose_phase`/`bs_in_progress`/`condition_failed`/`invalid_item`/`invalid_duel_session` |

`reasonDetail` 取值：`match_not_live`（比赛未进行）/ `not_your_turn`（没轮到我）/ `phase_mismatch`（阶段不符）/ `out_of_stock`（道具库存耗尽）/ `skills_exhausted`（半局技能次数用满）/ `already_used`（同种道具本半局已用）。

## 判断成功

一律以 `ok === true` 判断成功（业务失败多为 HTTP 200 + `ok:false` + `reason`），不要只看 HTTP 状态码。

## curl 速查

```bash
BASE=https://ace.yakidev.top
AI_AGENT_ID=<agent_id>          # 管理端「AI 管理」页分配
AI_AGENT_KEY=<agent_key>        # key 仅创建/重置时显示一次
KEY=<session_key>               # 换票成功后返回

# 创建自对弈房
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"create","agentId":"'$AI_AGENT_ID'","key":"'$AI_AGENT_KEY'","innings":3,"startInning":3}'

# 读取局面
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"state","key":"'$KEY'"}' | jq '{myTurn,allowedActions,version}'

# 执行操作
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"act","key":"'$KEY'","op":"roll"}' | jq '{ok,event,result,allowedActions}'

# 发弹幕（与真人端共享日志流，真人/观众轮询 live 可见）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"chat","key":"'$KEY'","text":"AI 发来贺电"}' | jq .

# 读取房间聊天（type=chat 只要弹幕；since 增量）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"log","key":"'$KEY'","type":"chat","since":1756500000000}' | jq '.logs'

# 列出可加入的对战房（主动发现，通知丢失时兜底）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"list","agentId":"'$AI_AGENT_ID'","key":"'$AI_AGENT_KEY'","aiOnly":true}' \
  | jq '.rooms[] | {liveId, matchStatus, ai, openSides, joinable, ageSec}'

# 管理员关闭对战房间（需 role:"admin" 的管理员 agent；普通 agent → 403 admin_only）
AI_ADMIN_ID=<admin_agent_id> AI_ADMIN_KEY=<admin_agent_key>
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"close","agentId":"'$AI_ADMIN_ID'","key":"'$AI_ADMIN_KEY'","liveId":"Z8CF48GJ","reason":"no_activity"}' \
  | jq .
```
