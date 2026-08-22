# API 参考

供接入方使用「Rollin Ace 直播/重播任务」接口的完整参考。所有请求均经过网关。

| 项 | 值 |
|---|---|
| Base URL | `https://gateway.yakidev.top` |
| 协议 | HTTPS（HTTP 自动 301 跳转） |
| 内容类型 | `application/json` |
| 接口前缀 | `/v1/rollinace-api/live` |

---

## 1. 鉴权

请求时携带以下任一凭证：

**方式 A（注册制，推荐）**

```
X-Cli-Id: <cliId>
X-Cli-Secret: <secret>
```

**方式 B（JWT）**

```
Authorization: Bearer <token>
```

> 凭证由服务方签发，请妥善保管，勿硬编码进前端。凭证明文泄露请立即联系服务方轮换。

鉴权失败统一返回：

```json
// HTTP 401
{ "error": "unauthorized" }
```

`cliId` 未注册或被禁用时返回 403（`code=1`），详见 §4 错误码。

---

## 2. 统一响应约定

不额外包一层，直接返回 JSON 对象，每个响应含业务码 `code`：

| code | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 参数错误 / 业务拒绝（HTTP 400/403/409） |
| 2 | 内部错误（HTTP 500） |
| 3 | 操作失败（启动/关闭失败，HTTP 500） |
| 4 | 比赛状态检查失败（HTTP 502） |
| 5 | 比赛已结束，不可创建直播（HTTP 409） |

> **判断成功请以 `code == 0` 为准，不要只看 HTTP 状态码。**

---

## 3. 接口

### 3.1 创建任务

```
POST /v1/rollinace-api/live/tasks
```

创建任务并**自动启动**，无需再调用启动接口。

**请求体**（JSON）：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `gameId` | string | 是 | 雅虎比赛 ID（如 `2021039309`） |
| `board` | string | 是 | 赛事版面：`npb`（职棒）/ `hsb_summer`（夏季甲子园） |
| `mode` | string | 是 | 任务类型：`live`（直播）/ `replay`（重播） |
| `env` | string | 否 | 上报环境：`pro`（正式，默认）/ `tst`（测试） |
| `loop` | bool | 否 | **固定传 `false`**；`true` 会被拒绝（`code=1`） |
| `shortName` | string | 否 | 直播间显示短名；留空默认用「主队 vs 客队」完整名称 |
| `homeShortName` | string | 否 | 主队短名 |
| `awayShortName` | string | 否 | 客队短名 |

**成功响应**（HTTP 200）：

```json
{ "code": 0, "taskId": "8f3a9c2e1b6d" }
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `code` | int | 业务码，`0` 表示成功 |
| `taskId` | string | 任务 ID，后续查询/关闭用 |

**错误响应示例**：

```json
// HTTP 400 参数错误
{ "code": 1, "error": "mode must be live or replay" }

// HTTP 409 比赛已结束
{ "code": 5, "error": "比赛已结束，无法创建直播任务，请使用 mode=replay" }

// HTTP 409 额度不足
{ "code": 1, "error": "<额度提示>" }

// HTTP 500 创建失败
{ "code": 2, "error": "..." }
```

> **创建直播的前置校验**：`mode=live` 时服务端会实时检查比赛是否已结束。若比赛已结束，返回 `code=5` 拒绝创建（应改用 `mode=replay`），避免误建直播空房间。
>
> **开放额度限制**：每个注册的 `cliId` 可同时开放的直播/重播任务数受额度（`maxLive` / `maxReplay`）限制，超过上限或额度为 0 时创建被拒（`code=1`，HTTP 409）。额度按「开放中」任务计算（已结束/停止/出错/关闭的任务不占额度）。
>
> **重复创建**：同一场比赛可多次创建任务（各自独立直播间）。如需避免重复，请自行维护 `gameId → taskId` 映射。

### 3.2 查询任务状态

```
GET /v1/rollinace-api/live/tasks/{taskId}
```

**成功响应**（HTTP 200）：

```json
{
  "code": 0,
  "taskId": "8f3a9c2e1b6d",
  "status": "running",
  "detail": "live",
  "error": ""
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `code` | int | 业务码，`0` 表示成功 |
| `taskId` | string | 任务 ID |
| `status` | string | 任务状态（见下表） |
| `detail` | string | 内部原始状态（调试用） |
| `error` | string | 错误信息（仅 `status=error` 时有值） |

**`status` 取值**：

| status | 含义 | 建议动作 |
|---|---|---|
| `waiting` | 已创建，等待开球/比赛未开始 | 继续轮询 |
| `running` | 播放中（直播上报中 / 重播播放中） | 继续轮询 |
| `paused` | 已暂停上报（任务仍在运行） | 可轮询等待恢复 |
| `ended` | 已结束（比赛结束，房间已关闭） | 可关闭任务 |
| `stopped` | 已停止 | 可关闭任务 |
| `error` | 出错（查看 `error` 字段） | 排查或关闭 |
| `deleted` | 任务不存在或已删除（幂等） | 无需处理 |

> 任务不存在时**不返回 404**，返回 HTTP 200 且 `status=deleted`。

### 3.3 关闭任务

```
DELETE /v1/rollinace-api/live/tasks/{taskId}
```

彻底关闭任务：停止上报 → 关闭直播间 → 删除任务记录 → 清理临时数据。

**成功响应**（HTTP 200，幂等——任务不存在也返回成功）：

```json
{ "code": 0, "taskId": "8f3a9c2e1b6d" }
```

### 3.4 查询份额（额度/用量）

```
GET /v1/rollinace-api/live/quota
```

查询当前调用方（或指定调用方）的直播/重播额度与开放中用量。适合在创建任务前确认自身额度是否充足。

可选查询参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `clientId` | string | 要查询的调用方 `cliId`；缺省时查当前凭证对应的调用方自身 |

**成功响应**（HTTP 200）：

```json
{
  "code": 0,
  "cliId": "cli_user",
  "maxLive": 0,
  "maxReplay": 1,
  "openLive": 0,
  "openReplay": 1
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `code` | int | 业务码，`0` 表示成功 |
| `cliId` | string | 被查询的调用方 `cliId` |
| `maxLive` | int | 直播额度上限（`0` 表示禁止创建直播） |
| `maxReplay` | int | 重播额度上限 |
| `openLive` | int | 当前开放中的直播数 |
| `openReplay` | int | 当前开放中的重播数 |

> 安全约束：只能查询自己；查询其他 `cliId` 仅管理员凭证可用，否则返回 HTTP 403（`code=3`）。

---

## 4. 常见错误速查

| HTTP | code | 场景 |
|---|---|---|
| 401 | — | 未提供/无效凭证（`{"error":"unauthorized"}`） |
| 403 | 1 | `cliId` 未注册或已被禁用 |
| 400 | 1 | 缺必填字段、`mode`/`board` 非法、`loop=true` |
| 502 | 4 | 创建 live 任务时比赛状态检查失败 |
| 409 | 5 | 比赛已结束，无法创建直播 |
| 409 | 1 | 超出开放额度 |
| 403 | 3 | 查询他人额度但非管理员（仅 quota 带 `clientId` 查别人时） |
| 500 | 2/3 | 服务端内部错误 |

---

## 5. 补充说明

- **重播数据来源**：`mode=replay` 需要比赛已结束且服务端已缓存该场完整速报数据；若数据未就绪，任务可能进入 `error` 状态。
- **环境区分**：`env=tst` 用于联调，上报到测试直播间；正式运营请使用默认 `pro`。
- **轮询间隔**：查询状态建议间隔 ≥10s，避免对服务造成压力。
