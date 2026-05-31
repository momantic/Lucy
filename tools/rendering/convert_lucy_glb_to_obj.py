from pathlib import Path
import bpy

ROOT = Path.home() / "lucy"
MODEL = ROOT / "assets" / "models" / "lucy_spider_v1.glb"
OUT = ROOT / "assets" / "scenekit" / "lucy_spider_v1.obj"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

bpy.ops.import_scene.gltf(filepath=str(MODEL))

OUT.parent.mkdir(parents=True, exist_ok=True)

# Blender 4/5 uses wm.obj_export.
bpy.ops.wm.obj_export(filepath=str(OUT), export_selected_objects=False)

print(f"Exported {OUT}")
