#!/usr/bin/env bash
# xiaojian-meeting — 小鹿会议室预订 CLI
# 用法见 SKILL.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true

# ── 默认配置 ──────────────────────────────────────────
AREA_ID="${XJ_MEETING_AREA_ID:-1}"          # 1=上海
BUILDING_ID="${XJ_MEETING_BUILDING_ID:-45}" # 45=LuOne凯德晶萃
DEFAULT_CAPACITY="${XJ_MEETING_CAPACITY:-3}"
DEFAULT_DURATION="${XJ_MEETING_DURATION:-60}" # 分钟
API_BASE="${XJ_CALENDAR_API:-https://city.xiaohongshu.com}"
SSO_DIR="${XJ_SSO_DIR:-$HOME/.xhs-auth}"

# ── 颜色输出 ──────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'
info()    { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}$*${NC}"; }

# ── 获取 SSO Token ─────────────────────────────────────
get_token() {
    local token_file="$SSO_DIR/token.json"
    if [[ ! -f "$token_file" ]]; then
        # 尝试通过 data-fe-common-sso skill 获取
        local sso_skill="/app/skills/data-fe-common-sso/scripts/data-fe-common-sso.sh"
        if [[ -f "$sso_skill" ]]; then
            bash "$sso_skill" "$SSO_DIR" >/dev/null 2>&1 || true
        fi
    fi
    if [[ -f "$token_file" ]]; then
        python3 -c "import json; d=json.load(open('$token_file')); print(d.get('token') or d.get('access_token') or d.get('hi_token',''))"
    else
        echo ""
    fi
}

# ── API 请求 ───────────────────────────────────────────
api_get() {
    local path="$1"; shift
    local token; token=$(get_token)
    curl -sf "$API_BASE$path" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "User-Agent: xiaojian-meeting/1.0" \
        "$@"
}

api_post() {
    local path="$1"; local body="$2"; shift 2
    local token; token=$(get_token)
    curl -sf -X POST "$API_BASE$path" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "User-Agent: xiaojian-meeting/1.0" \
        -d "$body" \
        "$@"
}

# ── 时间解析 ───────────────────────────────────────────
# 把"明天下午4点"转成 ISO8601
parse_time() {
    python3 - "$1" "$2" << 'PYEOF'
import sys
from datetime import datetime, timedelta
import re

desc = sys.argv[1]  # 如 "2026-03-30T16:00:00+08:00" 或已是标准格式
duration = int(sys.argv[2])  # 分钟

# 如果已经是 ISO 格式直接用
if re.match(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}', desc):
    from datetime import timezone
    dt = datetime.fromisoformat(desc.replace('Z', '+00:00'))
    end = dt + timedelta(minutes=duration)
    print(dt.isoformat())
    print(end.isoformat())
    sys.exit(0)

print("ERROR: 请使用 ISO 格式时间，如 2026-03-30T16:00:00+08:00", file=sys.stderr)
sys.exit(1)
PYEOF
}

# ── 查询空闲会议室 ─────────────────────────────────────
cmd_query() {
    local begin_time="" end_time="" capacity="$DEFAULT_CAPACITY" max_rooms=30

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --begin-time) begin_time="$2"; shift 2 ;;
            --end-time)   end_time="$2";   shift 2 ;;
            --capacity)   capacity="$2";   shift 2 ;;
            --area-id)    AREA_ID="$2";    shift 2 ;;
            --building)   BUILDING_ID="$2";shift 2 ;;
            --max)        max_rooms="$2";  shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$begin_time" || -z "$end_time" ]] && error "需要 --begin-time 和 --end-time"

    section "查询空闲会议室"
    echo "时间：$begin_time → $end_time"
    echo "容量需求：≥ $capacity 人"
    echo ""

    # 调用 calendar skill 的底层能力（已安装）
    local cal_dir="/home/node/.openclaw/workspace/skills/calendar"
    if [[ -f "$cal_dir/run.sh" ]]; then
        chmod +x "$cal_dir/run.sh"
        local result
        result=$("$cal_dir/run.sh" query-meeting-rooms \
            --area-id "$AREA_ID" \
            --building-id-list "$BUILDING_ID" \
            --begin-time "$begin_time" \
            --end-time "$end_time" \
            --max-rooms "$max_rooms" 2>&1)
        echo "$result"
        # 提取空闲且容量合适的房间
        echo ""
        echo "── 推荐（容量 ≥ $capacity 人，无预约）──"
        echo "$result" | python3 "$SCRIPT_DIR/parse_rooms.py" "$capacity" list
    else
        error "calendar skill 未安装，请先运行: clawhub install calendar"
    fi
}

