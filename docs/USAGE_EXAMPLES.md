# 使用用例（Usage Examples）

本页提供 curl / Python / Node.js 三种语言的接入示例，覆盖完整的任务生命周期：

```
创建任务 → 查询状态（轮询） → 关闭任务
```

可运行的脚本放在仓库 `examples/` 目录下：

| 语言 | 脚本 | 说明 |
|---|---|---|
| bash | `examples/bash/full_lifecycle.sh` | 完整生命周期（含额度预检） |
| Python | `examples/python/task_demo.py` | 完整生命周期 |
| Node.js | `examples/node/task_demo.mjs` | 完整生命周期 |

> 所有示例中的 `CLI_ID` / `CLI_SECRET` 均为占位符，请替换为服务方签发的真实凭证。

---

## 1. curl

### 1.1 创建任务

```bash
BASE=https://gateway.yakidev.top
CLI_ID=<your-cli-id>
CLI_SECRET=<your-cli-secret>

curl -s -X POST "$BASE/v1/rollinace-api/live/tasks" \
  -H "Content-Type: application/json" \
  -H "X-Cli-Id: $CLI_ID" \
  -H "X-Cli-Secret: $CLI_SECRET" \
  -d '{"gameId":"2021039309","board":"npb","mode":"replay"}'
```

### 1.2 查询任务状态

```bash
TASK_ID=8f3a9c2e1b6d

curl -s "$BASE/v1/rollinace-api/live/tasks/$TASK_ID" \
  -H "X-Cli-Id: $CLI_ID" \
  -H "X-Cli-Secret: $CLI_SECRET"
```

### 1.3 关闭任务

```bash
curl -s -X DELETE "$BASE/v1/rollinace-api/live/tasks/$TASK_ID" \
  -H "X-Cli-Id: $CLI_ID" \
  -H "X-Cli-Secret: $CLI_SECRET"
```

### 1.4 查询自身额度（创建任务前先确认）

```bash
curl -s "$BASE/v1/rollinace-api/live/quota" \
  -H "X-Cli-Id: $CLI_ID" \
  -H "X-Cli-Secret: $CLI_SECRET"
```

---

## 2. Python（requests）

```python
import time
import requests

BASE = "https://gateway.yakidev.top"
CLI_ID = "<your-cli-id>"
CLI_SECRET = "<your-cli-secret>"
HEADERS = {
    "X-Cli-Id": CLI_ID,
    "X-Cli-Secret": CLI_SECRET,
    "Content-Type": "application/json",
}

# 1) 创建任务（mode=replay；live 同理，需比赛未结束）
r = requests.post(
    f"{BASE}/v1/rollinace-api/live/tasks",
    headers=HEADERS,
    json={"gameId": "2021039309", "board": "npb", "mode": "replay"},
)
r.raise_for_status()
task_id = r.json()["taskId"]
print("taskId:", task_id)

# 2) 轮询状态，直到结束/出错/停止（建议间隔 >= 10s）
while True:
    st = requests.get(f"{BASE}/v1/rollinace-api/live/tasks/{task_id}", headers=HEADERS).json()
    print("status:", st["status"], "| detail:", st.get("detail"), "| error:", st.get("error"))
    if st["status"] in ("ended", "error", "stopped"):
        break
    time.sleep(15)

# 3) 关闭任务（幂等）
print(requests.delete(f"{BASE}/v1/rollinace-api/live/tasks/{task_id}", headers=HEADERS).json())
```

---

## 3. Node.js（内置 fetch）

