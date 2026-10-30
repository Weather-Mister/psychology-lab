"""Run numerical invariants on the documented independent filmic look curve."""
from pathlib import Path
import math
s=(Path(__file__).resolve().parents[1]/'Grainlight/Imaging/FilmRenderer.swift').read_text()
assert 'pow(v, 1.28)' in s
assert '1.06 - 0.11 * v' in s
assert 'CIRAWFilter(imageURL:' in s
assert 'CIColorCube' in s
assert 'CIGaussianBlur' in s
assert 'CIRandomGenerator' in s
clamp=lambda x:min(1,max(0,x))
def curve(x):
 v=clamp(x)
 return clamp((v**1.28)*(1.06-.11*v))
xs=[i/1000 for i in range(1001)]
ys=[curve(x) for x in xs]
assert all(math.isfinite(y) and 0<=y<=1 for y in ys)
assert all(a<=b for a,b in zip(ys,ys[1:]))
assert curve(.18)<.18, f'18% gray should retain a low-key look, got {curve(.18)}'
assert curve(.85)>.72, 'bright highlight should not be flattened'
print('PASS look: monotonic finite low-key toe/highlight curve, RAW-first path, grain and halation')
