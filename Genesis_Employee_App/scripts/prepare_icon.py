"""Remove white/light grey background from Genesis logo and resize for app icon."""
import os
import sys

try:
    from PIL import Image
except ImportError:
    print("Installing Pillow...")
    os.system(f"{sys.executable} -m pip install Pillow -q")
    from PIL import Image

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
SOURCE = os.path.join(PROJECT_ROOT, "Genesis.jpeg")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "assets", "icon")
OUTPUT = os.path.join(OUTPUT_DIR, "genesis_icon_foreground.png")
CANVAS_SIZE = 1024
SAFE_ZONE_SIZE = 560  # ~55% - extra margin so G/S not cut by circular mask
BACKGROUND_THRESHOLD = 220  # Remove white AND light grey (R,G,B > this -> transparent)


def main():
    if not os.path.exists(SOURCE):
        print(f"Error: {SOURCE} not found")
        sys.exit(1)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    img = Image.open(SOURCE).convert("RGBA")
    data = list(img.getdata())
    new_data = []
    for item in data:
        r, g, b, a = item
        if r >= BACKGROUND_THRESHOLD and g >= BACKGROUND_THRESHOLD and b >= BACKGROUND_THRESHOLD:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append(item)
    img.putdata(new_data)

    # Get bounding box of non-transparent pixels
    bbox = img.getbbox()
    if bbox is None:
        print("Error: No visible content after background removal")
        sys.exit(1)
    x1, y1, x2, y2 = bbox
    logo_w, logo_h = x2 - x1, y2 - y1
    logo = img.crop(bbox)

    # Resize logo to fit safe zone (max 560x560)
    scale = min(SAFE_ZONE_SIZE / logo_w, SAFE_ZONE_SIZE / logo_h)
    new_w = int(logo_w * scale)
    new_h = int(logo_h * scale)
    logo = logo.resize((new_w, new_h), Image.Resampling.LANCZOS)

    # Center on 1024x1024 transparent canvas
    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (255, 255, 255, 0))
    paste_x = (CANVAS_SIZE - new_w) // 2
    paste_y = (CANVAS_SIZE - new_h) // 2
    canvas.paste(logo, (paste_x, paste_y), logo)
    canvas.save(OUTPUT, "PNG")
    print(f"Saved: {OUTPUT}")


if __name__ == "__main__":
    main()
