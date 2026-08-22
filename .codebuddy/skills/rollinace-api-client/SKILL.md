---
name: rollinace-api-client
description: 管理 Rollin Ace 棒球速报的直播/重播自动运营任务。通过统一网关 gateway.yakidev.top 的公开契约（/v1/rollinace-api/live/*）创建任务、查询任务状态、关闭任务、查询调用额度。当用户需要创建/管理直播或重播任务、查询任务是否结束、关闭任务回收资源、确认调用额度是否充足时，应使用本技能。
---

# Rollin Ace 直播/重播任务 API 客户端

## 何时使用

当用户需要管理「棒球速报」直播/重播自动运营任务时使用本技能，典型场景：

- 创建一场直播（`live`）或重播（`replay`）任务；
- 查询任务状态（等待开球 / 播放中 / 已结束 / 出错）；
- 关闭任务以回收资源（停止上报、关闭直播间）；
- 创建任务前查询调用方自身的直播/重播额度是否充足。

本技能只使用**公开契约**，所有请求均走统一网关 `https://gateway.yakidev.top`，路径前缀 `/v1/rollinace-api/live`。不要使用任何内部路径或源站地址。

## 前置条件

- 调用方凭证：`X-Cli-Id` / `X-Cli-Secret`（注册制，推荐）或 `Authorization: Bearer <token>`（JWT）。
- 凭证获取方式（按优先级）：
  1. 环境变量 `ROLLINACE_CLI_ID` / `ROLLINACE_CLI_SECRET`；
  2. 直接询问用户提供；
  3. 若用户声称已注册但无法提供凭证，提示用户联系服务方获取，不要编造凭证。
- 凭证**禁止**写入代码或提交到仓库；建议通过环境变量或临时变量传入。

## 接口总览

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST` | `/v1/rollinace-api/live/tasks` | 创建任务（创建后自动启动） |
| `GET` | `/v1/rollinace-api/live/tasks/{taskId}` | 查询任务状态 |
| `DELETE` | `/v1/rollinace-api/live/tasks/{taskId}` | 关闭任务（幂等） |
| `GET` | `/v1/rollinace-api/live/quota` | 查询调用额度与开放中用量 |

## 操作指南

以 curl 为例（`BASE=https://gateway.yakidev.top`，`CLI_ID`/`CLI_SECRET` 为凭证）：

### 创建任务

```bash
curl -s -X POST "$BASE/v1/rollinace-api/live/tasks" \
  -H "Content-Type: application/json" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET" \
  -d '{"gameId":"2021039309","board":"npb","mode":"replay"}'
```

必填字段：

- `gameId`：雅虎比赛 ID（字符串，如 `2021039309`）；
- `board`：`npb`（职棒）或 `hsb_summer`（夏季甲子园）；
- `mode`：`live`（直播）或 `replay`（重播）。

可选字段：

- `env`：`pro`（默认）/ `tst`（测试）；
- `loop`：**固定传 `false`**，`true` 会被拒绝（`code=1`）；
- `shortName` / `homeShortName` / `awayShortName`：直播间与队伍短名。

成功响应：`{ "code": 0, "taskId": "<taskId>" }`。**以 `code == 0` 判断成功，不要只看 HTTP 状态码。**

### 查询任务状态

```bash
curl -s "$BASE/v1/rollinace-api/live/tasks/$TASK_ID" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"
```

`status` 取值：`waiting`（等待开球）/ `running`（播放中）/ `paused` / `ended`（已结束）/ `stopped` / `error`（查看 `error` 字段）/ `deleted`（不存在或已删除，幂等）。

### 关闭任务

```bash
curl -s -X DELETE "$BASE/v1/rollinace-api/live/tasks/$TASK_ID" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"
```

幂等：任务不存在也返回 `code=0`，可安全重复调用。

### 查询额度

```bash
curl -s "$BASE/v1/rollinace-api/live/quota" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"
```

响应含 `maxLive`/`maxReplay`（额度上限，`0` 表示禁止创建）与 `openLive`/`openReplay`（当前开放中数量）。创建任务前建议先查询确认额度充足。

## 关键约定

- 判断成功以业务码 `code == 0` 为准，**不要只看 HTTP 状态码**。
- `mode=live` 时服务端会预检比赛是否已结束；返回 `code=5` 表示比赛已结束，应改用 `mode=replay`。
- `loop` 固定传 `false`，禁止循环重播。
- 轮询任务状态建议间隔 ≥10s，避免对服务造成压力。
- 任务不存在时查询返回 `status=deleted`（HTTP 200），不要误判为 404 错误。
- 同一场比赛可多次创建任务（各自独立直播间）；如需避免重复，自行维护 `gameId → taskId` 映射。

## 完整参考

接口字段、错误码速查表、多语言示例见本技能附带的 `references/api_quick_ref.md`；仓库根目录的 `docs/API_REFERENCE.md` 与 `docs/USAGE_EXAMPLES.md` 也可直接引用。仓库 `examples/` 目录下提供 bash / Python / Node.js 可运行示例。
