# Usage: python3 tap_text.py ui.xml "Text" -> prints "x y" of the node whose text/desc has a line equal to Text
# (falls back to a line starting with Text).
import html, re, sys
xml = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
want = sys.argv[2].lower()
nodes = []
for m in re.finditer(r'<node [^>]*>', xml):
    n = m.group(0)
    t = html.unescape((re.search(r' text="([^"]*)"', n) or [None, ''])[1] + '\n' + (re.search(r'content-desc="([^"]*)"', n) or [None, ''])[1])
    lines = [l.strip().lower() for l in t.split('\n') if l.strip()]
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
    if b: nodes.append((lines, tuple(map(int, b.groups()))))
for test in (lambda l: l == want, lambda l: l.startswith(want)):
    for lines, (x1, y1, x2, y2) in nodes:
        if any(test(l) for l in lines):
            print((x1 + x2) // 2, (y1 + y2) // 2); sys.exit(0)
sys.exit(1)
