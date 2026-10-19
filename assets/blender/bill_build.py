"""Build Bill (the waiter) in Blender and render his sprite passes.

Run inside Blender (Blender MCP: exec(open(path).read())). Everything lives in
its own scene "CWL_Bill" with objects named "BILL_*", so an open file is not
touched otherwise.

For every direction (down, up, right) and pose (idle, walk 1-4) two images are
rendered at 4x the sprite resolution (128x192, pixel aspect 2:1 like Mode 0):
  id_<dir><pose>.png    flat emission colour per material (material id in R)
  shade_<dir><pose>.png white diffuse lit by a sun (light level)
  features.json         sprite-pixel positions of the face features (eyes,
                        brows, nose, mouth) with visibility, drawn by hand-made
                        rules in post (too small to come out of the render)
tools/render2sprite.py turns them into palette pixel art.
"""

import json

import math
import os

import bpy
import bmesh
from mathutils import Vector

OUT = os.environ.get("CWL_RENDER_DIR", r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\CookedWithLoveCPC\build\render\bill")
SCN = "CWL_Bill"
P = "BILL_"

# material name -> id (R channel = id*16+8 in the id pass)
MATS = ["hair", "skin", "shirt", "vest", "trousers", "shoes", "bowtie",
        "buttons", "eyes", "mouth", "apron", "brows"]


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# --------------------------------------------------------------------------
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
    k = MATS.index(name)
    v = srgb_to_lin((k * 16 + 8) / 255)
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
        m = bpy.data.materials[P + name]
        m.node_tree.nodes["PASS"].inputs[0].default_value = 1.0 if shade else 0.0


# --------------------------------------------------------------------------
def link(sc, ob, parent=None):
    sc.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def empty(sc, name, loc, parent=None):
    e = bpy.data.objects.new(P + name, None)
    e.location = loc
    return link(sc, e, parent)


def mesh_obj(sc, name, bm, mat, loc=(0, 0, 0), parent=None, smooth=True):
    me = bpy.data.meshes.new(P + name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material(mat))
    ob = bpy.data.objects.new(P + name, me)
    ob.location = loc
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


def cut(bm, keep):
    """Delete vertices for which keep(co) is False."""
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
    return bm


def poly(points, depth=0.03):
    """Flat polygon (in the XZ plane) extruded by depth along Y."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, 0, z)) for x, z in points]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.y += depth
    return bm


# --------------------------------------------------------------------------
def build(sc):
    root = empty(sc, "root", (0, 0, 0))
    body = empty(sc, "body", (0, 0, 0), root)       # bobs while walking

    # legs (pivot at the hip)
    for side, sx in (("l", 0.21), ("r", -0.21)):
        hip = empty(sc, "hip_" + side, (sx, 0, 1.18), body)
        mesh_obj(sc, "leg_" + side, cyl(0.19, 0.16, 1.0), "trousers", (0, 0, 0), hip)
        mesh_obj(sc, "shoe_" + side, sphere(0.2, (1.0, 1.75, 0.65)), "shoes", (0, -0.1, -1.06), hip)

    # torso: vest, shirt V, collar, bow tie, buttons
    mesh_obj(sc, "vest", cyl(0.6, 0.5, 0.92, 0.66), "vest", (0, 0, 2.06), body)
    mesh_obj(sc, "shirt_v", poly([(-0.3, 2.05), (0.3, 2.05), (0.0, 1.5)], 0.04), "shirt",
             (0, -0.41, 0), body)
    mesh_obj(sc, "collar", cyl(0.22, 0.25, 0.12), "shirt", (0, -0.02, 2.11), body)
    mesh_obj(sc, "bow_l", poly([(0.0, 2.0), (0.24, 2.09), (0.24, 1.9)], 0.05), "bowtie",
             (0, -0.45, 0), body)
    mesh_obj(sc, "bow_r", poly([(0.0, 2.0), (-0.24, 2.09), (-0.24, 1.9)], 0.05), "bowtie",
             (0, -0.45, 0), body)
    mesh_obj(sc, "bow_knot", sphere(0.07), "bowtie", (0, -0.48, 2.0), body)
    for i, z in enumerate((1.45, 1.27)):
        mesh_obj(sc, "button%d" % i, sphere(0.045), "buttons", (0.17, -0.37, z), body)

    # apron: front half of a cone around the hips, waist to knee
    ap = cut(cyl(0.5, 0.56, 0.9, 0.7), lambda co: co.y < 0.05)
    mesh_obj(sc, "apron", ap, "apron", (0, 0, 1.3), body)
    mesh_obj(sc, "apron_band", cut(cyl(0.48, 0.48, 0.08, 0.68), lambda co: co.y < 0.2),
             "apron", (0, 0, 1.34), body)

    # arms (pivot at the shoulder): sleeve, forearm sleeve, hand
    for side, sx in (("l", 0.68), ("r", -0.68)):
        sh = empty(sc, "shoulder_" + side, (sx, 0, 1.93), body)
        mesh_obj(sc, "upper_" + side, cyl(0.15, 0.13, 0.55), "shirt", (0, 0, 0.05), sh)
        mesh_obj(sc, "fore_" + side, cyl(0.13, 0.12, 0.42), "shirt", (0, 0, -0.48), sh)
        mesh_obj(sc, "hand_" + side, sphere(0.14, (1, 1, 1.1)), "skin", (0, -0.02, -0.98), sh)

    # neck and head
    mesh_obj(sc, "neck", cyl(0.17, 0.17, 0.16), "skin", (0, 0, 2.22), body)
    head = empty(sc, "head", (0, 0, 2.78), body)
    mesh_obj(sc, "skull", sphere(0.72, (1.0, 0.92, 0.95)), "skin", (0, 0, 0), head)
    for side, sx in (("l", 0.71), ("r", -0.71)):
        mesh_obj(sc, "ear_" + side, sphere(0.15, (0.6, 1, 1)), "skin", (sx, 0.02, -0.05), head)
    hair = cut(sphere(0.77, (1.0, 0.97, 0.95)),
               lambda co: co.z > 0.24 - 0.45 * max(0.0, co.y) / 0.77 or co.y > 0.3)
    mesh_obj(sc, "hair", hair, "hair", (0, 0.04, 0.02), head)
    # side parting fringe
    mesh_obj(sc, "fringe", sphere(0.4, (1.3, 0.45, 0.38)), "hair", (0.16, -0.42, 0.43), head)
    mesh_obj(sc, "nose", sphere(0.1, (1, 1, 1.2)), "skin", (0, -0.7, -0.1), head)
    # face feature points on the skull surface (drawn in post)
    for name, (fx, fz) in FEATURES.items():
        a, b, c = 0.72, 0.72 * 0.92, 0.72 * 0.95
        t = 1 - (fx / a) ** 2 - (fz / c) ** 2
        empty(sc, "feat_" + name, (fx, -b * math.sqrt(max(t, 0)), fz), head)

    # light and camera
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
    return root


FEATURES = {"eye_l": (0.27, 0.02), "eye_r": (-0.27, 0.02),
            "brow_l": (0.28, 0.24), "brow_r": (-0.28, 0.24),
            "nose": (0.0, -0.12), "mouth": (0.0, -0.33)}


# --------------------------------------------------------------------------
# poses: (leg swing, arm swing, body bob) in degrees / units
POSES = [(0, 0, 0.0), (28, 24, 0.0), (0, 0, 0.07), (-28, -24, 0.0), (0, 0, 0.07)]
DIRS = [("down", 0), ("up", 180), ("right", 90)]


def pose(sc, leg, arm, bob):
    o = sc.objects
    o[P + "hip_l"].rotation_euler = (math.radians(leg), 0, 0)
    o[P + "hip_r"].rotation_euler = (math.radians(-leg), 0, 0)
    o[P + "shoulder_l"].rotation_euler = (math.radians(-arm), 0, math.radians(4))
    o[P + "shoulder_r"].rotation_euler = (math.radians(arm), 0, math.radians(-4))
    o[P + "body"].location = (0, 0, bob)


def align_camera(sc):
    """Shift the camera so that the feet point (world origin) lands on sprite
    pixel (16, 46.5) of the 32x48 sprite."""
    from bpy_extras.object_utils import world_to_camera_view
    cam = sc.camera
    cam.data.shift_x = cam.data.shift_y = 0
    bpy.context.view_layer.update()
    for _ in range(3):
        p = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
        tx, ty = 0.5, 1.0 - 46.5 / 48
        # shift is relative to the larger image dimension (width here)
        aspect = (sc.render.resolution_y) / (sc.render.resolution_x * sc.render.pixel_aspect_x)
        cam.data.shift_x += (p.x - tx)
        cam.data.shift_y += (p.y - ty) * aspect
        bpy.context.view_layer.update()


def features(sc):
    """Sprite-pixel position and visibility of each face feature."""
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


def render_all(sc):
    os.makedirs(OUT, exist_ok=True)
    root = sc.objects[P + "root"]
    feats = {}
    if True:
        for dname, rot in DIRS:
            root.rotation_euler = (0, 0, math.radians(rot))
            for i, (leg, arm, bob) in enumerate(POSES):
                pose(sc, leg, arm, bob)
                bpy.context.view_layer.update()
                feats["%s%d" % (dname, i)] = features(sc)
                for shade in (False, True):
                    set_pass(shade)
                    sc.eevee.taa_render_samples = 16 if shade else 1
                    sc.render.filter_size = 1.5 if shade else 0.0
                    sc.render.filepath = os.path.join(OUT, "%s_%s%d.png" % ("shade" if shade else "id", dname, i))
                    bpy.ops.render.render(write_still=True, scene=sc.name)
    with open(os.path.join(OUT, "features.json"), "w") as f:
        json.dump(feats, f, indent=1)


def run():
    # work with our scene active (matrices/depsgraph), restore the user's after
    win = bpy.context.window
    old = win.scene
    sc = scene()
    win.scene = sc
    try:
        build(sc)
        bpy.context.view_layer.update()
        align_camera(sc)
        render_all(sc)
    finally:
        win.scene = old
    return sc


if __name__ == "__main__" or True:
    run()
