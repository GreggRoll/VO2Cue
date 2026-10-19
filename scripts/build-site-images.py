"""Build optimized web images from the original app artwork. Requires Pillow."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'docs/assets'
SCREENSHOTS = ROOT / 'docs/demo/assets'

with Image.open(ASSETS / 'app-icon.png') as icon:
    for size in (44, 88, 132):
        icon.resize((size, size), Image.Resampling.LANCZOS).save(ASSETS / f'app-icon-{size}.png', optimize=True)
    for size, name in ((32, 'favicon-32.png'), (180, 'apple-touch-icon.png')):
        icon.resize((size, size), Image.Resampling.LANCZOS).save(ASSETS / name, optimize=True)

for name in ('timer', 'watch', 'workouts', 'profile', 'progress', 'widget-small', 'widget-medium', 'widget-complete'):
    original = next(p for p in SCREENSHOTS.glob(f'{name}.*') if p.suffix in ('.jpg', '.png'))
    with Image.open(original) as source:
        sizes = sorted({w for w in (160, 240, 360, 480, 640, 960) if w < source.width} | {source.width})
        for width in sizes:
            height = round(source.height * width / source.width)
            source.resize((width, height), Image.Resampling.LANCZOS).save(SCREENSHOTS / f'{name}-{width}.webp', quality=86, method=6)
print('Built header icons, favicon, touch icon, and responsive WebP images.')
