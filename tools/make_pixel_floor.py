from PIL import Image, ImageDraw


SIZE = 64
image = Image.new("RGB", (SIZE, SIZE), "#0b141d")
draw = ImageDraw.Draw(image)

# One low-detail armored plate per tile keeps the arena readable at gameplay zoom.
draw.rectangle((1, 1, 62, 62), fill="#1a2935")
draw.line((3, 3, 60, 3), fill="#2b3d48")
draw.line((3, 4, 3, 60), fill="#263a46")
draw.line((4, 60, 60, 60), fill="#111b25")
draw.line((60, 4, 60, 59), fill="#111b25")

# A short service stripe and status pixel break up the repeating surface.
draw.rectangle((29, 13, 34, 20), fill="#263b47")
draw.rectangle((29, 25, 34, 33), fill="#3f7f76")
draw.point((32, 28), fill="#d2a65c")
draw.rectangle((29, 38, 34, 50), fill="#263b47")

# Four restrained rivets sit inside the corners of the plate.
for px, py in ((8, 8), (55, 8), (8, 55), (55, 55)):
    draw.rectangle((px, py, px + 1, py + 1), fill="#52636d")

# Explicit dark seams make adjacent copies form a consistent grid.
for p in range(SIZE):
    image.putpixel((p, 0), (10, 17, 27))
    image.putpixel((p, SIZE - 1), (10, 17, 27))
    image.putpixel((0, p), (10, 17, 27))
    image.putpixel((SIZE - 1, p), (10, 17, 27))

image.save("art/pixel_floor.png")
