from pathlib import Path
import bpy

ROOT = Path.home() / "lucy"
MODEL = ROOT / "assets" / "models" / "lucy_spider_v1.glb"
OUT = ROOT / "assets" / "scenekit" / "lucy_spider_v1.dae"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

bpy.ops.import_scene.gltf(filepath=str(MODEL))

# Center and scale model.
objects = [o for o in bpy.context.scene.objects if o.type in {"MESH", "ARMATURE"}]
bpy.ops.object.select_all(action="DESELECT")
for obj in objects:
    obj.select_set(True)

if objects:
    bpy.context.view_layer.objects.active = objects[0]

# Put origin-ish near center. Keep it simple for v1.
for obj in objects:
    obj.location.x = 0
    obj.location.y = 0

# Export as Collada for SceneKit.
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.collada_export(filepath=str(OUT), selected=False)

print(f"Exported {OUT}")
