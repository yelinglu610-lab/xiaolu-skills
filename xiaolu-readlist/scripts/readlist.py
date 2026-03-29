#!/usr/bin/env python3
"""
xiaolu-readlist — 待读清单管理
命令：
  parse   --url URL              解析URL内容，返回摘要
  add     --url --summary --purpose --tag   加入队列
  check-reminders                 检查是否有到期提醒
  list                            列出所有待读
  mark-read --id ID               标记已读
  search  --query Q --count N     全网搜索（输出JSON供上层使用）
"""
import sys, os, json, uuid, re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Asia/Shanghai")
QUEUE_FILE = os.path.expanduser("~/.openclaw/workspace/memory/readlist.json")


# ── 队列读写 ─────────────────────────────────────────────

def load_queue():
    if os.path.exists(QUEUE_FILE):
        with open(QUEUE_FILE) as f:
            return json.load(f)
    return {"items": []}

def save_queue(q):
    os.makedirs(os.path.dirname(QUEUE_FILE), exist_ok=True)
    with open(QUEUE_FILE, "w") as f:
        json.dump(q, f, ensure_ascii=False, indent=2)


# ── 计算提醒时间 ──────────────────────────────────────────

def calc_remind_at(now: datetime) -> datetime:
    """
    上午（00-11:59）→ 当天12:00
    下午（12-15:59）→ 当天16:00
    傍晚（16-23:59）→ 次日08:00
    """
    h = now.hour
    if h < 12:
        return now.replace(hour=12, minute=0, second=0, microsecond=0)
    elif h < 16:
        return now.replace(hour=16, minute=0, second=0, microsecond=0)
    else:
        tomorrow = now + timedelta(days=1)
        return tomorrow.replace(hour=8, minute=0, second=0, microsecond=0)


# ── 解析URL内容 ───────────────────────────────────────────

def cmd_parse(args):
    url = None
    for i, a in enumerate(args):
        if a == "--url" and i+1 < len(args):
            url = args[i+1]

    if not url:
        print(json.dumps({"error": "需要 --url"}))
        return

    # 判断类型
    url_type = "网页"
    if "xiaohongshu.com" in url or "xhslink.com" in url:
        url_type = "小红书"
    elif any(x in url.lower() for x in ["pitch", "deck", "bp", "pdf"]):
        url_type = "BP文档"

    # 抓取内容（简单 curl，取 title + og:description）
    import subprocess, html
    try:
        result = subprocess.run(
            ["curl", "-sL", "--max-time", "10", "--user-agent",
             "Mozilla/5.0 (compatible; XiaoluBot/1.0)",
             url],
            capture_output=True, text=True, timeout=15
        )
        content = result.stdout[:8000]

        # 提取 title
        title_m = re.search(r'<title[^>]*>(.*?)</title>', content, re.I | re.S)
        title = html.unescape(title_m.group(1).strip()) if title_m else ""

        # 提取 og:description 或 meta description
        desc_m = (re.search(r'og:description"[^>]*content="([^"]+)"', content, re.I) or
                  re.search(r'<meta[^>]*name="description"[^>]*content="([^"]+)"', content, re.I) or
                  re.search(r'content="([^"]{30,200})"[^>]*name="description"', content, re.I))
        desc = html.unescape(desc_m.group(1).strip()) if desc_m else ""

        # 提取正文前200字（去标签）
        body = re.sub(r'<[^>]+>', ' ', content)
        body = re.sub(r'\s+', ' ', body).strip()[:300]

        summary = ""
        if title:
            summary += title
        if desc and desc != title:
            summary += "。" + desc[:100]
        if not summary:
            summary = body[:150]

        # 截断到2句话
        sentences = re.split(r'[。！？.!?]', summary)
        summary = "。".join(s.strip() for s in sentences[:2] if s.strip())
        if summary and not summary.endswith(("。", "！", "？")):
            summary += "。"

    except Exception as e:
        title = url
        summary = f"（无法自动解析，请手动描述内容）"

    print(json.dumps({
        "url": url,
        "type": url_type,
        "title": title[:60] if title else url,
        "summary": summary or title or url,
    }, ensure_ascii=False))


