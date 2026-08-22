#!/usr/bin/env python3
"""Rollin Ace 直播/重播任务 —— Python 完整生命周期示例

流程: 创建任务 -> 轮询状态 -> 关闭任务

用法:
    export ROLLINACE_CLI_ID=<your-cli-id>
    export ROLLINACE_CLI_SECRET=<your-cli-secret>
    python task_demo.py [gameId] [--board npb] [--mode replay]

依赖: requests (pip install requests)
"""

import argparse
import os
import sys
import time

import requests

BASE = "https://gateway.yakidev.top"
POLL_INTERVAL = 15  # 建议 >= 10s
TERMINAL = {"ended", "error", "stopped"}


def main() -> int:
    parser = argparse.ArgumentParser(description="Rollin Ace 任务生命周期示例")
    parser.add_argument("game_id", help="雅虎比赛 ID，如 2021039309")
    parser.add_argument("--board", default="npb", choices=["npb", "hsb_summer"])
    parser.add_argument("--mode", default="replay", choices=["live", "replay"])
    args = parser.parse_args()

    cli_id = os.environ.get("ROLLINACE_CLI_ID")
    cli_secret = os.environ.get("ROLLINACE_CLI_SECRET")
    if not cli_id or not cli_secret:
        print("请先设置 ROLLINACE_CLI_ID / ROLLINACE_CLI_SECRET 环境变量", file=sys.stderr)
        return 2

    headers = {
        "X-Cli-Id": cli_id,
        "X-Cli-Secret": cli_secret,
        "Content-Type": "application/json",
    }

    # 1) 创建任务
    print("==> 创建任务:", args.game_id, args.board, args.mode)
    resp = requests.post(
        f"{BASE}/v1/rollinace-api/live/tasks",
        headers=headers,
        json={
            "gameId": args.game_id,
            "board": args.board,
            "mode": args.mode,
        },
        timeout=30,
    )
    body = resp.json()
    if body.get("code") != 0:
        print(f"!! 创建失败: {body}", file=sys.stderr)
        return 1
    task_id = body["taskId"]
    print("taskId:", task_id)

    # 2) 轮询状态
    print("==> 轮询状态 (每 %ss)" % POLL_INTERVAL)
    while True:
        st = requests.get(
            f"{BASE}/v1/rollinace-api/live/tasks/{task_id}",
            headers=headers,
            timeout=30,
        ).json()
        print(f"status={st['status']} detail={st.get('detail')} error={st.get('error')}")
        if st["status"] in TERMINAL:
            break
        time.sleep(POLL_INTERVAL)

    # 3) 关闭任务（幂等）
    print("==> 关闭任务")
    closed = requests.delete(
        f"{BASE}/v1/rollinace-api/live/tasks/{task_id}",
        headers=headers,
        timeout=30,
    ).json()
    print("closed:", closed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