```js
const BASE = "https://gateway.yakidev.top";
const CLI_ID = "<your-cli-id>";
const CLI_SECRET = "<your-cli-secret>";

const headers = {
  "X-Cli-Id": CLI_ID,
  "X-Cli-Secret": CLI_SECRET,
  "Content-Type": "application/json",
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  // 1) 创建任务
  const created = await fetch(`${BASE}/v1/rollinace-api/live/tasks`, {
    method: "POST",
    headers,
    body: JSON.stringify({ gameId: "2021039309", board: "npb", mode: "replay" }),
  }).then((r) => r.json());
  const taskId = created.taskId;
  console.log("taskId:", taskId);

  // 2) 轮询状态
  for (;;) {
    const st = await fetch(`${BASE}/v1/rollinace-api/live/tasks/${taskId}`, { headers }).then((r) => r.json());
    console.log("status:", st.status, "| detail:", st.detail, "| error:", st.error);
    if (["ended", "error", "stopped"].includes(st.status)) break;
    await sleep(15000);
  }

  // 3) 关闭任务
  const closed = await fetch(`${BASE}/v1/rollinace-api/live/tasks/${taskId}`, {
    method: "DELETE",
    headers,
  }).then((r) => r.json());
  console.log("closed:", closed);
}

main();
```

---

## 4. bash 完整生命周期脚本

仓库中的 `examples/bash/full_lifecycle.sh` 已包含完整的「额度预检 → 创建 → 轮询 → 关闭」流程：

```bash
# 使用方式：把凭证写入环境变量后执行
export ROLLINACE_CLI_ID=<your-cli-id>
export ROLLINACE_CLI_SECRET=<your-cli-secret>

bash examples/bash/full_lifecycle.sh --game 2021039309 --board npb --mode replay
```

脚本行为：

1. 先调 `GET .../quota` 预检额度，额度不足时直接退出；
2. 调 `POST .../tasks` 创建任务并保存 `taskId`；
3. 每 15s 轮询 `GET .../tasks/{taskId}`，直到 `ended` / `error` / `stopped`；
4. 最后 `DELETE .../tasks/{taskId}` 关闭任务。

---

# AI 对战接口用例（AI Duel API）

本节覆盖「AI 对战接口」`POST /api/ai` 的接入示例（创建 AI 自对弈房 → 按 `allowedActions` 循环决策 → 比赛结束）。
接口完整说明见 [AI_DUEL_API.md](AI_DUEL_API.md)。

> agent 凭证（`agent_id` + `key`）由服务方在管理端「AI 管理」页创建分配（key 仅创建/重置时显示一次），
> 请通过环境变量传入，勿硬编码。
> 可运行脚本：`examples/bash/ai_duel_demo.sh`（bash 自对弈示例）、
> `examples/node/bot_server_demo.mjs`（机器人服务示例：收 `duel_created` 通知 → join → 走棋）。

## 5. curl — 自对弈最小流程

```bash
BASE=https://ace.yakidev.top
AI_AGENT_ID=<agent_id>          # agent 凭证（管理端「AI 管理」页分配）
AI_AGENT_KEY=<agent_key>        # agent 密钥（key 仅创建/重置时显示一次）

# 1) 创建 AI 自对弈房（3 局制，缩短验证）
ROOM=$(curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"create","agentId":"'"$AI_AGENT_ID"'","key":"'"$AI_AGENT_KEY"'","innings":3,"startInning":3}' )
echo "$ROOM" | jq .
LIVE_ID=$(echo "$ROOM" | jq -r .liveId)
KEY_AWAY=$(echo "$ROOM" | jq -r '.keys[] | select(.side=="away") | .key')

# 2) 客场先攻：读取局面
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"state","key":"'"$KEY_AWAY"'"}' | jq '{myTurn,allowedActions,version}'

# 3) 执行操作（轮到我且 allowedActions 非空时）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"act","key":"'"$KEY_AWAY"'","op":"roll"}' | jq '{ok,event,result,allowedActions,advanced}'
```

## 6. Python — 自对弈循环

