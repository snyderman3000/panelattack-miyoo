import sys
# usage: mkinput.py out start step key[:holdframes] ...   ("wait" skips a slot, "wait:N" waits N frames)
codes = dict(a=57, b=29, x=42, y=56, l=18, r=20, start=28, select=97, up=103, down=108, left=105, right=106, menu=1)
out, start, step = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
f = open(out, "w"); t = start
for k in sys.argv[4:]:
    name, _, hold = k.partition(":")
    hold = int(hold) if hold else 4
    if name == "wait":
        t += hold if _ else step
        continue
    f.write("%d %d 1\n%d %d 0\n" % (t, codes[name], t + hold, codes[name]))
    t += max(step, hold + 10)
print("last frame", t)
