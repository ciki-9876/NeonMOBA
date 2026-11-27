import bpy
import math
import os


def hex_rgba(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


def material(name, color, metallic=0.0, roughness=0.7):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = hex_rgba(color)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hex_rgba(color)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def octagonal_cylinder(name, radius, depth, z, mat, bevel):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8,
        radius=radius,
        depth=depth,
        location=(0.0, 0.0, z),
        rotation=(0.0, 0.0, math.pi / 8.0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel_mod = obj.modifiers.new("single-pixel bevel", "BEVEL")
    bevel_mod.width = bevel
    bevel_mod.segments = 1
    bevel_mod.profile = 0.5
    obj.modifiers.new("weighted corner normals", "WEIGHTED_NORMAL")
    return obj


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

base_mat = material("deep graphite", "101923", metallic=0.12)
edge_mat = material("slate titanium", "586c75", metallic=0.28)
inset_mat = material("inset ceramic", "273b45", metallic=0.06)
teal_mat = material("teal power mark", "8bd7bb", metallic=0.0, roughness=0.85)
gold_mat = material("amber status pixel", "d2a65c", metallic=0.08)

octagonal_cylinder("shadow foot", 1.12, 0.24, 0.12, base_mat, 0.10)
octagonal_cylinder("armored rim", 0.98, 0.19, 0.31, edge_mat, 0.07)
octagonal_cylinder("inset panel", 0.75, 0.06, 0.435, inset_mat, 0.025)

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.49))
core = bpy.context.object
core.name = "teal square relay"
core.dimensions = (0.48, 0.48, 0.055)
core.rotation_euler.z = math.pi / 4.0
core.data.materials.append(teal_mat)
bevel_core = core.modifiers.new("pixel bevel", "BEVEL")
bevel_core.width = 0.035
bevel_core.segments = 1
core.modifiers.new("weighted corner normals", "WEIGHTED_NORMAL")

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.53))
status = bpy.context.object
status.name = "amber status pixel"
status.dimensions = (0.12, 0.12, 0.025)
status.data.materials.append(gold_mat)
status.modifiers.new("weighted corner normals", "WEIGHTED_NORMAL")

for i in range(4):
    angle = math.pi * 0.25 + i * math.pi * 0.5
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=(math.cos(angle) * 0.79, math.sin(angle) * 0.79, 0.43),
    )
    rivet = bpy.context.object
    rivet.name = f"edge rivet {i + 1}"
    rivet.dimensions = (0.09, 0.09, 0.035)
    rivet.data.materials.append(base_mat)

world = bpy.data.worlds.new("transparent sprite world") if not bpy.data.worlds else bpy.data.worlds[0]
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = hex_rgba("9baeb0")
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25

bpy.ops.object.light_add(type="AREA", location=(-2.5, -3.0, 4.5))
light = bpy.context.object
light.name = "large warm pixel-art key"
light.data.energy = 180.0
light.data.shape = "DISK"
light.data.size = 3.0
light.data.color = (1.0, 0.88, 0.68)

bpy.ops.object.camera_add(location=(0.0, 0.0, 6.0))
camera = bpy.context.object
camera.name = "top down sprite camera"
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.55
camera.data.lens = 50.0
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 64
scene.render.resolution_y = 64
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "Medium High Contrast"
scene.view_settings.exposure = 0.0
scene.view_settings.gamma = 1.0
scene.render.image_settings.color_depth = "8"
asset_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "art"))
scene.render.filepath = os.path.join(asset_dir, "pixel_cover.png")
scene.camera.data.dof.use_dof = False

blend_path = os.path.join(asset_dir, "pixel_cover_source.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)
bpy.ops.render.render(write_still=True)
