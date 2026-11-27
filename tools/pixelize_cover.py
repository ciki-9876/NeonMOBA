from PIL import Image


path = "art/pixel_cover.png"
source = Image.open(path).convert("RGBA")
rgb = source.convert("RGB").quantize(colors=12, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
alpha = source.getchannel("A").point(lambda value: 255 if value >= 96 else 0)
pixel_art = rgb.convert("RGBA")
pixel_art.putalpha(alpha)
pixel_art.save(path)
