---
name: xiaojian-meeting
version: 1.0.0
description: 小鹿会议室预订。用户说「帮我订会议室」「约个会议室」「抢会议室」时触发。自动查询空闲、选最合适的房间、直接预订，无需用户二次确认。
---

# xiaojian-meeting — 小鹿会议室预订

## 核心脚本
```
{baseDir}/scripts/meeting.sh
```

## 触发词
「帮我订会议室」「约会议室」「抢会议室」「预约会议室」「book meeting room」

## 工作流（每次严格按这个顺序）

### 第一步：解析需求
从用户消息提取：
- **时间**：开始时间（必须）
- **时长**：默认60分钟
- **人数**：默认3人
- **标题**：默认「会议」
- **参会人**：可选，姓名逗号分隔
- **城市/楼栋**：默认上海LuOne

### 第二步：自动查询 + 预订（一步到位）
```bash
bash {baseDir}/scripts/meeting.sh book \
  --begin-time "YYYY-MM-DDTHH:MM:00+08:00" \
  --duration 60 \
  --title "会议标题" \
  --capacity 3
```

脚本会自动：查空闲 → 选最小合适房间 → 预检 → 创建 → 返回确认

### 第三步：发确认到 Hi
```
✅ 会议室预订成功！

📅 [标题]
⏰ [开始时间] → [结束时间]
🏢 上海 LuOne 凯德晶萃广场
🆔 会议 ID：[id]
```

## 规则
- **预检通过直接订，不二次确认**
- 优先选容量刚好匹配的小房间（省资源）
- 人数默认3人，时长默认60分钟
- 需要 calendar skill 已安装（`/home/node/.openclaw/workspace/skills/calendar`）

## 仅查询（不预订）
```bash
bash {baseDir}/scripts/meeting.sh query \
  --begin-time "2026-03-30T16:00:00+08:00" \
  --end-time "2026-03-30T17:00:00+08:00" \
  --capacity 3
```

## 默认配置
| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| XJ_MEETING_AREA_ID | 1 | 上海 |
| XJ_MEETING_BUILDING_ID | 45 | LuOne凯德晶萃 |
| XJ_MEETING_CAPACITY | 3 | 默认人数 |
| XJ_MEETING_DURATION | 60 | 默认时长（分钟）|
