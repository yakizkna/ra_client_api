#!/usr/bin/env node
/**
 * Rollin Ace 直播/重播任务 —— Node.js 完整生命周期示例
 *
 * 流程: 创建任务 -> 轮询状态 -> 关闭任务
 *
 * 用法:
 *   export ROLLINACE_CLI_ID=<your-cli-id>
 *   export ROLLINACE_CLI_SECRET=<your-cli-secret>
 *   node task_demo.mjs [gameId] [--board npb] [--mode replay]
 *
 * 说明: 使用 Node.js >= 18 内置 fetch, 无需额外依赖。
 */

const BASE = "https://gateway.yakidev.top";
const POLL_INTERVAL = 15000; // 建议 >= 10s
const TERMINAL = new Set(["ended", "error", "stopped"]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function parseArgs() {
  const argv = process.argv.slice(2);
  const opts = { gameId: argv[0], board: "npb", mode: "replay" };
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === "--board") opts.board = argv[++i];
    else if (argv[i] === "--mode") opts.mode = argv[++i];
  }
  return opts;
}

async function main() {
  const { gameId, board, mode } = parseArgs();
  if (!gameId) {
    console.error("用法: node task_demo.mjs <gameId> [--board npb|hsb_summer] [--mode live|replay]");
    process.exit(2);
  }

  const cliId = process.env.ROLLINACE_CLI_ID;
  const cliSecret = process.env.ROLLINACE_CLI_SECRET;
  if (!cliId || !cliSecret) {
    console.error("请先设置 ROLLINACE_CLI_ID / ROLLINACE_CLI_SECRET 环境变量");
    process.exit(2);
  }

  const headers = {
    "X-Cli-Id": cliId,
    "X-Cli-Secret": cliSecret,
    "Content-Type": "application/json",
  };

  // 1) 创建任务
  console.log(`==> 创建任务: ${gameId} ${board} ${mode}`);
  const created = await fetch(`${BASE}/v1/rollinace-api/live/tasks`, {
    method: "POST",
    headers,
    body: JSON.stringify({ gameId, board, mode }),
  }).then((r) => r.json());
  if (created.code !== 0) {
    console.error(`!! 创建失败: ${JSON.stringify(created)}`);
    process.exit(1);
  }
  const taskId = created.taskId;
  console.log("taskId:", taskId);

  // 2) 轮询状态
  console.log(`==> 轮询状态 (每 ${POLL_INTERVAL / 1000}s)`);
  for (;;) {
    const st = await fetch(`${BASE}/v1/rollinace-api/live/tasks/${taskId}`, { headers }).then((r) => r.json());
    console.log(`status=${st.status} detail=${st.detail} error=${st.error}`);
    if (TERMINAL.has(st.status)) break;
    await sleep(POLL_INTERVAL);
  }

  // 3) 关闭任务（幂等）
  console.log("==> 关闭任务");
  const closed = await fetch(`${BASE}/v1/rollinace-api/live/tasks/${taskId}`, {
    method: "DELETE",
    headers,
  }).then((r) => r.json());
  console.log("closed:", closed);
}

main().catch((e) => {
  console.error("!! 出错:", e);
  process.exit(1);
});
