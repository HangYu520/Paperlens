#!/usr/bin/env python3
from PIL import Image, ImageDraw
import math, os, subprocess

base = "/Users/hangyu/PaperLens/icon.iconset"
os.makedirs(base, exist_ok=True)

sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = size * 0.12
    cx, cy = size / 2, size / 2

    circle_r = (size - 2 * margin) * 0.38
    angle = math.radians(45)
    handle_len = circle_r * 0.85
    handle_width = circle_r * 0.30

    handle_cx = cx + (circle_r * 0.70) * math.cos(angle)
    handle_cy = cy + (circle_r * 0.70) * math.sin(angle)

    bg_radius = max(1, int(size * 0.055))
    draw.rounded_rectangle(
        [margin * 0.5, margin * 0.5, size - margin * 0.5, size - margin * 0.5],
        radius=bg_radius,
        fill=(74, 144, 217, 255)
    )

    line_w = max(2, int(size * 0.065))
    draw.ellipse(
        [cx - circle_r, cy - circle_r, cx + circle_r, cy + circle_r],
        outline=(255, 255, 255, 255),
        width=line_w
    )

    hw = handle_width / 2
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    p1 = (handle_cx - hw * sin_a, handle_cy + hw * cos_a)
    p2 = (handle_cx + hw * sin_a, handle_cy - hw * cos_a)
    p3 = (handle_cx + handle_len * cos_a - hw * sin_a,
          handle_cy + handle_len * sin_a + hw * cos_a)
    p4 = (handle_cx + handle_len * cos_a + hw * sin_a,
          handle_cy + handle_len * sin_a - hw * cos_a)

    draw.polygon([p1, p3, p4, p2], fill=(255, 255, 255, 255))

    return img

for name, size in sizes.items():
    img = draw_icon(size)
    img.save(os.path.join(base, name))

subprocess.run([
    "iconutil", "-c", "icns", base,
    "-o", "/Users/hangyu/PaperLens/icon.icns"
], check=True)

print("icon.icns created.")