# ── 预订会议室 ─────────────────────────────────────────
cmd_book() {
    local title="会议" begin_time="" end_time="" room_id="" participants=""
    local duration="$DEFAULT_DURATION" capacity="$DEFAULT_CAPACITY"
    local auto_select=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)      title="$2";        shift 2 ;;
            --begin-time) begin_time="$2";   shift 2 ;;
            --end-time)   end_time="$2";     shift 2 ;;
            --duration)   duration="$2";     shift 2 ;;
            --room-id)    room_id="$2";      shift 2 ;;
            --capacity)   capacity="$2";     shift 2 ;;
            --participants) participants="$2"; shift 2 ;;
            --area-id)    AREA_ID="$2";      shift 2 ;;
            --building)   BUILDING_ID="$2";  shift 2 ;;
            --auto)       auto_select=true;  shift ;;
            *) shift ;;
        esac
    done

    [[ -z "$begin_time" ]] && error "需要 --begin-time，格式：2026-03-30T16:00:00+08:00"

    # 自动计算 end_time
    if [[ -z "$end_time" ]]; then
        end_time=$(python3 -c "
from datetime import datetime, timedelta
dt = datetime.fromisoformat('$begin_time')
print((dt + timedelta(minutes=$duration)).isoformat())
")
    fi

    local cal_dir="/home/node/.openclaw/workspace/skills/calendar"
    chmod +x "$cal_dir/run.sh" 2>/dev/null || true

    # 自动选房间
    if [[ -z "$room_id" ]]; then
        section "自动选择会议室"
        local rooms_output
        rooms_output=$("$cal_dir/run.sh" query-meeting-rooms \
            --area-id "$AREA_ID" \
            --building-id-list "$BUILDING_ID" \
            --begin-time "$begin_time" \
            --end-time "$end_time" \
            --max-rooms 50 2>&1)

        room_id=$(echo "$rooms_output" | python3 "$SCRIPT_DIR/parse_rooms.py" "$capacity" first-id)
        if [[ "$room_id" == "NONE" || -z "$room_id" ]]; then
            error "找不到合适的空闲会议室（$capacity 人，$begin_time）"
        fi
        info "自动选定：roomId=$room_id"
    fi

    # 预检
    section "预检会议"
    local preview_args=(
        --title "$title"
        --begin-time "$begin_time"
        --end-time "$end_time"
        --meeting-room-ids "$room_id"
        --format json
    )
    [[ -n "$participants" ]] && preview_args+=(--participant-names "$participants")

    local preview
    preview=$("$cal_dir/run.sh" preview-create-conference "${preview_args[@]}" 2>&1)
    local errors
    errors=$(echo "$preview" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    states = d.get('reserveCheck', {}).get('resultStateList', [])
    fatal = [s for s in states if s not in ('room_less_man', 'common_over_five')]
    print('\n'.join(fatal))
except: pass
" 2>/dev/null || echo "")

    if [[ -n "$errors" ]]; then
        error "预检失败：$errors"
    fi
    info "预检通过"

    # 正式创建
    section "创建会议"
    local create_args=(
        --title "$title"
        --begin-time "$begin_time"
        --end-time "$end_time"
        --meeting-room-ids "$room_id"
    )
    [[ -n "$participants" ]] && create_args+=(--participant-names "$participants")

    local result
    result=$("$cal_dir/run.sh" create-conference "${create_args[@]}" 2>&1)
    echo "$result"

    # 提取会议 ID
    local conf_id
    conf_id=$(echo "$result" | grep -oP '返回 ID: \K\d+' || echo "")

    if [[ -n "$conf_id" ]]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━"
        echo "✅ 会议室预订成功！"
        echo ""
        echo "📅 $title"
        echo "⏰ $(echo "$begin_time" | cut -c1-16 | tr 'T' ' ') → $(echo "$end_time" | cut -c12-16)"
        echo "🏢 上海 LuOne 凯德晶萃广场"
        echo "🆔 会议 ID：$conf_id"
        [[ -n "$participants" ]] && echo "👥 参会人：$participants"
        echo "━━━━━━━━━━━━━━━━━━"
    else
        echo "$result"
    fi
}

# ── 列出区域 ───────────────────────────────────────────
cmd_areas() {
    local cal_dir="/home/node/.openclaw/workspace/skills/calendar"
    chmod +x "$cal_dir/run.sh" 2>/dev/null || true
    "$cal_dir/run.sh" list-meeting-areas 2>&1
}

# ── 帮助 ───────────────────────────────────────────────
cmd_help() {
    cat << 'EOF'
xiaojian-meeting — 小鹿会议室预订

用法：
  meeting.sh query  --begin-time TIME --end-time TIME [--capacity N]
  meeting.sh book   --begin-time TIME [--duration 分钟] [--title 标题] [--capacity N] [--participants "张三,李四"]
  meeting.sh areas

示例：
  # 查询明天下午4-5点空闲会议室（3人）
  meeting.sh query --begin-time 2026-03-30T16:00:00+08:00 --end-time 2026-03-30T17:00:00+08:00 --capacity 3

  # 自动选房间并预订（1小时，默认3人）
  meeting.sh book --begin-time 2026-03-30T14:00:00+08:00 --title "产品评审"

  # 指定参会人
  meeting.sh book --begin-time 2026-03-30T10:00:00+08:00 --duration 90 --title "需求评审" --participants "张三,李四" --capacity 5

默认配置（可用环境变量覆盖）：
  XJ_MEETING_AREA_ID=1        # 上海
  XJ_MEETING_BUILDING_ID=45   # LuOne凯德晶萃
  XJ_MEETING_CAPACITY=3       # 3人
  XJ_MEETING_DURATION=60      # 60分钟
EOF
}

# ── 入口 ───────────────────────────────────────────────
CMD="${1:-help}"; shift 2>/dev/null || true
case "$CMD" in
    query)  cmd_query "$@" ;;
    book)   cmd_book "$@" ;;
    areas)  cmd_areas ;;
    help|-h|--help) cmd_help ;;
    *) echo "未知命令: $CMD"; cmd_help; exit 1 ;;
esac
