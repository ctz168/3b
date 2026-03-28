#!/usr/bin/env python3
# ============================================================================
#  Ollama Nanbeige4.1-3B-q4_K_M 速度基准测试脚本
#  跨平台支持: Windows / Linux / macOS
#  用法: python3 bench.py [选项]
#  选项:
#    --model MODEL     模型名称 (默认: softw8/Nanbeige4.1-3B-q4_K_M)
#    --host HOST       Ollama 服务地址 (默认: http://127.0.0.1:11434)
#    --rounds N        测试轮次 (默认: 5)
#    --max-tokens N    每轮最大生成 token 数 (默认: 256)
#    --output FILE     输出结果到 JSON 文件
# ============================================================================

import json
import time
import sys
import os
import argparse
import statistics
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError

# ======================== 默认配置 ========================
DEFAULT_MODEL = "softw8/Nanbeige4.1-3B-q4_K_M"
DEFAULT_HOST = "http://127.0.0.1:11434"
DEFAULT_ROUNDS = 5
DEFAULT_MAX_TOKENS = 256

# 测试 prompt 集合（中英文混合，覆盖不同场景）
TEST_PROMPTS = [
    {"role": "user", "content": "你好，请用一句话介绍你自己。"},
    {"role": "user", "content": "请用中文写一首关于春天的四行短诗。"},
    {"role": "user", "content": "请详细解释什么是人工智能，它的主要应用领域有哪些？"},
    {"role": "user", "content": "What is the capital of France? Please answer briefly."},
    {"role": "user", "content": "Write a Python function to calculate the nth Fibonacci number."},
    {"role": "user", "content": "请将以下句子翻译成英文：今天天气真好，我想出去散步。"},
    {"role": "user", "content": "用简洁的语言解释量子计算的基本原理。"},
]


def generate_stream(host, model, messages, max_tokens=256):
    """
    发送流式生成请求，收集详细的时间指标。
    返回包含 TTFT、生成速度等指标的字典。
    """
    url = f"{host}/api/chat"
    payload = json.dumps({
        "model": model,
        "messages": messages,
        "stream": True,
        "options": {
            "num_predict": max_tokens,
            "temperature": 0.7,
        }
    }).encode("utf-8")

    req = Request(url, data=payload, headers={"Content-Type": "application/json"})

    token_timestamps = []
    full_response = ""
    start_time = None
    first_token_time = None
    prompt_eval_count = 0
    prompt_eval_duration = 0
    eval_count = 0
    eval_duration = 0

    try:
        with urlopen(req, timeout=300) as resp:
            buf = ""
            while True:
                chunk = resp.read(1)
                if not chunk:
                    break
                buf += chunk.decode("utf-8", errors="replace")

                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    # 提取内容
                    content = event.get("message", {}).get("content", "")
                    if content:
                        now = time.time()
                        if start_time is None:
                            start_time = now
                        if first_token_time is None:
                            first_token_time = now
                        token_timestamps.append(now)
                        full_response = content

                    # 提取性能指标（Ollama 在 done 事件中返回）
                    if event.get("done"):
                        prompt_eval_count = event.get("prompt_eval_count", 0)
                        prompt_eval_duration = event.get("prompt_eval_duration", 0)
                        eval_count = event.get("eval_count", 0)
                        eval_duration = event.get("eval_duration", 0)
                        break

    except (URLError, OSError) as e:
        return {"error": str(e)}

    if not token_timestamps or start_time is None:
        return {"error": "No tokens generated"}

    total_time = token_timestamps[-1] - start_time
    ttft = first_token_time - start_time
    gen_time = total_time - ttft if total_time > ttft else total_time

    # 使用 Ollama 返回的精确指标（如果可用）
    if eval_count > 0 and eval_duration > 0:
        # eval_duration 单位是纳秒
        actual_tps = eval_count / (eval_duration / 1e9)
        actual_ttft_ms = prompt_eval_duration / 1e6 if prompt_eval_duration > 0 else ttft * 1000
    else:
        # 回退: 基于时间戳估算
        actual_tps = len(token_timestamps) / gen_time if gen_time > 0 else 0
        actual_ttft_ms = ttft * 1000

    return {
        "ttft_ms": round(actual_ttft_ms, 2),
        "total_time_ms": round(total_time * 1000, 2),
        "gen_time_ms": round(gen_time * 1000, 2),
        "eval_count": eval_count,
        "prompt_eval_count": prompt_eval_count,
        "tokens_per_second": round(actual_tps, 2),
        "response_length": len(full_response),
        "response_preview": full_response[:200],
        "error": None,
    }


def run_single_test(host, model, prompt, max_tokens, round_num, total_rounds):
    """执行单轮测试并打印结果。"""
    label = prompt["content"][:50]
    print(f"  [{round_num}/{total_rounds}] {label}...", end="", flush=True)

    result = generate_stream(host, model, [prompt], max_tokens)

    if result.get("error"):
        print(f" \033[31m失败: {result['error']}\033[0m")
        return None

    print(f" \033[32m{result['tokens_per_second']:.1f} tok/s\033[0m"
          f" (TTFT: {result['ttft_ms']:.0f}ms,"
          f" tokens: {result['eval_count']})")
    return result