# ── 加入队列 ──────────────────────────────────────────────

def cmd_add(args):
    params = {}
    for i, a in enumerate(args):
        if a.startswith("--") and i+1 < len(args):
            params[a[2:]] = args[i+1]

    url     = params.get("url", "")
    summary = params.get("summary", "")
    purpose = params.get("purpose", "感兴趣")
    tag     = params.get("tag", "")

    now = datetime.now(tz=TZ)
    remind_at = calc_remind_at(now)

    item = {
        "id": str(uuid.uuid4())[:8],
        "url": url,
        "summary": summary,
        "purpose": purpose,
        "tag": tag,
        "added_at": now.isoformat(),
        "remind_at": remind_at.isoformat(),
        "reminded": False,
        "read": False,
    }

    q = load_queue()
    q["items"].append(item)
    save_queue(q)

    print(json.dumps({
        "status": "ok",
        "id": item["id"],
        "remind_at": remind_at.strftime("%m/%d %H:%M"),
        "message": f"已加入待读，{remind_at.strftime('%H:%M')} 提醒你"
    }, ensure_ascii=False))


# ── 检查到期提醒 ──────────────────────────────────────────

def cmd_check_reminders(args):
    now = datetime.now(tz=TZ)
    q = load_queue()
    due = []

    for item in q["items"]:
        if item.get("read") or item.get("reminded"):
            continue
        remind_at = datetime.fromisoformat(item["remind_at"])
        if remind_at.tzinfo is None:
            remind_at = remind_at.replace(tzinfo=TZ)
        if now >= remind_at:
            due.append(item)

    if not due:
        print(json.dumps({"due": [], "count": 0}, ensure_ascii=False))
        return

    # 标记已提醒
    for item in q["items"]:
        if item["id"] in [d["id"] for d in due]:
            item["reminded"] = True
    save_queue(q)

    print(json.dumps({"due": due, "count": len(due)}, ensure_ascii=False))


# ── 列出所有待读 ──────────────────────────────────────────

def cmd_list(args):
    q = load_queue()
    unread = [i for i in q["items"] if not i.get("read")]
    print(json.dumps({"items": unread, "count": len(unread)}, ensure_ascii=False))


# ── 标记已读 ──────────────────────────────────────────────

def cmd_mark_read(args):
    item_id = None
    for i, a in enumerate(args):
        if a == "--id" and i+1 < len(args):
            item_id = args[i+1]

    q = load_queue()
    for item in q["items"]:
        if item["id"] == item_id:
            item["read"] = True
            save_queue(q)
            print(json.dumps({"status": "ok", "id": item_id}, ensure_ascii=False))
            return
    print(json.dumps({"status": "not_found"}, ensure_ascii=False))


# ── 搜索关键词 ────────────────────────────────────────────
# 注意：实际搜索由上层AI调用 web_search 工具完成
# 这里只做关键词提取，返回建议搜索词

def cmd_search_keywords(args):
    query = ""
    count = 3
    for i, a in enumerate(args):
        if a == "--query" and i+1 < len(args): query = args[i+1]
        if a == "--count" and i+1 < len(args): count = int(args[i+1])

    # 提取搜索建议
    keywords = [
        query,
        f"{query} 融资",
        f"{query} 行业报告 2025",
        f"{query} 竞品",
    ]
    print(json.dumps({
        "query": query,
        "count": count,
        "suggested_searches": keywords[:count+1]
    }, ensure_ascii=False))


# ── 入口 ─────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: readlist.py <命令> [参数]")
        sys.exit(1)

    cmd = sys.argv[1]
    args = sys.argv[2:]

    dispatch = {
        "parse":           cmd_parse,
        "add":             cmd_add,
        "check-reminders": cmd_check_reminders,
        "list":            cmd_list,
        "mark-read":       cmd_mark_read,
        "search-keywords": cmd_search_keywords,
    }

    if cmd not in dispatch:
        print(f"未知命令: {cmd}")
        sys.exit(1)

    dispatch[cmd](args)
