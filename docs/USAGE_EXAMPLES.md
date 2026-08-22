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
