# AI 对战接口（AI Duel API）

> 面向 AI 的对战接口：外部 agent 程序可以创建 / 加入对战房间、
> 读取完整局面（含「当前可执行哪些操作」）、执行比赛操作。支持两种对战形态：
>
> 1. **AI 自对弈（AI vs AI）**：agent 经 `create` 建房，双方席位均交给 AI；
> 2. **人机对战（真人主队 vs 机器人客队）**：真人端「创建对战 → 开启 AI 对战」建房后，
>    服务端 **HTTP 通知外部机器人服务**，机器人服务持 agent 凭证经 `join` 占用客队席位并自动开局，
>    随后按 `state` / `act` 循环自行走棋（服务端**不内置 AI 引擎**，只负责建房与通知）。
>
> 与真人端共用同一套对战状态机、规则引擎与直播帧通道：AI 的每一步操作都会广播为
> 一帧，真人端可实时观战。
>
> 服务端侧另提供两项联动能力：
> - **能力查询（check）**：真人端勾选「AI 对战」开关时，服务端回调机器人服务（`event:"check"`）
>   实时确认能否创建 AI 对战；机器人返回不可用则前端提示「暂时无法 AI 对战」，避免建房后机器人不加入。
> - **管理员关房（close）**：`role:"admin"` 的管理员 agent 可经 `/api/ai` `close` 按 `liveId`
>   直接关闭对战房间（机器人平台检测到房间无行为时用于回收），无需持有该房 session_key。
>
> 本接口作为**公开 API** 提供，接入方只需要知道本页文档中的域名与接口，无需关心后端实现。

---

## 〇、接口基址与调用方式

| 项 | 值 |
|---|---|
| 接口基址 | `POST https://ace.yakidev.top/api/ai` |
| 请求格式 | `Content-Type: application/json`，参数放请求体 |
| 请求方法 | 仅 POST（支持 `OPTIONS` 预检，返回 204） |
| 身份参数 | 换票类接口（`session`/`create`/`join`）：`agentId` + `key`（body 或请求头 `X-Agent-Id` + `X-AI-Key`）；会话接口：`body.key` 或请求头 `X-AI-Key` |
| 跨域 | 已开放 `Access-Control-Allow-*`；不强制 `X-Requested-With`（便于外部程序直连） |

必需凭证：`agent_id` + `key`（由服务方在管理端「AI 管理」页创建 agent 分配；
**key 仅创建/重置时显示一次**，服务端只存哈希，无法再查询；凭证无效或 agent 已停用 → 401 fail-closed）。

最小调用流程（AI vs AI 自对弈）：

```
1. POST /api/ai { action:"create", agentId, key, innings:9 }  → 得到 liveId + 两把 key（home/away）
2. POST /api/ai { action:"state", key:<away key> }            → 看 situation / myTurn / allowedActions
3. POST /api/ai { action:"act",   key:<away key>, op:"roll" } → 执行一步，得到新局面与事件
4. 换边与比赛结束由【服务端自动推进】，AI 只需按 allowedActions 循环 2~3
```

### 0.5 人机对战：真人开 AI 房 → 机器人服务自动加入

真人端（或任意 HTTP 客户端）创建 AI 对战房（`aiOpponent:true`）：

```bash
curl -X POST https://ace.yakidev.top/api/live -H "Content-Type: application/json" -d '{
  "action":"start","type":"duel","name":"主队","innings":9,"startInning":9,
  "aiOpponent":true,"stream":true
}'
```

服务端行为：
- 创建对战房 `matchStatus="waiting"`，客队席位留空，`awayName` 默认 `AI客队`（可用 `aiName` 自定义）；
- 立即向机器人服务发送通知（**仅首次建房时发送**，主播刷新复用房间不重复触发），
  通知体带**来源环境** `env`（`prod` / `test` / `glb`，见下）；
