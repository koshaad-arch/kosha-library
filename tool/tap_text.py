# Usage: python3 tap_text.py ui.xml "Text" -> prints "x y" of the first node whose text/desc contains Text
import re, sys
xml = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
want = sys.argv[2].lower()
for m in re.finditer(r'<node [^>]*>', xml):
    n = m.group(0)
    t = (re.search(r' text="([^"]*)"', n) or [None, ''])[1] + ' ' + (re.search(r'content-desc="([^"]*)"', n) or [None, ''])[1]
    if want in t.lower():
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if b:
            x1, y1, x2, y2 = map(int, b.groups())
            print((x1 + x2) // 2, (y1 + y2) // 2)
            sys.exit(0)
sys.exit(1)
