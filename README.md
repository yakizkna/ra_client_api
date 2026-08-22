# Rollin Ace 直播/重播任务 API（用户接入文档）

面向接入方的公开 API 文档与示例仓库。通过本仓库提供的信息，接入方可以在统一的网关域名上管理「棒球速报」的直播 / 重播自动运营任务：

- **创建任务**（直播 `live` / 重播 `replay`，创建后自动启动）
- **查询任务状态**（轮询是否结束 / 出错）
- **关闭任务**（回收资源）
- **查询调用额度**（创建前确认自身额度是否充足）

> 所有请求均经过统一网关，接入方**只需要知道本仓库文档中的域名与接口**，无需关心后端实现。

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

---

## 接口总览

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST` | `/v1/rollinace-api/live/tasks` | 创建任务（直播/重播，创建后自动启动） |
| `GET` | `/v1/rollinace-api/live/tasks/{taskId}` | 查询任务状态 |
| `DELETE` | `/v1/rollinace-api/live/tasks/{taskId}` | 关闭任务（幂等） |
| `GET` | `/v1/rollinace-api/live/quota` | 查询调用额度与开放中用量 |

---

## 建议的接入流程

1. 联系服务方注册 `cliId` 并获取 `secret`；
2. 先用 `GET .../quota` 确认自身直播/重播额度（`maxLive`/`maxReplay`）是否充足；
3. 用 `gameId` + 已知的 `board`/`mode` 调 `POST .../tasks` 创建任务，保存返回的 `taskId`；
4. 定时（建议间隔 ≥10s）调 `GET .../tasks/{taskId}` 查看 `status`；
5. 业务结束或需要中止时，调 `DELETE .../tasks/{taskId}` 关闭；
6. `mode=replay` 时**不要**设置 `loop=true`（会被拒绝）；重播直接传 `mode=replay`。

---

## 仓库结构

```
ra_client_api/
├── README.md                      # 本文档（快速上手）
├── docs/
│   ├── API_REFERENCE.md           # 完整接口参考（字段/错误码/状态表）
│   └── USAGE_EXAMPLES.md          # 多语言使用用例（curl / Python / Node）
├── examples/
│   ├── bash/full_lifecycle.sh     # bash 完整生命周期示例
│   ├── python/task_demo.py        # Python 示例
│   └── node/task_demo.mjs         # Node.js 示例
└── skills/
    └── rollinace-api-client/          # Agent Skill：供其他 AI Agent 直接调用本 API
```

- 完整接口明细（请求/响应字段、错误码、任务状态取值）见 [docs/API_REFERENCE.md](docs/API_REFERENCE.md)。
- 多语言使用用例见 [docs/USAGE_EXAMPLES.md](docs/USAGE_EXAMPLES.md) 与 [examples/](examples/)。
- 供其他 AI Agent 调用的 Skill 见 [skills/rollinace-api-client/](skills/rollinace-api-client/SKILL.md)。

---

## 内容与安全说明

- 本仓库为**公开文档仓库**，只包含公开契约（`gateway.yakidev.top` 与 `/v1/rollinace-api/live/*`），**不包含**任何内部路径、源站地址或密钥。
- 请勿在本仓库中提交任何真实凭证、密钥或 `.env` 文件（已通过 `.gitignore` 拦截常见情况）。
- 鉴权失败统一返回 `HTTP 401`：`{ "error": "unauthorized" }`。
