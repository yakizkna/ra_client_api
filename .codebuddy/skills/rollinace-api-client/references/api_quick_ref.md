# Rollin Ace API 快速参考

## 基本信息

| 项 | 值 |
|---|---|
| Base URL | `https://gateway.yakidev.top` |
| 内容类型 | `application/json` |
| 接口前缀 | `/v1/rollinace-api/live` |

## 鉴权

- 方式 A：`X-Cli-Id` + `X-Cli-Secret`（推荐）
- 方式 B：`Authorization: Bearer <token>`
- 失败：HTTP 401 `{ "error": "unauthorized" }`

## 业务码

| code | 含义 | HTTP |
|---|---|---|
| 0 | 成功 | 200 |
| 1 | 参数错误 / 业务拒绝 | 400/403/409 |
| 2 | 内部错误 | 500 |
| 3 | 操作失败（启动/关闭失败） | 500 |
| 4 | 比赛状态检查失败 | 502 |
| 5 | 比赛已结束，不可创建直播 | 409 |

## 创建任务

`POST /v1/rollinace-api/live/tasks`

```json
{
  "gameId": "2021039309",
  "board": "npb",
  "mode": "replay",
  "env": "pro",
  "loop": false
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `gameId` | 是 | 雅虎比赛 ID |
| `board` | 是 | `npb` / `hsb_summer` |
| `mode` | 是 | `live` / `replay` |
| `env` | 否 | `pro`（默认）/ `tst` |
| `loop` | 否 | 仅允许 `false` |
| `shortName` / `homeShortName` / `awayShortName` | 否 | 直播间/队伍短名 |

成功：`{ "code": 0, "taskId": "8f3a9c2e1b6d" }`

## 查询任务状态

`GET /v1/rollinace-api/live/tasks/{taskId}`

```json
{
  "code": 0,
  "taskId": "8f3a9c2e1b6d",
  "status": "running",
  "detail": "live",
  "error": ""
}
```

`status`：`waiting` / `running` / `paused` / `ended` / `stopped` / `error` / `deleted`

任务不存在返回 HTTP 200 且 `status=deleted`（幂等）。

## 关闭任务

`DELETE /v1/rollinace-api/live/tasks/{taskId}` → `{ "code": 0, "taskId": "..." }`

幂等，可重复调用。

## 查询额度

`GET /v1/rollinace-api/live/quota?clientId=<cliId>`

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

`maxLive`/`maxReplay` 为额度上限（`0` 禁止创建），`openLive`/`openReplay` 为当前开放中数量。只能查自己（管理员可查任意）。

## 常见错误速查

| HTTP | code | 场景 |
|---|---|---|
| 401 | — | 无/无效凭证 |
| 403 | 1 | cliId 未注册或被禁用 |
| 400 | 1 | 缺字段、mode/board 非法、loop=true |
| 502 | 4 | 创建 live 时比赛状态检查失败 |
| 409 | 5 | 比赛已结束，改用 replay |
| 409 | 1 | 超出开放额度 |
| 403 | 3 | 非管理员查询他人额度 |
| 500 | 2/3 | 服务端内部错误 |

## curl 速查

```bash
BASE=https://gateway.yakidev.top

# 创建
curl -s -X POST "$BASE/v1/rollinace-api/live/tasks" \
  -H "Content-Type: application/json" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET" \
  -d '{"gameId":"2021039309","board":"npb","mode":"replay"}'

# 查询
curl -s "$BASE/v1/rollinace-api/live/tasks/<taskId>" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"

# 关闭
curl -s -X DELETE "$BASE/v1/rollinace-api/live/tasks/<taskId>" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"

# 额度
curl -s "$BASE/v1/rollinace-api/live/quota" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"
```
