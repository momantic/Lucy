from pathlib import Path
import bpy

ROOT = Path.home() / "lucy"
MODEL = ROOT / "assets" / "models" / "lucy_spider_v1.glb"
OUT_DIR = ROOT / "assets" / "scenekit" / "textures"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

bpy.ops.import_scene.gltf(filepath=str(MODEL))

OUT_DIR.mkdir(parents=True, exist_ok=True)

saved = []

for image in bpy.data.images:
    if not image.name:
        continue

    # Skip generated/internal images without pixels.
    if image.size[0] == 0 or image.size[1] == 0:
        continue

    safe_name = image.name.replace("/", "_").replace("\\", "_").replace(" ", "_")

    # Prefer PNG output for SceneKit stability.
    if not safe_name.lower().endswith((".png", ".jpg", ".jpeg")):
        safe_name += ".png"

    if safe_name.lower().endswith(".jpg") or safe_name.lower().endswith(".jpeg"):
        safe_name = safe_name.rsplit(".", 1)[0] + ".png"

    out_path = OUT_DIR / safe_name

    image.filepath_raw = str(out_path)
    image.file_format = "PNG"
    image.save()

    saved.append(out_path)

print("Saved textures:")
for path in saved:
    print(path)
