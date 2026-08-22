#!/usr/bin/env bash
# Rollin Ace 直播/重播任务 —— 完整生命周期示例
# 流程: 额度预检 -> 创建任务 -> 轮询状态 -> 关闭任务
#
# 用法:
#   export ROLLINACE_CLI_ID=<your-cli-id>
#   export ROLLINACE_CLI_SECRET=<your-cli-secret>
#   bash full_lifecycle.sh --game 2021039309 --board npb --mode replay
#
# 注意: 凭证请通过环境变量传入, 不要写进脚本/提交到仓库。

set -euo pipefail

BASE="https://gateway.yakidev.top"
POLL_INTERVAL=15

CLI_ID="${ROLLINACE_CLI_ID:-}"
CLI_SECRET="${ROLLINACE_CLI_SECRET:-}"
GAME_ID=""
BOARD="npb"
MODE="replay"

usage() {
  echo "用法: $0 --game <gameId> [--board npb|hsb_summer] [--mode live|replay]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --game) GAME_ID="$2"; shift 2 ;;
    --board) BOARD="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$CLI_ID" && -n "$CLI_SECRET" ]] || { echo "请先设置 ROLLINACE_CLI_ID / ROLLINACE_CLI_SECRET 环境变量" >&2; exit 1; }
[[ -n "$GAME_ID" ]] || usage

echo "==> 1/4 查询自身额度 (quota)"
quota=$(curl -s "$BASE/v1/rollinace-api/live/quota" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET")
echo "$quota"

max_replay=$(echo "$quota" | sed -n 's/.*"maxReplay":\([0-9]*\).*/\1/p')
open_replay=$(echo "$quota" | sed -n 's/.*"openReplay":\([0-9]*\).*/\1/p')
if [[ -n "$max_replay" && -n "$open_replay" ]] && (( open_replay >= max_replay )); then
  echo "!! 重播额度已用满 (openReplay=$open_replay / maxReplay=$max_replay), 请先关闭其他任务" >&2
  exit 1
fi

echo "==> 2/4 创建任务 (mode=$MODE, board=$BOARD, gameId=$GAME_ID)"
created=$(curl -s -X POST "$BASE/v1/rollinace-api/live/tasks" \
  -H "Content-Type: application/json" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET" \
  -d "{\"gameId\":\"$GAME_ID\",\"board\":\"$BOARD\",\"mode\":\"$MODE\"}")
echo "$created"

code=$(echo "$created" | sed -n 's/.*"code":\([0-9]*\).*/\1/p')
task_id=$(echo "$created" | sed -n 's/.*"taskId":"\([^"]*\)".*/\1/p')
[[ "$code" == "0" ]] || { echo "!! 创建失败: $created" >&2; exit 1; }
echo "taskId: $task_id"

echo "==> 3/4 轮询状态 (每 ${POLL_INTERVAL}s, 直到 ended/error/stopped)"
while true; do
  st=$(curl -s "$BASE/v1/rollinace-api/live/tasks/$task_id" \
    -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET")
  echo "status=$(echo "$st" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p') detail=$(echo "$st" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p') error=$(echo "$st" | sed -n 's/.*"error":"\([^"]*\)".*/\1/p')"
  status=$(echo "$st" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
  case "$status" in
    ended|error|stopped) break ;;
    *) sleep "$POLL_INTERVAL" ;;
  esac
done

echo "==> 4/4 关闭任务"
curl -s -X DELETE "$BASE/v1/rollinace-api/live/tasks/$task_id" \
  -H "X-Cli-Id: $CLI_ID" -H "X-Cli-Secret: $CLI_SECRET"
echo ""
echo "==> 完成"
