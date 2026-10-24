"""Render the app's camera mark. Optional tooling: pip install Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
image = Image.new('RGB', (1024, 1024), '#6D0808')
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((190, 310, 834, 754), radius=78, fill='#EEEAD7')
draw.rounded_rectangle((330, 230, 560, 360), radius=32, fill='#EEEAD7')
draw.ellipse((350, 358, 674, 682), fill='#6D0808')
draw.ellipse((404, 412, 620, 628), fill='#757D6F')
draw.ellipse((696, 360, 740, 404), fill='#6D0808')
for density, size in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    path = root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
    image.resize((size,size), Image.Resampling.LANCZOS).save(path)
image.save(root / 'windows/runner/resources/app_icon.ico', sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