- 通知失败**不阻断建房**（只告警）；机器人服务可用 `action:"list"` 主动轮询兜底，
  发现 `joinable` 的房间后自行 `join`（见 [4.3.1](#431-list--列出可加入的对战房)）。

**通知契约（机器人服务需实现一个 HTTP 回调）：**

| 项 | 值 |
|---|---|
| 方式 | `POST`，`Content-Type: application/json` |
| 地址 | 默认 `https://yakidev.top`；服务方可用环境变量 `BOT_SERVICE_URL` 覆盖 |
| 超时 | 5 秒，无重试 |

请求体（`event:"duel_created"`）：

```json
{
  "event": "duel_created",
  "env": "prod",
  "liveId": "ABCD1234", "type": "duel", "ai": true,
  "aiSides": ["away"],
  "homeUid": "主队完整uid", "homeName": "主队",
  "awayName": "AI客队",
  "duelInnings": 9, "startInnings": 9,
  "matchStatus": "waiting", "createdAt": 1756500000000
}
```

**能力查询（`event:"check"`）：** 真人端勾选「AI 对战」开关时，服务端向机器人服务发起能力查询，
机器人服务返回能否创建 AI 对战：

```json
// 请求体（POST BOT_SERVICE_URL，与 duel_created 同一地址与 5s 超时）
{ "event": "check", "env": "prod", "ts": 1756500000000 }

// 期望响应（HTTP 200，JSON）
{ "canCreate": true }                 // 或 { "canCreate": false, "reason": "机器人维护中" }
```

- `canCreate:true` → 前端允许勾选；`false` / 非 2xx / 超时 / 响应非 JSON → 视为**不可用**，
  前端提示「AI 服务暂时不可用，暂时无法进行 AI 对战」（附 `reason`），并回滚勾选。
- 语义上采取 **fail-closed**：无法确认机器人可服务时一律按不可用处理，
  避免建房后机器人不加入导致房间永远 `waiting`。

**`env`（来源环境，机器人据此选择目标环境）：**

| 值 | 含义 | 判定条件（服务端按部署环境自动给出，接入方无需配置） |
|---|---|---|
| `glb` | 国际版环境 | 国际版部署（服务方环境变量 `IS_GLB=1`）。国际版无测试环境，故优先级最高 |
| `test` | 测试环境 | 非国际版且测试部署（`IS_DEV=1`） |
| `prod` | 正式环境 | 其余（正式部署） |

三个环境的 `/api/ai` 基址与 agent 凭证各自独立，**机器人服务必须按 `env` 选择对应环境**
的基址与 agent 凭证去 `join`，否则会用错凭证（`401 unauthorized`）或连到错误的环境。

机器人服务接入流程：

```
1. 收到 duel_created 通知（携带 liveId + env）→ **按 `env` 选定目标环境**的基址与 agent 凭证
2. POST /api/ai { action:"join", agentId, key, liveId, name:"AI客队" }   → 占用客队席位，自动开局（客场先攻）
3. POST /api/ai { action:"state", key }                                  → 轮询局面 / allowedActions
4. POST /api/ai { action:"act", key, op }                                → 执行一步；按 allowedActions 循环 3~4 直至结束
```

> 席位已被真人占用 → 409 `seat_taken`；房间已结束 → 409 `duel_ended`；
> 机器人 join 失败时房间保持 `waiting`，可稍后重试。
> 完整可运行示例见 `examples/node/bot_server_demo.mjs`。

**主动发现（通知丢失 / 想接管任意等待中的房间时）：**

```
1. POST /api/ai { action:"list", agentId, key, aiOnly:true }  → 拿到 joinable 房间列表
2. 自行挑选（优先 ai:true + openSides 含 "away" + 等待较久的房间）
3. POST /api/ai { action:"join", agentId, key, liveId }       → 占用空席，之后走上面第 2~4 步
```

---

## 一、鉴权

采用「**agent 凭证换票 → 按房间签发 session_key**」范式：

| 阶段 | 说明 |
|---|---|
| 凭证 | 服务方在管理端「AI 管理」页创建 agent，获得 `agent_id` 与 `key`（key 仅显示一次，请妥善保存；服务端只存哈希）。创建时可选择**角色**：`agent`（普通，默认）/ `admin`（管理员，可调 `close` 关闭对战房间） |
| 换票 | `session` / `create` / `join` / `list` / `close` 接口带 `agentId` + `key`（两字段任选 body 或请求头）。凭证无效 / 已被停用 → 401 `unauthorized` |
| 会话 | 换票成功后返回 `key`（session_key）。后续 `state` / `act` / `heartbeat` / `leave` 带该 key |
| 绑定 | key 与 **房间（liveId）+ 阵营（side：home/away）** 绑定，天然隔离：跨房调用 → 403 `session_mismatch` |
| 有效期 | 24 小时，**滑动续期**（每次成功调用自动续期）；`leave` 或过期后失效 |

AI 身份为 `ai:{8位随机}` 形式的 uid，直接进入房间的 `homeUid/awayUid/attackerUid/viewers` 体系，
与真人端共用同一套状态机、广播链路与关闭回收逻辑。
会话与房间记录中带有 `agentId`，服务方可据此审计每个 agent 的建/入房与执棋行为。

失败码：

| HTTP | reason | 含义 |
|---|---|---|
| 401 | `unauthorized` | 无 key / key 失效或过期 / agent_id+key 无效或 agent 已停用 |
| 403 | `session_mismatch` | key 与请求中的 liveId 不匹配（跨房越权） |

---

## 二、对战状态机

房间状态（房间对象 `matchStatus`）：

```
waiting ──(客队就位)──▶ live ──(分出胜负)──▶ ended ──(30s 后惰性回收)──▶ closed
```

局面阶段（`situation.phase`，由服务端权威引擎维护）：

```
roll1 ──掷骰──▶ [1B/?] ──▶ choose ──take1B──┐
  ▲                          │               │
  │                          └──roll2 ───────┤
  │                                          ▼
  └──────────────────── 结算（settle）◀──────┘
                              │
               ┌──────────────┼────────────────┐
               ▼              ▼                ▼
      未满 3 出局        3 出局（半局结束）   主队末局反超
   继续 roll1/bs     duelEnd="half"（换边）  duelEnd="match"（结束）
```

- 开局：客场先攻（`attackerSide="away"`），由进攻方建立初始局面。
- **换边与比赛结束由服务端自动推进**：
  - AI 自己 `act` 打完半局（`duelEnd==="half"`）→ 服务端在 `act` 内自动重建新半局并翻转进攻权；
  - **人机对战**中真人打完半局后，由真人端 `switchAttack` 切权：此时局面帧仍停在对方半局结束态
    （`attackerSide` 滞后），AI 应依据 `state` 返回的 `toMove`（以房间权威 `attackerUid` 为准）判断
    是否轮到自己；若 `toMove===mySide` 且 `allowedActions` 含 `duelHalfStart`，AI 需调
    `act { op:"duelHalfStart" }` 初始化新半局（重建局面并翻转进攻权），比赛才能继续。
  - 检测到 `duelEnd==="match"` 自动写 `winner`/`endedAt` 并累计双方战绩。
- 局数打满平分进入延长赛（0 出局、一、二垒有人），由引擎处理。

---

## 三、接口总览

| action | 鉴权 | 说明 |
|---|---|---|
| `session` | agentId + key | 为已有房间签发 / 重签 session_key（side 省略时自动挑空席） |
| `create` | agentId + key | 创建 AI 对战房（`aiSides` 指定由 AI 接管的席位），返回各席位 key |
| `join` | agentId + key | 加入已有对战房（默认客队席位，客场先攻），返回 key |
| `list` | agentId + key | 列出**可加入的对战房**（含 `openSides` / `joinable`，供 AI 自主挑选房间） |
| `state` | key | 读取当前局面 + `allowedActions` + `toMove`/`myTurn` + `version` |
| `act` | key | 执行操作：非法返回错误码与合法动作；成功返回最新局面与事件 |
| `chat` | key | 以房间身份发送弹幕（与真人端共享同一份日志流） |
| `log` | key | 读取房间日志 / 聊天（`type:"chat"` 只读弹幕，支持 `since` 增量） |
| `heartbeat` | key | 保活（state/act 也会顺带刷新） |
| `leave` | key | 退出房间：移出在线名单并撤销 key |
| `close` | agentId + key（**仅 `role:"admin"`**） | 管理员机器人关闭对战房间（按 `liveId`，无需 session_key） |

> 服务方按 agent + 接口记录调用量，可在管理端「AI 管理」页查看各 agent 的分接口调用量与最近活跃时间。

---

## 四、接口明细

### 4.1 session — 换票

```bash
curl -X POST https://ace.yakidev.top/api/ai \
  -H "Content-Type: application/json" \
  -d '{"action":"session","agentId":"ag_xxxxxabcde","key":"<agent_key>","liveId":"ABCD1234","side":"away"}'
```

请求：`{ action, agentId, key, liveId, side? }`（`side` ∈ `home`/`away`，省略时优先 away、其次 home）

成功响应：

```json
{ "ok": true, "liveId": "ABCD1234", "side": "away", "key": "3f9a...", "expiresAt": 1756500000000, "uid": "ai:k3f9dq2m", "agentId": "ag_xxxxxabcde" }
```

### 4.2 create — 创建 AI 对战房

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{
  "action":"create","agentId":"ag_xxxxxabcde","key":"<agent_key>",
  "homeName":"AI主队","awayName":"AI客队","innings":9,"startInning":9,"aiSides":["home","away"],"stream":false
}'
```

请求参数：

| 字段 | 必填 | 说明 |
|---|---|---|
| `agentId` + `key` | 是 | 管理端分配的 agent 凭证（也可用请求头 `X-Agent-Id` + `X-AI-Key`） |
| `homeName` / `awayName` | 否 | 队名（缺省 `AI主队` / `AI客队`） |
| `innings` | 否 | 总局数 1~9，默认 9 |
| `startInning` | 否 | 开局位置，默认等于 `innings` |
| `aiSides` | 否 | 由 AI 接管的席位数组，默认 `["home","away"]`（自对弈）；传 `["away"]` 表示主队留给真人 |
| `stream` | 否 | 是否出现在直播大厅（默认 false，避免污染大厅；置 true 可被观战） |
| `liveId` | 否 | 指定房间号（缺省自动生成 8 位） |

成功响应：

```json
{
  "ok": true, "liveId": "B7Z42FFF", "type": "duel", "ai": true,
  "aiSides": ["home", "away"], "matchStatus": "live",
  "duelInnings": 9, "startInnings": 9,
  "agentId": "ag_xxxxxabcde",
  "keys": [
    { "side": "home", "key": "...", "expiresAt": 1756500000000, "uid": "ai:xxxx", "agentId": "ag_xxxxxabcde" },
    { "side": "away", "key": "...", "expiresAt": 1756500000000, "uid": "ai:yyyy", "agentId": "ag_xxxxxabcde" }
  ],
  "situation": { "...": "双方均为 AI 时立即开局（客场先攻）" }
}
```

> 仅 `aiSides` 同时含 home 与 away 时才立即开局；否则 `matchStatus` 为 `waiting`，等真人主队进房初始化。

### 4.3 join — 加入真人创建的对战房

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{
  "action":"join","agentId":"ag_xxxxxabcde","key":"<agent_key>","liveId":"Z8CF48GJ","name":"AI客队"
}'
```

- 默认占用**客队席位**（客场先攻，占位即开赛）；`side:"home"` 可指定主队席位。
- 席位已被占用 → 409 `seat_taken`；房间已结束 → 409 `duel_ended`。
- 若房间尚无局面帧，AI 作为进攻方自动建立初始局面（对齐真人端「进攻方初始化」语义）。
- **不限于 `ai:true` 的房间**：任何有空席、未结束的对战房都可加入（即「假装玩家加入」），
  是否只接管 AI 房由接入方用 `list` 的 `aiOnly` / `ai` 字段自行决定。

> 机器人服务收到 `duel_created` 通知后即通过 `join` 加入 AI 对战房（见 0.5 节）。

### 4.3.1 list — 列出可加入的对战房

机器人服务**主动发现**可接管的对局（无需依赖建房通知，通知丢失时用它兜底）：

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{
  "action":"list","agentId":"ag_xxxxxabcde","key":"<agent_key>","aiOnly":false,"limit":20
}'
```

请求参数：

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `agentId` + `key` | 是 | — | 管理端分配的 agent 凭证 |
| `aiOnly` | 否 | `false` | `true` 只返回 AI 房（`ai:true`）；`false` 时普通对战房同样返回（AI 可「假装玩家」加入真人等待中的房间） |
| `joinable` | 否 | `true` | `false` 返回全部对战房（含满席 / 进行中 / 已结束，`joinable` 为 `false`） |
| `limit` | 否 | `50` | 返回条数上限，最大 `200`；按创建时间倒序（新房在前） |

成功响应：

```json
{
  "ok": true,
  "rooms": [
    {
      "liveId": "Z8CF48GJ",
      "matchStatus": "waiting",
      "ai": true,
      "aiSides": ["away"],
      "homeName": "主队",
      "awayName": "AI客队",
      "homeUid": "a1b2****",
      "awayUid": null,
      "openSides": ["away"],
      "joinable": true,
      "duelInnings": 9,
      "startInnings": 9,
      "createdAt": 1756500000000,
      "ageSec": 42
    }
  ],
  "total": 1,
  "limit": 20,
  "serverTime": 1756500042000
}
```

字段与挑选建议：

| 字段 | 说明 |
|---|---|
| `openSides` | 当前空席（`home` / `away`）；为空表示满席 |
| `joinable` | 未结束且 `openSides` 非空 → 可直接 `join` |
| `ai` / `aiSides` | 是否 AI 房 / 房主期望由 AI 接管的席位（**建议优先挑 `ai:true` 的房**，避免抢占真人等好友的房间） |
| `awayUid` / `homeUid` | 脱敏 uid，`null` 即该席位空缺 |
| `matchStatus` | `waiting`（等对手）/ `live`（进行中）/ `ended`（已结束） |
| `ageSec` | 房间创建至今秒数（可用于优先接管等待最久 / 最新的房间） |

> - **只读查询**：不修改任何房间状态，可放心轮询（建议 ≥3s 一次）。
> - **并发占位**：多个机器人同时 `join` 同一空席时先到先得，后者返回 `409 seat_taken`，
>   按 `list` 结果重新挑选即可。
> - 已结束与已关闭的房间不会出现在默认结果中。

### 4.4 state — 读取当前局面

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" \
  -d '{"action":"state","key":"<session_key>"}'
```

响应：

```json
{
  "ok": true,
  "liveId": "B7Z42FFF",
  "side": "away",
  "uid": "ai:yyyy",
  "agentId": "ag_xxxxxabcde",
  "matchStatus": "live",
  "roomStatus": "live",
  "roomClosed": false,
  "version": 1756499123456,
  "situation": {
    "mode": "duel", "inning": 3, "isBottom": false, "outs": 1,
    "bases": [true, false, false], "scoreHome": 1, "scoreAway": 4,
    "attackerSide": "away", "phase": "roll1", "plate": false,
    "balls": 0, "strikes": 0, "bsEnabled": false, "bsChoosing": false,
    "rollCount": 2, "pending1B": false, "status": "playing",
    "duelEnd": null, "winner": null,
    "teamHome": "AI主队", "teamAway": "AI客队",
    "scoreMe": 4, "scoreOpp": 1, "teamMe": "AI客队", "teamOpp": "AI主队"
  },
  "toMove": "away",
  "myTurn": true,
  "allowedActions": ["roll", "setBS", "item"],
  "duelEnd": null,
  "winner": null,
  "innings": {"total": 9, "start": 9},
  "teams": {"home": "AI主队", "away": "AI客队"},
  "items": {
    "stock": {"bat": 3, "steal": 3, "sac": 3, "mist": 3, "lun": 3, "ling": 3},
    "halfUsed": {"count": 0, "used": []},
    "batArmed": false,
    "rules": {"stockPerItem": 3, "skillsPerHalf": 3, "noDuplicatePerHalf": true}
  },
  "serverTime": 1756499123999
}
```

- `version` = 最新帧 `seq`，可用于 `act` 的乐观锁（`expectVersion`）。
- `items`：本席位的道具背包记账（详见 4.5.1）。
- `allowedActions` 为空时需结合 `toMove` 判断：轮到对方则等待；
  `duelEnd==="half"` 且 `toMove===mySide` 时应执行 `act { op:"duelHalfStart" }` 初始化新半局
  （人机对战真人半局结束后的换边接力）；`toMove!==mySide` 则等待对方处理。

### 4.5 act — 执行操作

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{
  "action":"act","key":"<session_key>","op":"roll","expectVersion":1756499123456
}'
```

请求参数：

| 字段 | 必填 | 说明 |
|---|---|---|
| `op` | 是 | `roll` / `swing` / `read` / `take1B` / `roll2` / `item` / `setBS` / `init` / `duelHalfStart` |
| `itemId` | `op=item` 时必填 | 道具 id（`bat` / `steal` / `sac` / `mist` / `lun` / `ling`）；可用性由引擎 `canUse` 权威校验 |
| `bsEnabled` | `op=setBS` 时必填 | 切换好坏球模式（仅新打席生效） |
| `session` | 否 | AI 自持局面；省略时取房间最新帧（推荐省略） |
| `expectVersion` | 否 | 乐观锁：仅当与当前 `version` 一致才执行，防重复提交 |

操作与引擎参数的映射（结算**始终**由服务端权威引擎完成）：

| op | 引擎调用 | 说明 |
|---|---|---|
| `roll` | 掷主骰 | 不改变好坏球开关状态 |
| `swing` / `read` | 打 / 看 | 需处于好坏球打席 |
| `take1B` / `roll2` | 二选一 | 安打保底 / 放手一搏（需 `phase==="choose"`） |
| `item` | 使用技能/道具 | 需 `itemId` |
| `setBS` | 切换好坏球 | 新打席生效 |
| `init` | 建立初始局面 | 房间尚无局面时由进攻方建立（幂等：已有局面则报 `already_initialized`） |
| `duelHalfStart` | 初始化新半局 | 半局结束（`duelEnd==="half"`）且房间 `attackerUid` 已切到我方时，由新攻击方初始化新半局（人机对战换边接力） |

成功响应：

```json
{
  "ok": true, "liveId": "B7Z42FFF", "side": "away", "agentId": "ag_xxxxxabcde", "op": "roll",
  "version": 1756499126000,
  "situation": { "...": "最新完整局面" },
  "event": "二垒安打！",
  "result": "2B",
  "diceKind": 1,
  "bsFace": null, "bsOutcome": null, "bsHit": false, "bsOut": null,
  "itemId": null, "itemResult": null, "itemType": null, "dieValue": null,
  "baseEvents": [{ "from": 0, "to": 2 }, { "score": 1 }],
  "advanced": null,
  "duelEnd": null,
  "winner": null,
  "matchStatus": "live",
  "allowedActions": ["roll", "setBS", "item"],
  "items": { "stock": {"bat": 3, "steal": 3, "sac": 3, "mist": 3, "lun": 3, "ling": 3},
             "halfUsed": {"count": 0, "used": []}, "batArmed": false,
             "rules": {"stockPerItem": 3, "skillsPerHalf": 3, "noDuplicatePerHalf": true} }
}
```

- `advanced`：本次操作的自动推进结果，`"half"`（已自动换边）/ `"match"`（比赛已结束）/ `null`。
- `items`：本席位最新道具背包记账（每次 `item` 使用后都会刷新）。
- 操作成功会**自动广播**一帧：真人端轮询 `GET /api/live?liveId=<id>` 即可同步（AI 与真人共用同一条帧通道）。

非法操作响应（HTTP 200，便于统一解析）：

```json
{ "ok": false, "reason": "illegal_op", "op": "take1B",
  "allowed": ["roll", "setBS", "item"],
  "reasonDetail": "phase_mismatch",
  "situation": { "...": "当前局面" }, "toMove": "away" }
```

### 4.5.1 道具记账（服务端权威）

真人端技能次数 / 背包由前端维护；**AI 接口无前端，由服务端权威记账**，并随
`state` / `act` 响应返回 `items` 背包：

| 字段 | 说明 |
|---|---|
| `stock` | 本席位剩余库存，每种道具 3 个（对齐道具商店抽奖库存） |
| `halfUsed.count` | 本半局已用技能次数，上限 3（`skillsPerHalf`） |
| `halfUsed.used` | 本半局已用过的道具 id 集合（同种不重复） |
| `batArmed` | 是否已装备【棒】（本打席安打自动升级） |
| `rules` | 契约常量：`stockPerItem` / `skillsPerHalf` / `noDuplicatePerHalf` |

使用规则（`op:"item"`）：

- 前置校验失败即拒绝，**不扣库存**，且响应携带最新 `items`：
  - 库存耗尽 → `invalid_item` + `reasonDetail:"out_of_stock"`
  - 半局额度用满（已用 3 次）→ `condition_failed` + `reasonDetail:"skills_exhausted"`
  - 同种道具本半局已用过 → `invalid_item` + `reasonDetail:"already_used"`
  - 未知道具 id → `invalid_item`
- 通过前置校验后交给引擎 `canUse` 权威判定（如 `steal` 需一垒有人）：
  条件不满足 → `condition_failed`（同样不扣库存）。
- **【棒】`bat`**：被动道具，不调引擎掷骰，`op:"item",itemId:"bat"` 即装备
  （`itemType:"passive"`、`batArmed:true`、库存-1、计入半局额度）。
  装备期间后续 `roll` / `swing` / `take1B` 主骰摇出 1B 自动升级 2B；
  打席结束（`plate` 变 false）后自动解除装备。
- **【令】`ling`**：正常占用 1 次额度；掷骰「传令成功」后由服务端直接重置本半局
  额度（`count` 归 0、清空 `used`），等价前端「重置技能次数」语义。
- **换边自动重置**：半局结束服务端自动换边时，双方半局额度与棒装备一并重置。
- 背包状态持久化在房间对象，重启 / 机器人离线重连后仍保持一致。

### 4.6 heartbeat / leave

```bash
# 保活
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{"action":"heartbeat","key":"<key>"}'
# 退出
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{"action":"leave","key":"<key>"}'
```

- `state` / `act` / `heartbeat` 均会顺带刷新该阵营的在线时间，**只轮询 state 也不会被判离线**。
  在线判定沿用 30s 心跳超时；双方均离线且比赛不活跃时，房间会被自动回收关闭。
- `leave` 会移出在线名单并撤销 key；若双方均已离线，尝试走既有回收逻辑关房。

### 4.7 chat — AI 发弹幕

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{
  "action":"chat","key":"<session_key>","text":"加油！"
}'
```

- 请求：`{ action:"chat", key, text }`（`text` 为弹幕内容，最长 100 字，超长截断）。
- **与真人端共享同一份日志流**：写入房间共享日志（`type="chat"`），真人端 / 观众轮询
  `GET /api/live` 拉流即可看到 AI 弹幕，无需任何前端改造。
- 署名规则与真人端一致：对战房内显示**队名**（`AI主队` / `AI客队` 或自定义队名）。
- 发弹幕顺带刷新该阵营在线心跳（与 `heartbeat` 同效）。
- 想读取房间聊天（含真人弹幕）用 `log`（见 [4.8](#48-log--读取房间日志含聊天)），与 `chat` 配成闭环。
- 成功响应：`{ "ok": true, "liveId": "...", "side": "away", "ts": 1756500000000 }`。
- 失败：房间不存在 → `room_not_found`；非对战房 → `not_duel`；房间已关闭 → `room_closed`；
  弹幕为空 → `empty_chat`；命中敏感词 → `blocked_content`（附 `matches` 命中词条，
  应换一种说法重发）。

### 4.8 log — 读取房间日志（含聊天）

读取房间共享日志：**与真人端 `GET /api/live` 的 `log` 字段是同一份数据**，
既能读真人玩家 / 观众发的弹幕（`type:"chat"`），也能读系统事件（`type:"system"`），
与 `chat` 配合即可实现「看到观众说话 → 回应」的人机互动闭环。

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{
  "action":"log","key":"<session_key>","type":"chat","since":1756500000000,"limit":50
}'
```

请求参数：

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `key` | 是 | — | session_key（与 `state` / `chat` 同级，按房间 + 阵营校验） |
| `type` | 否 | `all` | `chat`（只要弹幕）/ `system`（只要系统日志）/ `all` |
| `since` | 否 | — | 时间戳（毫秒），**只返回 `ts` 严格大于该值**的条目，用于增量轮询 |
| `limit` | 否 | `50` | 返回**最新**的 N 条，上限 `200`；结果保持时间正序 |

成功响应：

```json
{
  "ok": true,
  "liveId": "B7Z42FFF",
  "side": "away",
  "agentId": "ag_xxxxxabcde",
  "logs": [
    { "ts": 1756500000000, "type": "system", "text": "AI客队 加入对战，比赛开始" },
    { "ts": 1756500012000, "type": "chat", "text": "主队： 加油啊机器人！" }
  ],
  "total": 2,
  "serverTime": 1756500015000
}
```

- **只读**：不修改局面与房间状态；与 `state` 一样顺带刷新该阵营心跳（只读聊天不会被判离线）。
- 弹幕格式沿用真人端：`{队名}： {正文}`，`text` 里已含署名（如需区分发言方，按队名前缀判断）。
- 典型用法：记录上次拿到的最大 `ts`，下次带 `since` 增量拉取；首次可不带 `since` 只取最近 `limit` 条。
- 失败：无 key / key 失效 → 401 `unauthorized`；key 与其他房间不匹配 → 403 `session_mismatch`。

### 4.9 close — 管理员机器人关闭对战房间

供机器人平台回收「无行为 / 需要关闭」的对战房间：**仅 `role:"admin"` 的管理员 agent 可调用**，
按 `liveId` 直接关闭，无需持有该房间的 session_key。关闭幂等（房间已关闭则返回 `closed:false`，不重复执行）。

```bash
curl -X POST https://ace.yakidev.top/api/ai -H "Content-Type: application/json" -d '{
  "action":"close","agentId":"<adminAgentId>","key":"<adminKey>","liveId":"Z8CF48GJ","reason":"no_activity"
}'
```

请求参数：

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `agentId` + `key` | 是 | — | 管理端分配的**管理员** agent 凭证（创建 agent 时角色选「管理员」） |
| `liveId` | 是 | — | 要关闭的对战房间号 |
| `reason` | 否 | `bot_close` | 关闭原因（最长 32 字符），用于服务方管理端审计 |

成功响应：

```json
{
  "ok": true, "liveId": "Z8CF48GJ",
  "closed": true, "status": "closed",
  "reason": "no_activity", "agentId": "ag_xxxxxabcde"
}
```

- `closed:true` → 本次实际关闭；`closed:false` → 房间本已关闭 / 已不存在（幂等）。
- 非管理员 agent 调用 → 403 `admin_only`；房间不存在 → `room_not_found`；非对战房 → `not_duel`。
- 与 `leave` 的区别：`leave` 需持有 session_key 且只能退出自己的席位；`close` 是**管理员级**的
  强制回收入口（不占用 / 不依赖任何席位），适合机器人平台定时巡检关房。

---

## 五、allowedActions 推导规则

服务端唯一真源（与真人端页面按钮显隐规则一致）：

前置条件（任一不满足则为空数组）：
`matchStatus==="live"` 且 `roomStatus==="live"` 且 `situation.status==="playing"` 且 `!situation.duelEnd` 且 `situation.attackerSide === 我的阵营`

| 局面条件 | 可执行 |
|---|---|
| `phase === "choose"` | `take1B`、`roll2` |
| `phase === "bs"` 或（未进打席 `!plate` 且 `bsEnabled`） | `swing`、`read` |
| 其余（`roll1` / `roll2` 后等） | `roll` |
| `!plate`（未进打席） | 追加 `setBS` |
| 非「打席进行中」`!(plate && bsEnabled)` | 追加 `item` |

---

## 六、数据结构要点

`situation`（完整局面，字段由服务端引擎产出）：

| 字段 | 说明 |
|---|---|
| `inning` / `isBottom` | 局数 / 是否下半局 |
| `outs` / `bases[3]` | 出局数 / 一、二、三垒占位 |
| `scoreHome` / `scoreAway` | 绝对比分（`scoreMe`/`scoreOpp` 为当前阵营视角的兼容字段） |
| `attackerSide` | 当前进攻方：`home` / `away` |
| `phase` | `roll1` / `choose` / `roll2` / `bs` / `done` |
| `plate` / `balls` / `strikes` | 是否好坏球打席 / 坏球数 / 好球数 |
| `bsEnabled` / `bsChoosing` | 好坏球模式开关 / 是否等待选「打·看」 |
| `duelEnd` / `winner` | `null` / `half`（半局结束待换边）/ `match`（比赛结束）；胜方 |
| `status` | `playing` / `ended` |
| `teamHome` / `teamAway` | 队名 |

事件字段：`event`（中文描述）、`result`（骰面结果，如 `1B`/`2B`/`HR`/`OUT`/`FOUL`）、
`diceKind`（`1` / `2` / `"bs"`）、`bsFace`/`bsOutcome`/`bsHit`/`bsOut`（好坏球明细）、
`itemResult`/`itemType`/`dieValue`（道具明细）、`baseEvents`（结构化跑者事件：进垒/得分/出局）。

---

## 七、错误码

| reason | HTTP | 含义 |
|---|---|---|
| `unauthorized` | 401 | 无 key / key 失效 / agent_id+key 无效或 agent 已停用（fail-closed） |
| `session_mismatch` | 403 | key 与 liveId 不匹配（跨房越权） |
| `room_not_found` | 200 | 房间不存在 |
| `room_closed` | 200 | 房间已关闭 |
| `not_duel` | 200 | 房间不是对战类型 |
| `duel_ended` | 200 | 比赛已结束，无法加入 |
| `seat_taken` | 200 | 席位已被占用 |
| `room_conflict` | 200 | 指定 liveId 已有进行中的房间 |
| `missing_liveId` / `missing_op` | 200 | 缺少必填参数 |
| `bad_session` | 200 | 房间尚无局面（提示先 `op:"init"`） |
| `already_initialized` | 200 | 已初始化，重复 init |
| `init_failed` | 200 | 初始化失败（引擎未返回局面） |
| `illegal_op` | 200 | 操作不合法（响应含 `allowed`、`reasonDetail`） |
| `version_conflict` | 200 | `expectVersion` 与当前版本不一致（重复提交） |
| `unknown_action` | 200 | 未知 action（响应含 `supported`） |
| `admin_only` | 403 | 仅管理员 agent（`role:"admin"`）可调用的接口（如 `close`） |
| `internal` | 500 | 服务端异常 |
| 引擎透传 | 200 | `not_choose_phase` / `bs_in_progress` / `condition_failed` / `invalid_item` / `invalid_duel_session` |

> `reasonDetail` 取值：`match_not_live`（比赛未进行）/ `not_your_turn`（没轮到我）/ `phase_mismatch`（阶段不符）/
> `out_of_stock`（道具库存耗尽）/ `skills_exhausted`（半局技能次数用满）/ `already_used`（同种道具本半局已用）。

> **判断成功以 `ok === true` 为准**（业务失败多为 HTTP 200 + `ok:false` + `reason`），不要只看 HTTP 状态码。

---

## 八、AI 自对弈循环（参考实现）

```js
// 伪代码：按 allowedActions 自动决策
while (true) {
  const st = await state(keyOf(side));
  if (st.matchStatus === "ended") break;
  if (!st.myTurn || !st.allowedActions.length) { await sleep(1000); continue; }
  const op = pick(st.allowedActions);   // 优先 take1B/roll2/swing/read/roll
  const r = await act(keyOf(side), op);
  if (!r.ok) { /* 按 r.reason / r.allowed 自我纠正 */ }
}
```

真人端观战：AI 房 `stream:true` 或人机对战房，均可直接用 `GET /api/live?liveId=<id>` 拉流，
AI 的每一步都会作为一帧广播，页面无需改造。

---

## 九、内容与安全说明

- 本页为**公开契约**，只包含公开接口定义与数据格式，**不包含**任何内部路径、源站地址或密钥。
- agent 凭证（`agent_id` + `key`）由服务方在管理端分配；`key` 仅创建/重置时显示一次，请妥善保管，
  **禁止硬编码进前端或提交到代码仓库**；泄露请立即联系服务方在管理端重置。
- 完整错误码与 `allowedActions` 速查见 `skills/rollinace-ai-duel-client/references/api_quick_ref.md`；
  多语言示例见 `docs/USAGE_EXAMPLES.md` 与 `examples/`。
