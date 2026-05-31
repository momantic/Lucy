from pathlib import Path
import math
import bpy

ROOT = Path.home() / "lucy"
MODEL = ROOT / "assets" / "models" / "lucy_spider_v1.glb"
OUT = ROOT / "assets" / "appicon" / "lucy_icon_1024.png"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()

bpy.ops.import_scene.gltf(filepath=str(MODEL))

# Center and scale model.
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not objs:
    raise RuntimeError("No mesh objects found in Lucy model.")

for obj in objs:
    obj.select_set(True)

bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")

# Put model at origin.
for obj in objs:
    obj.location = (0, 0, 0)

# Add camera looking at Lucy's face/front.
camera_data = bpy.data.cameras.new("LucyIconCamera")
camera = bpy.data.objects.new("LucyIconCamera", camera_data)
bpy.context.collection.objects.link(camera)
bpy.context.scene.camera = camera

camera.location = (0, -3.2, 1.15)
camera.rotation_euler = (math.radians(72), 0, 0)
camera.data.lens = 70

# Lighting.
light_data = bpy.data.lights.new("KeyLight", type="AREA")
light = bpy.data.objects.new("KeyLight", light_data)
bpy.context.collection.objects.link(light)
light.location = (0, -2, 3)
light.data.energy = 650
light.data.size = 4

fill_data = bpy.data.lights.new("FillLight", type="POINT")
fill = bpy.data.objects.new("FillLight", fill_data)
bpy.context.collection.objects.link(fill)
fill.location = (2, -2, 2)
fill.data.energy = 90

# Render settings.
bpy.context.scene.render.engine = "BLENDER_EEVEE"
bpy.context.scene.render.resolution_x = 1024
bpy.context.scene.render.resolution_y = 1024
bpy.context.scene.render.film_transparent = True

# Slightly rotate if needed so face is centered.
for obj in objs:
    obj.rotation_euler[0] = math.radians(0)
    obj.rotation_euler[2] = math.radians(0)

OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.context.scene.render.filepath = str(OUT)

bpy.ops.render.render(write_still=True)
print(f"Rendered icon to {OUT}")
