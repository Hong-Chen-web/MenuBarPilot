#!/usr/bin/env python3
"""Generate Claude Code robot app icon for MenuBarPilot."""
from PIL import Image, ImageDraw
import os

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "MenuBarPilot/Assets.xcassets/AppIcon.appiconset")

def draw_robot(size):
    """Draw a Claude Code style robot icon at the given pixel size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # macOS icon: rounded square background
    margin = size * 0.08
    corner = size * 0.22
    bg_rect = [margin, margin, size - margin, size - margin]
    d.rounded_rectangle(bg_rect, radius=corner, fill=(20, 20, 30, 255))

    # Scale unit
    s = size / 1024.0

    # --- Antenna ---
    ax = size / 2
    aw = 6 * s
    ah = 40 * s
    d.rectangle([ax - aw, 150 * s, ax + aw, 200 * s], fill=(249, 115, 22, 255))  # orange stick
    ar = 18 * s  # antenna ball radius
    d.ellipse([ax - ar, 130 * s, ax + ar, 130 * s + ar * 2], fill=(249, 115, 22, 255))

    # --- Head ---
    head_l = 270 * s
    head_t = 210 * s
    head_r = 754 * s
    head_b = 500 * s
    head_rnd = 50 * s
    d.rounded_rectangle([head_l, head_t, head_r, head_b], radius=head_rnd, fill=(249, 115, 22, 255))

    # --- Eyes ---
    eye_y = 310 * s
    eye_r = 40 * s
    # Left eye
    lx = 380 * s
    d.ellipse([lx - eye_r, eye_y - eye_r, lx + eye_r, eye_y + eye_r], fill=(20, 20, 30, 255))
    # Right eye
    rx = 644 * s
    d.ellipse([rx - eye_r, eye_y - eye_r, rx + eye_r, eye_y + eye_r], fill=(20, 20, 30, 255))

    # Eye shine (small white dot)
    shine_r = 14 * s
    d.ellipse([lx - shine_r + 10*s, eye_y - shine_r - 8*s, lx - shine_r + 10*s + shine_r*2, eye_y - shine_r - 8*s + shine_r*2], fill=(255, 255, 255, 200))
    d.ellipse([rx - shine_r + 10*s, eye_y - shine_r - 8*s, rx - shine_r + 10*s + shine_r*2, eye_y - shine_r - 8*s + shine_r*2], fill=(255, 255, 255, 200))

    # --- Mouth ---
    mouth_l = 420 * s
    mouth_t = 420 * s
    mouth_r = 604 * s
    mouth_b = 460 * s
    mouth_rnd = 12 * s
    d.rounded_rectangle([mouth_l, mouth_t, mouth_r, mouth_b], radius=mouth_rnd, fill=(20, 20, 30, 255))

    # --- Neck ---
    neck_w = 100 * s
    neck_h = 30 * s
    neck_x = size / 2 - neck_w / 2
    d.rectangle([neck_x, 500 * s, neck_x + neck_w, 500 * s + neck_h], fill=(234, 88, 12, 255))

    # --- Body ---
    body_l = 280 * s
    body_t = 530 * s
    body_r = 744 * s
    body_b = 720 * s
    body_rnd = 30 * s
    d.rounded_rectangle([body_l, body_t, body_r, body_b], radius=body_rnd, fill=(249, 115, 22, 255))

    # Body detail: chest plate
    chest_l = 380 * s
    chest_t = 570 * s
    chest_r = 644 * s
    chest_b = 680 * s
    chest_rnd = 16 * s
    d.rounded_rectangle([chest_l, chest_t, chest_r, chest_b], radius=chest_rnd, fill=(234, 88, 12, 255))

    # Chest dot
    dot_r = 16 * s
    dot_x = size / 2
    dot_y = 625 * s
    d.ellipse([dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r], fill=(254, 243, 199, 255))

    # --- Arms ---
    arm_w = 60 * s
    arm_h = 120 * s
    arm_rnd = 20 * s
    # Left arm
    d.rounded_rectangle([200 * s, 545 * s, 200 * s + arm_w, 545 * s + arm_h], radius=arm_rnd, fill=(249, 115, 22, 255))
    # Right arm
    d.rounded_rectangle([764 * s, 545 * s, 764 * s + arm_w, 545 * s + arm_h], radius=arm_rnd, fill=(249, 115, 22, 255))

    # --- Legs ---
    leg_w = 80 * s
    leg_h = 110 * s
    leg_rnd = 24 * s
    # Left leg
    d.rounded_rectangle([370 * s, 720 * s, 370 * s + leg_w, 720 * s + leg_h], radius=leg_rnd, fill=(249, 115, 22, 255))
    # Right leg
    d.rounded_rectangle([574 * s, 720 * s, 574 * s + leg_w, 720 * s + leg_h], radius=leg_rnd, fill=(249, 115, 22, 255))

    return img


# macOS icon sizes: filename -> pixel size
ICONS = {
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

# Generate master at 1024, then scale down
master = draw_robot(1024)
master.save("/tmp/mbp_icon_master.png")
print("Master icon: /tmp/mbp_icon_master.png")

for filename, px in ICONS.items():
    icon = master.resize((px, px), Image.LANCZOS)
    path = os.path.join(OUTPUT_DIR, filename)
    icon.save(path)
    print(f"  {filename} ({px}x{px})")

# Update Contents.json
contents = {
    "images": [
        {"idiom": "mac", "scale": "1x", "size": "16x16", "filename": "icon_16x16.png"},
        {"idiom": "mac", "scale": "2x", "size": "16x16", "filename": "icon_16x16@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "32x32", "filename": "icon_32x32.png"},
        {"idiom": "mac", "scale": "2x", "size": "32x32", "filename": "icon_32x32@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png"},
        {"idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_128x128@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png"},
        {"idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_256x256@2x.png"},
        {"idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png"},
        {"idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_512x512@2x.png"},
    ],
    "info": {"author": "xcode", "version": 1},
}

import json
with open(os.path.join(OUTPUT_DIR, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)

print("\nAll icons generated and Contents.json updated!")
