#!/bin/bash
# 健康数据分析脚本入口
set -e

export HEALTH_GITHUB_PAT="${HEALTH_GITHUB_PAT:-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}"
export HEALTH_GITHUB_OWNER="${HEALTH_GITHUB_OWNER:-yelinglu610-lab}"
export HEALTH_GITHUB_REPO="${HEALTH_GITHUB_REPO:-health-data}"
export HEALTH_GITHUB_BRANCH="${HEALTH_GITHUB_BRANCH:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZE_SCRIPT="/home/node/.openclaw/workspace/health-adviser/analyze_health.py"

python3 "$ANALYZE_SCRIPT"