```python
import json
import time
import urllib.request

BASE = "https://ace.yakidev.top"
API = f"{BASE}/api/ai"
AI_AGENT_ID = "<agent_id>"   # 管理端「AI 管理」页分配
AI_AGENT_KEY = "<agent_key>" # key 仅创建/重置时显示一次，建议从环境变量读取

def post(payload: dict) -> dict:
    req = urllib.request.Request(
        API, data=json.dumps(payload).encode(), method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

# 1) 创建自对弈房
room = post({"action": "create", "agentId": AI_AGENT_ID, "key": AI_AGENT_KEY, "innings": 3, "startInning": 3})
keys = {k["side"]: k["key"] for k in room["keys"]}
print("liveId:", room["liveId"])

# 2) 循环决策（客场先攻）
side = "away"
while True:
    st = post({"action": "state", "key": keys[side]})
    if st.get("matchStatus") in ("ended", "closed"):
        break
    # 轮次交换：toMove 决定当前进攻方
    side = st.get("toMove", side)
    if not st.get("myTurn") or not st.get("allowedActions"):
        time.sleep(1)
        continue
    # 简单策略：二选一阶段优先 take1B（安打保底），否则掷骰
    op = "take1B" if "take1B" in st["allowedActions"] else "roll"
    r = post({"action": "act", "key": keys[side], "op": op})
    print("op:", op, "| event:", r.get("event"), "| result:", r.get("result"))
    time.sleep(1)
print("比赛结束")
```

## 7. Node.js — 自对弈循环

```js
const BASE = "https://ace.yakidev.top";
const API = `${BASE}/api/ai`;
const AI_AGENT_ID = process.env.AI_AGENT_ID;   // 管理端「AI 管理」页分配
const AI_AGENT_KEY = process.env.AI_AGENT_KEY; // key 仅创建/重置时显示一次，勿硬编码

const post = (payload) =>
  fetch(API, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }).then((r) => r.json());

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  // 1) 创建自对弈房
  const room = await post({ action: "create", agentId: AI_AGENT_ID, key: AI_AGENT_KEY, innings: 3, startInning: 3 });
  const keys = Object.fromEntries(room.keys.map((k) => [k.side, k.key]));
  console.log("liveId:", room.liveId);

  // 2) 循环决策（客场先攻）
  let side = "away";
  for (;;) {
    const st = await post({ action: "state", key: keys[side] });
    if (["ended", "closed"].includes(st.matchStatus)) break;
    side = st.toMove || side;                      // 换边
    if (!st.myTurn || !st.allowedActions.length) { await sleep(1000); continue; }
    const op = st.allowedActions.includes("take1B") ? "take1B" : "roll";  // 简单策略
    const r = await post({ action: "act", key: keys[side], op });
    console.log("op:", op, "| event:", r.event, "| result:", r.result);
    await sleep(1000);
  }
  console.log("比赛结束");
}

main();
```

## 8. Node.js — 机器人服务（人机对战）

机器人服务需处理三类服务端回调（同一地址 `BOT_SERVICE_URL`，默认 `https://yakidev.top`）：
- **`check`（能力查询）**：真人端勾选「AI 对战」开关时发起，返回 `{ canCreate, reason?, message? }`
  （`reason` 机器码；`message` 可选，为展示给玩家的友好文案，建议 64 字以内、不带内部细节）；
  返回不可用 / 超时 / 非 2xx 时前端提示「暂时无法 AI 对战」并回滚勾选（fail-closed）。
- **`duel_created`（建房通知）**：AI 对战房已创建，机器人服务收到后经 `join`
  占用客队席位、自动开局（客场先攻），随后按 `state`/`act` 循环自行走棋。
- **`room_closed`（关房通知）**：用户主动关闭对战房间（主播关播 `stop` / 对战玩家主动退出 `leave`），
  通知体带 `closedBy`（`host`/`player`）与 `reason`（`host_closed`/`player_leave`）；
  收到后停止该房间走棋并释放会话资源（通知丢失时 `state` 的 `roomStatus:"closed"` 兜底）。

