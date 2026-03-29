#!/usr/bin/env python3
"""从 calendar run.sh 输出中解析空闲会议室"""
import sys

def parse(text, capacity):
    lines = text.split('\n')
    in_table = False
    rooms = []
    for line in lines:
        if '| roomId |' in line:
            in_table = True
            continue
        if in_table and line.startswith('|---'):
            continue
        if in_table and line.startswith('|'):
            cols = [c.strip() for c in line.split('|')[1:-1]]
            if len(cols) >= 7:
                try:
                    room_id = cols[0]
                    name = cols[1]
                    location = cols[3]
                    cap = int(cols[4])
                    events = int(cols[6])
                    if cap >= capacity and events == 0:
                        rooms.append((room_id, name, location, cap))
                except:
                    pass
        elif in_table and line and not line.startswith('|'):
            in_table = False

    rooms.sort(key=lambda x: x[3])  # 按容量升序，优先小的
    return rooms

if __name__ == '__main__':
    capacity = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    mode = sys.argv[2] if len(sys.argv) > 2 else 'list'  # list 或 first-id

    text = sys.stdin.read()
    rooms = parse(text, capacity)

    if mode == 'first-id':
        print(rooms[0][0] if rooms else 'NONE')
    else:
        if not rooms:
            print("暂无合适的空闲会议室")
        else:
            for r in rooms[:8]:
                print(f"🟢 roomId={r[0]}  {r[1]}  {r[2]}  {r[3]}人")
            print(f"\n推荐：{rooms[0][1]}（roomId={rooms[0][0]}，{rooms[0][3]}人）")
