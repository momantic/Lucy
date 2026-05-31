import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path.home() / "lucy"
MODEL_PATH = ROOT / "assets" / "models" / "lucy_spider_v1.glb"
SPRITE_ROOT = ROOT / "assets" / "sprites" / "lucy"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def import_model():
    bpy.ops.import_scene.gltf(filepath=str(MODEL_PATH))

    objects = [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "ARMATURE"}]
    if not objects:
        raise RuntimeError("No mesh/armature objects found after importing model.")

    # Center model around origin.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Compute bounds.
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    min_x = min((obj.matrix_world @ Vector(corner)).x for obj in meshes for corner in obj.bound_box)
    max_x = max((obj.matrix_world @ Vector(corner)).x for obj in meshes for corner in obj.bound_box)
    min_y = min((obj.matrix_world @ Vector(corner)).y for obj in meshes for corner in obj.bound_box)
    max_y = max((obj.matrix_world @ Vector(corner)).y for obj in meshes for corner in obj.bound_box)
    min_z = min((obj.matrix_world @ Vector(corner)).z for obj in meshes for corner in obj.bound_box)
    max_z = max((obj.matrix_world @ Vector(corner)).z for obj in meshes for corner in obj.bound_box)

    center = ((min_x + max_x) / 2, (min_y + max_y) / 2, (min_z + max_z) / 2)

    for obj in objects:
        obj.location.x -= center[0]
        obj.location.y -= center[1]
        obj.location.z -= min_z

    # Scale to consistent size.
    height = max_z - min_z
    if height > 0:
        scale = 2.3 / height
        for obj in objects:
            obj.scale *= scale

    return objects


def setup_camera_and_lights():
    bpy.ops.object.light_add(type="AREA", location=(0, -3, 5))
    light = bpy.context.object
    light.name = "Lucy Softbox"
    light.data.energy = 500
    light.data.size = 5

    bpy.ops.object.camera_add(location=(0, -6, 2.4), rotation=(math.radians(68), 0, 0))
    bpy.context.scene.camera = bpy.context.object

    # Transparent render.
    bpy.context.scene.render.film_transparent = True
    bpy.context.scene.render.resolution_x = 512
    bpy.context.scene.render.resolution_y = 512

    # Use Eevee/Workbench-compatible simple settings.
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"


def render_frame(output_path, rotation_z=0.0, bob=0.0, squash=1.0):
    meshes_and_armatures = [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "ARMATURE"}]

    for obj in meshes_and_armatures:
        obj.rotation_euler[2] = rotation_z
        obj.location.z += bob
        obj.scale.z *= squash

    bpy.context.scene.render.filepath = str(output_path)
    bpy.ops.render.render(write_still=True)

    # Restore temporary bob/squash.
    for obj in meshes_and_armatures:
        obj.location.z -= bob
        if squash != 0:
            obj.scale.z /= squash


def render_idle(frames=24):
    out_dir = SPRITE_ROOT / "idle"
    out_dir.mkdir(parents=True, exist_ok=True)

    for i in range(frames):
        angle = math.sin(i / frames * math.tau) * math.radians(2)
        bob = math.sin(i / frames * math.tau) * 0.03
        render_frame(out_dir / f"idle_{i:03d}.png", rotation_z=angle, bob=bob)


def render_crawl(frames=24):
    out_dir = SPRITE_ROOT / "crawl"
    out_dir.mkdir(parents=True, exist_ok=True)

    for i in range(frames):
        angle = math.sin(i / frames * math.tau) * math.radians(4)
        bob = abs(math.sin(i / frames * math.tau)) * 0.04
        render_frame(out_dir / f"crawl_{i:03d}.png", rotation_z=angle, bob=bob)


def render_hop(frames=16):
    out_dir = SPRITE_ROOT / "hop"
    out_dir.mkdir(parents=True, exist_ok=True)

    for i in range(frames):
        t = i / max(frames - 1, 1)
        arc = math.sin(t * math.pi) * 0.35
        squash = 0.92 if i < 3 or i > frames - 4 else 1.04
        render_frame(out_dir / f"hop_{i:03d}.png", rotation_z=0, bob=arc, squash=squash)


def main():
    if not MODEL_PATH.exists():
        raise FileNotFoundError(f"Model not found: {MODEL_PATH}")

    clear_scene()
    import_model()
    setup_camera_and_lights()

    render_idle()
    render_crawl()
    render_hop()

    print("Rendered Lucy sprite frames:")
    print(SPRITE_ROOT)


if __name__ == "__main__":
    main()
