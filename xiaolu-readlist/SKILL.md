---
name: xiaolu-readlist
version: 1.0.0
description: 小鹿待读清单。用户发链接（网页/小红书/BP）到 Hi，自动解析摘要，询问目的（项目/赛道/感兴趣），定时提醒并附全网参考。
---

# xiaolu-readlist — 待读清单

## 触发条件
用户消息包含 URL（http/https），或说「加入待读」「待会读」「帮我存一下」

## 工作流（每次严格按顺序）

### 第一步：解析内容
```bash
python3 {baseDir}/scripts/readlist.py parse --url "URL"
```
输出：1-2句摘要 + 推测类型（BP/网页/小红书/文章）

### 第二步：询问目的（发到 Hi）
```
📌 已收到，帮你存好了～

[摘要1-2句]

这个是 for 什么？
① 项目 — 在看某个项目/公司
② 赛道 — 在研究某个行业方向  
③ 感兴趣 — 纯粹好奇想看看
```

### 第三步：等用户回复，存入队列
```bash
python3 {baseDir}/scripts/readlist.py add \
  --url "URL" \
  --summary "摘要" \
  --purpose "项目|赛道|感兴趣" \
  --tag "用户补充的标签"
```

### 第四步：心跳触发定时提醒
提醒时间规则：
- 上午（00:00-11:59）收到 → 12:00 提醒
- 下午（12:00-15:59）收到 → 16:00 提醒
- 傍晚（16:00-23:59）收到 → 次日 08:00 报告带上

提醒格式：
```
🦌 小鹿提醒：你有 N 条待读

━━━━━━━━━━━━━━━━━━
① [标题/摘要]  ← [目的标签]
   [URL]

━━━━━━━━━━━━━━━━━━
📡 同赛道参考阅读：
• [全网搜索结果1标题] — [来源]
  [URL]
• [全网搜索结果2标题] — [来源]
• [全网搜索结果3标题] — [来源]
```

### 第五步：全网搜索参考
```bash
python3 {baseDir}/scripts/readlist.py search --query "赛道/项目关键词" --count 3
```
使用 web_search 搜索相关内容，过滤掉原文链接本身

## 状态管理
队列文件：`/home/node/.openclaw/workspace/memory/readlist.json`

```json
{
  "items": [
    {
      "id": "uuid",
      "url": "https://...",
      "summary": "1-2句摘要",
      "purpose": "赛道",
      "tag": "AI应用",
      "added_at": "2026-03-29T08:30:00+08:00",
      "remind_at": "2026-03-29T12:00:00+08:00",
      "reminded": false,
      "read": false
    }
  ]
}
```

## HEARTBEAT.md 集成
心跳时检查：
```bash
python3 {baseDir}/scripts/readlist.py check-reminders
```
有到期未提醒的条目 → 触发提醒流程