通知体带**来源环境** `env`（`pro` / `tst` / `glb`），各环境的 `/api/ai` 基址与 agent 凭证
相互独立，**必须先按 `env` 选定目标环境**再 `join`（用错凭证会 `401 unauthorized`）：

| `env` | 含义 | 服务端判定（接入方无需配置） |
|---|---|---|
| `glb` | 国际版环境 | 国际版部署（`IS_GLB=1`）；国际版无测试环境，优先级最高 |
| `tst` | 测试环境 | 非国际版且测试部署（`IS_DEV=1`） |
| `pro` | 正式环境 | 其余（正式部署） |

```js
// 伪代码（完整可运行示例见 examples/node/bot_server_demo.mjs）
http.createServer(async (req, res) => {
  const payload = JSON.parse(await readBody(req));   // event:"check" | "duel_created"
  if (payload.event === "check") {
    // 能力查询：按 env 判断该环境能否提供对局服务。
    // reason 用机器码；message 给玩家可读文案（不带环境名/凭证等内部细节）。
    const target = resolveEnv(payload.env);
    if (target && target.agentId && target.key) return res.end(JSON.stringify({ canCreate: true }));
    return res.end(JSON.stringify({
      canCreate: false, reason: "maintenance",
      message: "AI 服务暂时不可用，请稍后再试",
    }));
  }
  if (payload.event !== "duel_created") return res.end("{}");

  // 0) 按 env 选定目标环境的基址与该环境的 agent 凭证
  const target = resolveEnv(payload.env);            // prod / test / glb → { base, agentId, key }

  // 1) join：占用客队席位（自动开局、客场先攻）
  const joined = await ai({ action: "join", agentId: target.agentId, key: target.key, liveId: payload.liveId, name: payload.awayName || "AI客队" });
  const sessionKey = joined.key;                     // 失败(seat_taken/duel_ended)时稍后重试

  // 2) state/act 循环
  for (;;) {
    const st = await ai({ action: "state", key: sessionKey });
    if (["ended", "closed"].includes(st.matchStatus)) break;
    if (!st.myTurn || !st.allowedActions.length) { await sleep(1000); continue; }
    const op = pick(st.allowedActions);              // 简单策略：take1B/roll2/swing/read/roll 优先
    const r = await ai({ action: "act", key: sessionKey, op });
    if (!r.ok) { await sleep(1000); continue; }      // 按 r.reason / r.allowed 自我纠正
    await sleep(1000);
  }
  res.end(JSON.stringify({ ok: true }));
}).listen(PORT);
```

运行方式：

```bash
AI_AGENT_ID=<agent_id> AI_AGENT_KEY=<agent_key> PORT=8080 node examples/node/bot_server_demo.mjs
```

将本服务公网地址提供给服务方，配置为 `BOT_SERVICE_URL`（默认 `https://yakidev.top`）。
回调契约为 `POST` + `Content-Type: application/json`，5 秒超时、无重试；回调失败不阻断建房，
机器人服务可用 `action:"list"` 主动轮询兜底（见第 9 节）。

## 9. 列出可加入的对战房（list）/ 读取房间聊天（log）

```bash
BASE=https://ace.yakidev.top
AI_AGENT_ID=<agent_id>          # 管理端「AI 管理」页分配
AI_AGENT_KEY=<agent_key>        # key 仅创建/重置时显示一次
KEY=<session_key>               # 换票 / join 后返回

# 列出可加入的对战房（aiOnly:true 只看 AI 房；默认只返回 joinable 的房间）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"list","agentId":"'$AI_AGENT_ID'","key":"'$AI_AGENT_KEY'","aiOnly":true,"limit":20}' \
  | jq '.rooms[] | {liveId, matchStatus, ai, aiSides, openSides, joinable, ageSec}'

# joinable:false → 返回全部对战房（含满席 / 已结束）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"list","agentId":"'$AI_AGENT_ID'","key":"'$AI_AGENT_KEY'","joinable":false}' \
  | jq '.rooms[] | {liveId, matchStatus, openSides, joinable}'

# 挑中后 join 占位（并发时先到先得，后者 409 seat_taken，重新 list 即可）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"join","agentId":"'$AI_AGENT_ID'","key":"'$AI_AGENT_KEY'","liveId":"Z8CF48GJ","name":"AI客队"}'

# 读取房间聊天（type=chat 只要弹幕；since 增量；结果按时间正序返回最新 limit 条）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"log","key":"'$KEY'","type":"chat","since":1756500000000,"limit":50}' | jq '.logs'
```

