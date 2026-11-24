# NEON DRIFT - pre-rendered 3D sprites (run inside Blender)
# Renders the WARDEN boss (16-frame loop) and the XP crystal (8-frame loop).
import bpy, math, os

ROOT = os.path.expanduser('~/NeonDrift')
OUT = ROOT + '/art'
os.makedirs(OUT, exist_ok=True)

# --- clean scene -------------------------------------------------------------
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
for eng in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
    try:
        sc.render.engine = eng
        break
    except Exception:
        pass
sc.render.film_transparent = True
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.resolution_percentage = 100
if sc.world is None:
    sc.world = bpy.data.worlds.new('World')
w = sc.world
try:
    w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[0].default_value = (0.02, 0.02, 0.05, 1)
    w.node_tree.nodes['Background'].inputs[1].default_value = 0.6
except Exception:
    pass


def emis(name, col, strength):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new('ShaderNodeEmission')
    e.inputs[0].default_value = (*col, 1)
    e.inputs[1].default_value = strength
    o = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def metal(name, col, rough=0.28):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (*col, 1)
    b.inputs['Metallic'].default_value = 0.9
    b.inputs['Roughness'].default_value = rough
    return m


def link(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def parent(obj, p):
    obj.parent = p


# --- camera & lights ----------------------------------------------------------
cam_data = bpy.data.cameras.new('Cam')
cam_data.type = 'ORTHO'
cam = bpy.data.objects.new('Cam', cam_data)
sc.collection.objects.link(cam)
cam.location = (0, -5.5, 7.5)
target = bpy.data.objects.new('Target', None)
sc.collection.objects.link(target)
c = cam.constraints.new('TRACK_TO')
c.target = target
c.track_axis = 'TRACK_NEGATIVE_Z'
c.up_axis = 'UP_Y'
sc.camera = cam

sun_d = bpy.data.lights.new('Sun', 'SUN')
sun_d.energy = 3.5
sun = bpy.data.objects.new('Sun', sun_d)
sun.rotation_euler = (math.radians(35), math.radians(-20), 0)
sc.collection.objects.link(sun)
rim_d = bpy.data.lights.new('Rim', 'POINT')
rim_d.energy = 900
rim_d.color = (1.0, 0.2, 0.8)
rim = bpy.data.objects.new('Rim', rim_d)
rim.location = (3, 3, 2)
sc.collection.objects.link(rim)
rim2_d = bpy.data.lights.new('Rim2', 'POINT')
rim2_d.energy = 700
rim2_d.color = (0.1, 0.8, 1.0)
rim2 = bpy.data.objects.new('Rim2', rim2_d)
rim2.location = (-3, -2, 2)
sc.collection.objects.link(rim2)

# --- WARDEN boss --------------------------------------------------------------
boss = bpy.data.objects.new('Warden', None)
sc.collection.objects.link(boss)
spin_a = bpy.data.objects.new('SpinCore', None)   # 5-fold symmetric part
sc.collection.objects.link(spin_a); parent(spin_a, boss)
spin_b = bpy.data.objects.new('SpinRing', None)   # 6-fold symmetric part
sc.collection.objects.link(spin_b); parent(spin_b, boss)

M_DARK = metal('BossHull', (0.05, 0.04, 0.09))
M_MAG = emis('NeonMagenta', (1.0, 0.12, 0.75), 7)
M_CYAN = emis('NeonCyan', (0.1, 0.9, 1.0), 6)
M_CORE = emis('CoreWhite', (1.0, 0.75, 0.95), 14)

bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=(0, 0, 0))
body = bpy.context.active_object; body.name = 'Hull'
link(body, M_DARK); parent(body, spin_a)
bpy.ops.object.shade_flat()

bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.03, location=(0, 0, 0))
wire = bpy.context.active_object; wire.name = 'HullWire'
mod = wire.modifiers.new('wf', 'WIREFRAME'); mod.thickness = 0.035
link(wire, M_MAG); parent(wire, spin_a)

bpy.ops.mesh.primitive_uv_sphere_add(radius=0.34, location=(0, 0, 0.82))
eye = bpy.context.active_object; eye.name = 'Eye'
link(eye, M_CORE); parent(eye, boss)

bpy.ops.mesh.primitive_torus_add(major_radius=1.55, minor_radius=0.055, location=(0, 0, 0))
ring = bpy.context.active_object; ring.name = 'Ring'
link(ring, M_CYAN); parent(ring, spin_b)
bpy.ops.mesh.primitive_torus_add(major_radius=1.25, minor_radius=0.03, location=(0, 0, 0))
ring2 = bpy.context.active_object; ring2.name = 'Ring2'
link(ring2, M_MAG); parent(ring2, spin_b)

for i in range(6):
    a = i * math.tau / 6
    x, y = math.cos(a) * 1.75, math.sin(a) * 1.75
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.22, radius2=0.0, depth=0.75,
                                    location=(x, y, 0),
                                    rotation=(0, math.radians(90), a))
    sp = bpy.context.active_object; sp.name = f'Spike{i}'
    link(sp, M_DARK); parent(sp, spin_b)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.09, location=(math.cos(a) * 2.15, math.sin(a) * 2.15, 0))
    tip = bpy.context.active_object; tip.name = f'Tip{i}'
    link(tip, M_CYAN); parent(tip, spin_b)

# --- XP crystal ----------------------------------------------------------------
gem = bpy.data.objects.new('Crystal', None)
sc.collection.objects.link(gem)
M_GEM = emis('GemGlow', (0.25, 1.0, 0.65), 3.5)
M_GEMW = emis('GemEdge', (0.9, 1.0, 0.95), 9)
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.6, radius2=0, depth=0.9, location=(0, 0, 0.45))
g1 = bpy.context.active_object; link(g1, M_GEM); parent(g1, gem)
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.6, radius2=0, depth=0.9, location=(0, 0, -0.45),
                                rotation=(math.pi, 0, 0))
g2 = bpy.context.active_object; link(g2, M_GEM); parent(g2, gem)
for g in (g1, g2):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.62, radius2=0, depth=0.92,
                                    location=g.location, rotation=g.rotation_euler)
    gw = bpy.context.active_object
    m2 = gw.modifiers.new('wf', 'WIREFRAME'); m2.thickness = 0.05
    link(gw, M_GEMW); parent(gw, gem)


def set_visible(root, vis):
    stack = [root]
    while stack:
        o = stack.pop()
        o.hide_render = not vis
        o.hide_viewport = not vis
        stack.extend(o.children)


def render(path):
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# boss frames
set_visible(gem, False); set_visible(boss, True)
sc.render.resolution_x = sc.render.resolution_y = 192
cam_data.ortho_scale = 5.0
N = 16
for i in range(N):
    t = i / N
    spin_a.rotation_euler.z = t * math.tau / 5
    spin_b.rotation_euler.z = -t * math.tau / 6
    eye.scale = [1.0 + 0.18 * math.sin(t * math.tau)] * 3
    render(f'{OUT}/boss_{i:02d}.png')

# crystal frames
set_visible(boss, False); set_visible(gem, True)
sc.render.resolution_x = sc.render.resolution_y = 48
cam_data.ortho_scale = 2.4
for i in range(8):
    gem.rotation_euler.z = (i / 8) * math.tau / 4
    render(f'{OUT}/gem_{i}.png')

set_visible(boss, True)
bpy.ops.wm.save_as_mainfile(filepath=OUT + '/warden_and_crystal.blend')
print('NEON DRIFT: renders done ->', OUT)
