"""Build the customers in Blender and render their part passes.

Run inside Blender (Blender MCP: exec(open(path).read())). Everything lives in
its own scene "CWL_Customer" with objects named "CUST_*".

A customer is three parts that combine freely (tools/custparts.py cuts them
out of the renders): head (sprite lines 0-19), body (20-33) and legs (34-47).
Each style of a part is its own set of objects; for every style, direction
(down, up, right) and pose (idle, walk 1, walk 2) only that style's objects
(plus the neck, shared by head and body so the seam closes) are rendered:
  id_<part><style>_<dir><pose>.png    flat emission colour per material
  shade_<part><style>_<dir><pose>.png white diffuse lit by a sun
  features.json                        face feature positions per head render
Proportions keep every part inside its band: the neck crosses line 20, the
hands and the hem of the top end above line 34, the legs start below it.
Same camera and light as Bill (assets/blender/bill_build.py).
"""

import json
import math
import os

import bpy
import bmesh
from mathutils import Vector

OUT = os.environ.get("CWL_RENDER_DIR", r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\CookedWithLoveCPC\build\render\cust")
SCN = "CWL_Customer"
P = "CUST_"

# material roles -> id (R channel = id*16+8 in the id pass); colours per style
# are chosen in tools/custparts.py
MATS = ["hair", "skin", "top", "trim", "bottom", "shoes", "eyes", "mouth",
        "brows", "beard"]

HEADS = 3
BODIES = 3
LEGS = 3


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
        m = bpy.data.materials.get(P + name)
        if m:                         # (eyes, brows: drawn in post)
            m.node_tree.nodes["PASS"].inputs[0].default_value = 1.0 if shade else 0.0


# --------------------------------------------------------------------------
GROUPS = {}          # "head0", "body1", "legs2", "neck" -> [objects]


def link(sc, ob, parent=None, group=None):
    sc.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    if group:
        GROUPS.setdefault(group, []).append(ob)
    return ob


def empty(sc, name, loc, parent=None):
    e = bpy.data.objects.new(P + name, None)
    e.location = loc
    return link(sc, e, parent)


def mesh_obj(sc, name, bm, mat, loc=(0, 0, 0), parent=None, group=None, smooth=True):
    me = bpy.data.meshes.new(P + name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(material(mat))
    ob = bpy.data.objects.new(P + name, me)
    ob.location = loc
    return link(sc, ob, parent, group)


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


# --------------------------------------------------------------------------
FEATURES = {"eye_l": (0.27, 0.02), "eye_r": (-0.27, 0.02),
            "brow_l": (0.28, 0.24), "brow_r": (-0.28, 0.24),
            "nose": (0.0, -0.12), "mouth": (0.0, -0.33)}

HIP_Z = 1.16         # legs pivot
HEM_Z = 1.07         # bottom of every top: sprite line ~34
SHOULDER_Z = 1.93
HEAD_Z = 2.78


def build(sc):
    GROUPS.clear()
    root = empty(sc, "root", (0, 0, 0))
    body = empty(sc, "body", (0, 0, 0), root)

    # ---- legs styles (pivot at the hip) ----
    hips = {}
    for side, sx in (("l", 0.2), ("r", -0.2)):
        hips[side] = empty(sc, "hip_" + side, (sx, 0, HIP_Z), body)
    for side in ("l", "r"):
        h = hips[side]
        # 0: trousers
        mesh_obj(sc, "l0_leg_" + side, cyl(0.19, 0.16, 1.0), "bottom", (0, 0, 0.02), h, "legs0")
        mesh_obj(sc, "l0_shoe_" + side, sphere(0.2, (1.0, 1.75, 0.65)), "shoes", (0, -0.1, -1.04), h, "legs0")
        # 1: skirt (on the body, below) + bare legs
        mesh_obj(sc, "l1_leg_" + side, cyl(0.13, 0.11, 1.0), "skin", (0, 0, -0.02), h, "legs1")
        mesh_obj(sc, "l1_shoe_" + side, sphere(0.17, (1.0, 1.6, 0.6)), "shoes", (0, -0.08, -1.05), h, "legs1")
        # 2: wide trousers with turn-ups
        mesh_obj(sc, "l2_leg_" + side, cyl(0.2, 0.2, 0.92), "bottom", (0, 0, 0.02), h, "legs2")
        mesh_obj(sc, "l2_cuff_" + side, cyl(0.21, 0.21, 0.08), "trim", (0, 0, -0.88), h, "legs2")
        mesh_obj(sc, "l2_shoe_" + side, sphere(0.2, (1.0, 1.8, 0.6)), "shoes", (0, -0.1, -1.04), h, "legs2")
    mesh_obj(sc, "l0_seat", cyl(0.42, 0.4, 0.2, 0.62), "bottom", (0, 0, HIP_Z + 0.1), body, "legs0")
    mesh_obj(sc, "l1_skirt", cyl(0.44, 0.6, 0.62, 0.7), "bottom", (0, 0, HIP_Z + 0.1), body, "legs1")
    mesh_obj(sc, "l2_seat", cyl(0.43, 0.42, 0.2, 0.62), "bottom", (0, 0, HIP_Z + 0.1), body, "legs2")

    # ---- body styles: top from the shoulders to the hem, arms ----
    top_h = 2.12 - HEM_Z
    # 0: t-shirt (short sleeves, bare arms)
    mesh_obj(sc, "b0_top", cyl(0.58, 0.48, top_h, 0.64), "top", (0, 0, 2.12), body, "body0")
    mesh_obj(sc, "b0_neckband", cyl(0.23, 0.24, 0.06), "trim", (0, -0.02, 2.14), body, "body0")
    # 1: shirt with collar and a placket
    mesh_obj(sc, "b1_top", cyl(0.6, 0.5, top_h, 0.66), "top", (0, 0, 2.12), body, "body1")
    mesh_obj(sc, "b1_collar_l", poly([(0.0, 2.17), (0.26, 2.17), (0.1, 1.98)], 0.04), "trim",
             (0, -0.42, 0), body, "body1")
    mesh_obj(sc, "b1_collar_r", poly([(0.0, 2.17), (-0.26, 2.17), (-0.1, 1.98)], 0.04), "trim",
             (0, -0.42, 0), body, "body1")
    mesh_obj(sc, "b1_placket", poly([(-0.03, 1.98), (0.03, 1.98), (0.03, 1.12), (-0.03, 1.12)], 0.03),
             "trim", (0, -0.43, 0), body, "body1")
    # 2: blouse with a V neck and a belt
    mesh_obj(sc, "b2_top", cyl(0.56, 0.52, top_h, 0.64), "top", (0, 0, 2.12), body, "body2")
    mesh_obj(sc, "b2_v", poly([(-0.24, 2.12), (0.24, 2.12), (0.0, 1.78)], 0.04), "skin",
             (0, -0.4, 0), body, "body2")
    mesh_obj(sc, "b2_belt", cut(cyl(0.53, 0.53, 0.08, 0.66), lambda co: True), "trim",
             (0, 0, HEM_Z + 0.12), body, "body2")
    for side, sx in (("l", 0.66), ("r", -0.66)):
        sh = empty(sc, "shoulder_" + side, (sx, 0, SHOULDER_Z), body)
        # arms end with the hands above the hem line (short arms)
        mesh_obj(sc, "b0_sleeve_" + side, cyl(0.16, 0.15, 0.28), "top", (0, 0, 0.06), sh, "body0")
        mesh_obj(sc, "b0_arm_" + side, cyl(0.12, 0.11, 0.5), "skin", (0, 0, -0.2), sh, "body0")
        mesh_obj(sc, "b0_hand_" + side, sphere(0.13, (1, 1, 1.1)), "skin", (0, -0.02, -0.72), sh, "body0")
        mesh_obj(sc, "b1_arm_" + side, cyl(0.15, 0.13, 0.66), "top", (0, 0, 0.05), sh, "body1")
        mesh_obj(sc, "b1_cuff_" + side, cyl(0.135, 0.135, 0.06), "trim", (0, 0, -0.6), sh, "body1")
        mesh_obj(sc, "b1_hand_" + side, sphere(0.13, (1, 1, 1.1)), "skin", (0, -0.02, -0.72), sh, "body1")
        mesh_obj(sc, "b2_arm_" + side, cyl(0.14, 0.12, 0.62), "top", (0, 0, 0.05), sh, "body2")
        mesh_obj(sc, "b2_hand_" + side, sphere(0.13, (1, 1, 1.1)), "skin", (0, -0.02, -0.68), sh, "body2")

    # ---- neck (head and body renders) ----
    mesh_obj(sc, "neck", cyl(0.17, 0.17, 0.24), "skin", (0, 0, 2.28), body, "neck")

    # ---- head styles ----
    head = empty(sc, "head", (0, 0, HEAD_Z), body)
    for k in range(HEADS):
        g = "head%d" % k
        mesh_obj(sc, "h%d_skull" % k, sphere(0.72, (1.0, 0.92, 0.95)), "skin", (0, 0, 0), head, g)
        for side, sx in (("l", 0.71), ("r", -0.71)):
            mesh_obj(sc, "h%d_ear_%s" % (k, side), sphere(0.15, (0.6, 1, 1)), "skin", (sx, 0.02, -0.05), head, g)
        mesh_obj(sc, "h%d_nose" % k, sphere(0.1, (1, 1, 1.2)), "skin", (0, -0.7, -0.1), head, g)
    # 0: short hair with a quiff
    hair = cut(sphere(0.77, (1.0, 0.97, 0.95)),
               lambda co: co.z > 0.26 - 0.45 * max(0.0, co.y) / 0.77 or co.y > 0.35)
    mesh_obj(sc, "h0_hair", hair, "hair", (0, 0.04, 0.02), head, "head0")
    mesh_obj(sc, "h0_fringe", sphere(0.4, (1.3, 0.45, 0.38)), "hair", (-0.16, -0.42, 0.43), head, "head0")
    # 1: bob cut (covers the ears, ends at the jaw) with a fringe
    bob = cut(sphere(0.82, (1.05, 1.0, 1.0)), lambda co: co.z > -0.42 and (co.y > -0.2 or co.z > 0.3))
    mesh_obj(sc, "h1_bob", bob, "hair", (0, 0.04, 0.0), head, "head1")
    mesh_obj(sc, "h1_fringe", sphere(0.5, (1.2, 0.4, 0.3)), "hair", (0, -0.5, 0.42), head, "head1")
    mesh_obj(sc, "h1_lips", sphere(0.1, (1.6, 0.6, 0.6)), "mouth", (0, -0.66, -0.33), head, "head1")
    # 2: bald top, hair at the sides and back, moustache
    ring = cut(sphere(0.76, (1.0, 0.97, 0.95)), lambda co: -0.3 < co.z < 0.28 and co.y > -0.05)
    mesh_obj(sc, "h2_ring", ring, "hair", (0, 0.03, 0.0), head, "head2")
    mesh_obj(sc, "h2_moustache", sphere(0.12, (2.0, 0.6, 0.6)), "beard", (0, -0.67, -0.24), head, "head2")
    # face feature points on the skull surface (drawn in post)
    for name, (fx, fz) in FEATURES.items():
        a, b, c = 0.72, 0.72 * 0.92, 0.72 * 0.95
        t = 1 - (fx / a) ** 2 - (fz / c) ** 2
        empty(sc, "feat_" + name, (fx, -b * math.sqrt(max(t, 0)), fz), head)

    # ---- light and camera (as for Bill) ----
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


# --------------------------------------------------------------------------
# poses: (leg swing, arm swing, body bob): idle, walk 1, walk 2
POSES = [(0, 0, 0.0), (28, 24, 0.0), (-28, -24, 0.0)]
DIRS = [("down", 0), ("up", 180), ("right", 90)]


def pose(sc, leg, arm, bob):
    o = sc.objects
    o[P + "hip_l"].rotation_euler = (math.radians(leg), 0, 0)
    o[P + "hip_r"].rotation_euler = (math.radians(-leg), 0, 0)
    o[P + "shoulder_l"].rotation_euler = (math.radians(-arm), 0, math.radians(4))
    o[P + "shoulder_r"].rotation_euler = (math.radians(arm), 0, math.radians(-4))
    o[P + "body"].location = (0, 0, bob)


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


def show(groups):
    for g, obs in GROUPS.items():
        for ob in obs:
            ob.hide_render = ob.hide_viewport = g not in groups


def render_all(sc, only=None):
    """Render every style (or only the named ones, e.g. ["head0", "legs2"])."""
    os.makedirs(OUT, exist_ok=True)
    root = sc.objects[P + "root"]
    feats = {}
    sets = ([("head%d" % k, ("head%d" % k, "neck")) for k in range(HEADS)]
            + [("body%d" % k, ("body%d" % k, "neck")) for k in range(BODIES)]
            + [("legs%d" % k, ("legs%d" % k,)) for k in range(LEGS)])
    fpath = os.path.join(OUT, "features.json")
    if only and os.path.exists(fpath):
        feats = json.load(open(fpath))
    for name, groups in sets:
        if only and name not in only:
            continue
        show(groups)
        for dname, rot in DIRS:
            root.rotation_euler = (0, 0, math.radians(rot))
            for i, (leg, arm, bob) in enumerate(POSES):
                pose(sc, leg, arm, bob)
                bpy.context.view_layer.update()
                tag = "%s_%s%d" % (name, dname, i)
                if name.startswith("head"):
                    feats[tag] = features(sc)
                for shade in (False, True):
                    set_pass(shade)
                    sc.eevee.taa_render_samples = 16 if shade else 1
                    sc.render.filter_size = 1.5 if shade else 0.0
                    sc.render.filepath = os.path.join(OUT, "%s_%s.png" % ("shade" if shade else "id", tag))
                    bpy.ops.render.render(write_still=True, scene=sc.name)
    show([g for g in GROUPS])
    with open(fpath, "w") as f:
        json.dump(feats, f, indent=1)


def run(render=True):
    win = bpy.context.window
    old = win.scene
    sc = scene()
    win.scene = sc
    try:
        build(sc)
        bpy.context.view_layer.update()
        align_camera(sc)
        if render:
            render_all(sc)
    finally:
        win.scene = old
    return sc


if __name__ == "__main__" or True:
    run(render=os.environ.get("CWL_NO_RENDER") is None)