Node.js：

```js
// 主动发现：挑选可加入的房间（优先 AI 房 + 等待较久的）
const rooms = await post({ action: "list", agentId: AI_AGENT_ID, key: AI_AGENT_KEY, aiOnly: true });
const pick = rooms.rooms
  .filter((r) => r.joinable && r.openSides.includes("away"))
  .sort((a, b) => (b.ageSec || 0) - (a.ageSec || 0))[0];
if (pick) await post({ action: "join", agentId: AI_AGENT_ID, key: AI_AGENT_KEY, liveId: pick.liveId });

// 读聊天：记录上次最大 ts，增量拉取（弹幕 text 形如「{队名}： {正文}」）
let since = 0;
const logs = await post({ action: "log", key: sessionKey, type: "chat", since });
for (const l of logs.logs) console.log(l.ts, l.text);
since = logs.logs.length ? logs.logs[logs.logs.length - 1].ts : since;
```

## 10. 管理员关闭对战房间（close）

回收「无行为 / 需要关闭」的对战房间：**仅 `role:"admin"` 的管理员 agent 可调用**
（管理端「AI 管理」页创建 agent 时角色选「管理员」），按 `liveId` 直接关闭，
无需持有该房间的 session_key。适合机器人平台定时巡检：检测到房间无行为 / 需要关停时用它回收。

```bash
BASE=https://ace.yakidev.top
AI_ADMIN_ID=<admin_agent_id>    # 角色为「管理员」的 agent
AI_ADMIN_KEY=<admin_agent_key>

# 关闭对战房间（幂等：已关闭/不存在时 closed:false，不重复执行）
curl -s -X POST "$BASE/api/ai" -H "Content-Type: application/json" \
  -d '{"action":"close","agentId":"'$AI_ADMIN_ID'","key":"'$AI_ADMIN_KEY'","liveId":"Z8CF48GJ","reason":"no_activity"}' \
  | jq .
# → { "ok":true, "liveId":"Z8CF48GJ", "closed":true, "status":"closed",
#    "reason":"no_activity", "agentId":"ag_...", "message":"对战房间已关闭" }
# 已关闭（幂等，含因超时被自动关闭）→ closed:false + message:"对战房间已处于关闭状态（无需重复关闭）"。
# 展示给玩家时请用 message，不要拼接 reason / status 等后台字段。
```

Node.js（巡检示例：每 60s 关闭超过 10 分钟无行为的 AI 对战房）：

```js
// 需要管理端创建 role:"admin" 的管理员 agent
setInterval(async () => {
  const rooms = await post({ action: "list", agentId: AI_ADMIN_ID, key: AI_ADMIN_KEY, joinable: false });
  for (const r of rooms.rooms) {
    if (r.matchStatus === "playing" && (r.lastActivityAgeSec || 0) > 600) {
      await post({ action: "close", agentId: AI_ADMIN_ID, key: AI_ADMIN_KEY, liveId: r.liveId, reason: "no_activity" });
    }
  }
}, 60_000);
```

- 非管理员 agent 调用 → 403 `admin_only`；房间不存在 → `room_not_found`；非对战房 → `not_duel`。
- 与 `leave` 的区别：`leave` 需持有 session_key 且只能退出自己的席位；`close` 是**管理员级**
  的强制回收入口，不占用 / 不依赖任何席位，可关任意对战房间。