def print_summary(results, model, host):
    """打印汇总统计。"""
    if not results:
        print("\n\033[31m所有测试均失败！\033[0m")
        return

    ttfts = [r["ttft_ms"] for r in results]
    tps = [r["tokens_per_second"] for r in results]
    gen_times = [r["gen_time_ms"] for r in results]
    total_times = [r["total_time_ms"] for r in results]
    eval_counts = [r["eval_count"] for r in results]

    print("\n" + "=" * 65)
    print("  测试结果汇总")
    print("=" * 65)

    print(f"\n  模型: {model}")
    print(f"  服务: {host}")
    print(f"  有效测试轮次: {len(results)}")

    print(f"\n  ┌─────────────────────┬──────────┬──────────┬──────────┐")
    print(f"  │ 指标                │ 平均     │ 最小     │ 最大     │")
    print(f"  ├─────────────────────┼──────────┼──────────┼──────────┤")
    print(f"  │ 首字延迟 (TTFT, ms) │ {statistics.mean(ttfts):>8.1f} │ {min(ttfts):>8.1f} │ {max(ttfts):>8.1f} │")
    print(f"  │ 生成速度 (tok/s)    │ {statistics.mean(tps):>8.2f} │ {min(tps):>8.2f} │ {max(tps):>8.2f} │")
    print(f"  │ 生成时间 (ms)       │ {statistics.mean(gen_times):>8.1f} │ {min(gen_times):>8.1f} │ {max(gen_times):>8.1f} │")
    print(f"  │ 总响应时间 (ms)     │ {statistics.mean(total_times):>8.1f} │ {min(total_times):>8.1f} │ {max(total_times):>8.1f} │")
    print(f"  │ 生成 token 数       │ {statistics.mean(eval_counts):>8.1f} │ {min(eval_counts):>8.0f} │ {max(eval_counts):>8.0f} │")

    if len(tps) > 1:
        print(f"  ├─────────────────────┼──────────┴──────────┴──────────┤")
        print(f"  │ 速度标准差 (tok/s)  │ {statistics.stdev(tps):>28.2f} │")

    print(f"  └─────────────────────┴──────────────────────────────────┘")

    # 性能评级
    avg_tps = statistics.mean(tps)
    print(f"\n  性能评级: ", end="")
    if avg_tps >= 30:
        print("\033[32m极快 (>=30 tok/s) - 适合实时对话\033[0m")
    elif avg_tps >= 15:
        print("\033[32m快 (>=15 tok/s) - 交互体验良好\033[0m")
    elif avg_tps >= 8:
        print("\033[33m中等 (>=8 tok/s) - 可接受的使用体验\033[0m")
    elif avg_tps >= 3:
        print("\033[33m较慢 (>=3 tok/s) - 需要等待\033[0m")
    else:
        print("\033[31m慢 (<3 tok/s) - 建议使用 GPU 加速\033[0m")

    print("=" * 65)

    return {
        "model": model,
        "host": host,
        "timestamp": datetime.now().isoformat(),
        "rounds": len(results),
        "summary": {
            "avg_ttft_ms": round(statistics.mean(ttfts), 2),
            "min_ttft_ms": round(min(ttfts), 2),
            "max_ttft_ms": round(max(ttfts), 2),
            "avg_tokens_per_second": round(statistics.mean(tps), 2),
            "min_tokens_per_second": round(min(tps), 2),
            "max_tokens_per_second": round(max(tps), 2),
            "avg_gen_time_ms": round(statistics.mean(gen_times), 2),
            "avg_total_time_ms": round(statistics.mean(total_times), 2),
            "avg_eval_count": round(statistics.mean(eval_counts), 1),
        },
        "details": results,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Ollama Nanbeige4.1-3B-q4_K_M 速度基准测试"
    )
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help=f"模型名称 (默认: {DEFAULT_MODEL})")
    parser.add_argument("--host", default=DEFAULT_HOST,
                        help=f"Ollama 服务地址 (默认: {DEFAULT_HOST})")
    parser.add_argument("--rounds", type=int, default=DEFAULT_ROUNDS,
                        help=f"测试轮次 (默认: {DEFAULT_ROUNDS})")
    parser.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS,
                        help=f"每轮最大生成 token 数 (默认: {DEFAULT_MAX_TOKENS})")
    parser.add_argument("--output", default=None,
                        help="输出结果到 JSON 文件")
    args = parser.parse_args()

    print()
    print("=" * 65)
    print("  Ollama 速度基准测试")
    print("=" * 65)
    print(f"  模型: {args.model}")
    print(f"  服务: {args.host}")
    print(f"  轮次: {args.rounds}")
    print(f"  最大 tokens: {args.max_tokens}")
    print("=" * 65)

    # 检查服务连通性
    print("\n检查服务连通性...", end="", flush=True)
    try:
        with urlopen(f"{args.host}/api/tags", timeout=5) as resp:
            tags = json.loads(resp.read())
            models = [m.get("name", "") for m in tags.get("models", [])]
            print(f" \033[32mOK\033[0m (已安装 {len(models)} 个模型)")
    except Exception as e:
        print(f" \033[31m失败: {e}\033[0m")
        print("\n请确保 Ollama 服务正在运行:")
        print("  Linux/macOS: ollama serve")
        print("  Windows:     start_server.cmd")
        sys.exit(1)

    # 预热
    print("\n[预热] 执行预热推理...", flush=True)
    warmup = generate_stream(args.host, args.model,
                             [TEST_PROMPTS[0]], max_tokens=32)
    if warmup.get("error"):
        print(f"  \033[31m预热失败: {warmup['error']}\033[0m")
        sys.exit(1)
    print(f"  预热完成: {warmup['tokens_per_second']:.1f} tok/s")

    # 正式测试
    print(f"\n开始 {args.rounds} 轮测试:")
    results = []
    for i in range(args.rounds):
        prompt = TEST_PROMPTS[i % len(TEST_PROMPTS)]
        result = run_single_test(
            args.host, args.model, prompt,
            args.max_tokens, i + 1, args.rounds
        )
        if result:
            results.append(result)

    # 汇总
    summary = print_summary(results, args.model, args.host)

    # 输出 JSON
    if args.output and summary:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)
        print(f"\n结果已保存到: {args.output}")


if __name__ == "__main__":
    main()
