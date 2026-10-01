import sys, glob, re
from PIL import Image
fs = sorted(glob.glob((__import__('os').environ.get('PD','/tmp/pd'))+'/*.ppm'), key=lambda f: int(re.findall(r'\d+', f.split('/')[-1])[0]))
idx = [int(a) for a in sys.argv[2:]] or list(range(len(fs)))
out = sys.argv[1]
cols = 2 if len(idx) > 1 else 1
rows = (len(idx) + cols - 1) // cols
W = Image.new('RGB', (640 * cols, 480 * rows))
for k, i in enumerate(idx):
    W.paste(Image.open(fs[i]), ((k % cols) * 640, (k // cols) * 480))
W.save(out)
print(out, [fs[i].split('/')[-1] for i in idx])
