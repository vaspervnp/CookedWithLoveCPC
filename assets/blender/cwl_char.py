"""Shared helpers for the character builders (liberty_build.py, ...).

Loaded with exec() into the builder's namespace, which defines first:
  P      object name prefix ("LIB_")
  SCN    scene name
  OUT    render directory
  MATS   material names (id pass: R = id*16+8)
Scene setup, id/shade materials, mesh primitives, the camera and light shared
with Bill (ortho, 22 degrees, feet on sprite pixel 16, 46.5), face feature
points and rendering of named frames.
"""

import json
import math
import os

import bpy
import bmesh
from mathutils import Vector

FEATURES = {"eye_l": (0.27, 0.02), "eye_r": (-0.27, 0.02),
            "brow_l": (0.28, 0.24), "brow_r": (-0.28, 0.24),
            "nose": (0.0, -0.12), "mouth": (0.0, -0.33)}


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def scene():
    sc = bpy.data.scenes.get(SCN) or bpy.data.scenes.new(SCN)
    for o in list(sc.collection.all_objects):
        if o.name.startswith(P):
            bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.name.startswith(P) and m.users == 0:
            bpy.data.meshes.remove(m)
    r = sc.render
    r.engine = "BLENDER_EEVEE"
    r.resolution_x, r.resolution_y, r.resolution_percentage = 128, 192, 100
    r.pixel_aspect_x, r.pixel_aspect_y = 2.0, 1.0
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0
    sc.view_settings.gamma = 1
    if sc.world is None:
        sc.world = bpy.data.worlds.new(P + "world")
    w = sc.world
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.12, 0.12, 0.13, 1)
    bg.inputs[1].default_value = 1.0
    return sc


def material(name):
    mname = P + name
    m = bpy.data.materials.get(mname) or bpy.data.materials.new(mname)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    v = srgb_to_lin((MATS.index(name) * 16 + 8) / 255)
    em.inputs[0].default_value = (v, 0, 0, 1)
    df = nt.nodes.new("ShaderNodeBsdfDiffuse")
    df.inputs[0].default_value = (0.8, 0.8, 0.8, 1)
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.name = "PASS"
    mix.inputs[0].default_value = 0.0
    nt.links.new(em.outputs[0], mix.inputs[1])
    nt.links.new(df.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def set_pass(shade):
    for name in MATS:
        m = bpy.data.materials.get(P + name)
        if m:
            m.node_tree.nodes["PASS"].inputs[0].default_value = 1.0 if shade else 0.0


def link(sc, ob, parent=None):
    sc.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def empty(sc, name, loc, parent=None):
    e = bpy.data.objects.new(P + name, None)
    e.location = loc
    return link(sc, e, parent)


def mesh_obj(sc, name, bm, mat, loc=(0, 0, 0), parent=None, smooth=True, rot=None):
    me = bpy.data.meshes.new(P + name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material(mat))
    ob = bpy.data.objects.new(P + name, me)
    ob.location = loc
    if rot:
        ob.rotation_euler = [math.radians(a) for a in rot]
    return link(sc, ob, parent)


def sphere(r, scale=(1, 1, 1), seg=24):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    return bm


def cyl(r1, r2, h, scale_y=1.0, seg=24):
    """Cylinder/cone from z=0 (radius r1) down to z=-h (radius r2)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r2, radius2=r1, depth=h)
    for v in bm.verts:
        v.co = Vector((v.co.x, v.co.y * scale_y, v.co.z - h / 2))
    return bm


def box(sx, sy, sz):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    return bm


def cut(bm, keep):
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
    return bm


def poly(points, depth=0.03):
    bm = bmesh.new()
    vs = [bm.verts.new((x, 0, z)) for x, z in points]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.y += depth
    return bm


def face_points(sc, head):
    for name, (fx, fz) in FEATURES.items():
        a, b, c = 0.72, 0.72 * 0.92, 0.72 * 0.95
        t = 1 - (fx / a) ** 2 - (fz / c) ** 2
        empty(sc, "feat_" + name, (fx, -b * math.sqrt(max(t, 0)), fz), head)


def camera_and_light(sc):
    sun_d = bpy.data.lights.get(P + "sun") or bpy.data.lights.new(P + "sun", "SUN")
    sun_d.energy = 1.6
    sun_d.angle = math.radians(2)
    sun = bpy.data.objects.new(P + "sun", sun_d)
    sun.rotation_euler = (math.radians(60), math.radians(-12), math.radians(-18))
    link(sc, sun)
    cam_d = bpy.data.cameras.get(P + "cam") or bpy.data.cameras.new(P + "cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = 5.0
    cam = bpy.data.objects.new(P + "cam", cam_d)
    elev = math.radians(22)
    d = 20
    cam.location = (0, -d * math.cos(elev), 1.6 + d * math.sin(elev))
    cam.rotation_euler = (math.radians(90) - elev, 0, 0)
    link(sc, cam)
    sc.camera = cam


def align_camera(sc):
    """Shift the camera so that the feet point lands on sprite pixel (16, 46.5)."""
    from bpy_extras.object_utils import world_to_camera_view
    cam = sc.camera
    cam.data.shift_x = cam.data.shift_y = 0
    bpy.context.view_layer.update()
    for _ in range(3):
        p = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
        tx, ty = 0.5, 1.0 - 46.5 / 48
        aspect = (sc.render.resolution_y) / (sc.render.resolution_x * sc.render.pixel_aspect_x)
        cam.data.shift_x += (p.x - tx)
        cam.data.shift_y += (p.y - ty) * aspect
        bpy.context.view_layer.update()


def features(sc):
    from bpy_extras.object_utils import world_to_camera_view
    dg = bpy.context.evaluated_depsgraph_get()
    cam = sc.camera
    view = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
    res = {}
    for name in FEATURES:
        p = sc.objects[P + "feat_" + name].matrix_world.translation
        uv = world_to_camera_view(sc, cam, p)
        hit, loc, nrm, idx, ob, mtx = sc.ray_cast(dg, p - view * 30, view)
        vis = bool(hit) and (loc - p).length < 0.06
        res[name] = [uv.x * 32, (1 - uv.y) * 48, vis]
    return res


def render_frames(sc, frames, setup):
    """frames: [(tag, args)]; setup(sc, *args) poses the character. Writes
    id_<tag>.png, shade_<tag>.png and features.json."""
    os.makedirs(OUT, exist_ok=True)
    feats = {}
    for tag, args in frames:
        setup(sc, *args)
        bpy.context.view_layer.update()
        feats[tag] = features(sc)
        for shade in (False, True):
            set_pass(shade)
            sc.eevee.taa_render_samples = 16 if shade else 1
            sc.render.filter_size = 1.5 if shade else 0.0
            sc.render.filepath = os.path.join(OUT, "%s_%s.png" % ("shade" if shade else "id", tag))
            bpy.ops.render.render(write_still=True, scene=sc.name)
    with open(os.path.join(OUT, "features.json"), "w") as f:
        json.dump(feats, f, indent=1)
