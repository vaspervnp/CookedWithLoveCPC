"""Build Liberty / Eleftheria (the cook) in Blender and render her passes.

Run inside Blender (Blender MCP: exec(open(path).read())). Scene
"CWL_Liberty", objects "LIB_*". Shared helpers: cwl_char.py.

White double-breasted chef's jacket, red neckerchief, dark trousers, dark
hair in a bun under a short white cap. Frames (id/shade passes, 4x size):
  walk_<dir><pose>   dir down/up/right, pose 0 idle, 1 walk 1, 2 walk 2
  act_<name><k>      at the counter, in profile (facing right; left = mirror):
                     chop0/1 (knife up, down), stir0/1 (ladle left, right),
                     oven0/1 (reaching in, lifting out)
tools/charsheet.py turns them into assets/sprites/liberty.png and
liberty_act.png.
"""

import math
import os

import bpy

HERE = r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\CookedWithLoveCPC\assets\blender"
OUT = os.environ.get("CWL_RENDER_DIR", r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\CookedWithLoveCPC\build\render\liberty")
SCN = "CWL_Liberty"
P = "LIB_"
MATS = ["hair", "skin", "jacket", "buttons", "scarf", "trousers", "shoes",
        "cap", "metal", "wood", "eyes", "mouth", "brows"]

exec(open(os.path.join(HERE, "cwl_char.py")).read())


def build(sc):
    root = empty(sc, "root", (0, 0, 0))
    root.scale = (0.95, 0.95, 0.95)          # the cap must fit in 48 lines
    body = empty(sc, "body", (0, 0, 0), root)

    for side, sx in (("l", 0.2), ("r", -0.2)):
        hip = empty(sc, "hip_" + side, (sx, 0, 1.16), body)
        mesh_obj(sc, "leg_" + side, cyl(0.18, 0.15, 1.0), "trousers", (0, 0, 0.02), hip)
        mesh_obj(sc, "shoe_" + side, sphere(0.19, (1.0, 1.7, 0.62)), "shoes", (0, -0.1, -1.04), hip)

    # jacket down to the upper thigh, double row of buttons, neckerchief
    mesh_obj(sc, "jacket", cyl(0.58, 0.54, 1.18, 0.66), "jacket", (0, 0, 2.12), body)
    for row, x in enumerate((0.16, -0.16)):
        for i, z in enumerate((1.85, 1.6, 1.35)):
            mesh_obj(sc, "button%d%d" % (row, i), sphere(0.045), "buttons", (x, -0.37, z), body)
    mesh_obj(sc, "scarf", cyl(0.24, 0.27, 0.12), "scarf", (0, -0.01, 2.16), body)
    mesh_obj(sc, "scarf_knot", sphere(0.09, (1.2, 0.7, 1.0)), "scarf", (0, -0.27, 2.04), body)

    # arms: shoulder -> elbow -> hand; tools in the right hand
    for side, sx in (("l", 0.66), ("r", -0.66)):
        sh = empty(sc, "shoulder_" + side, (sx, 0, 1.93), body)
        mesh_obj(sc, "upper_" + side, cyl(0.15, 0.13, 0.46), "jacket", (0, 0, 0.05), sh)
        el = empty(sc, "elbow_" + side, (0, 0, -0.4), sh)
        mesh_obj(sc, "fore_" + side, cyl(0.13, 0.12, 0.36), "jacket", (0, 0, 0), el)
        mesh_obj(sc, "cuff_" + side, cyl(0.135, 0.135, 0.06), "jacket", (0, 0, -0.32), el)
        hand = empty(sc, "hand_" + side, (0, -0.02, -0.46), el)
        mesh_obj(sc, "handm_" + side, sphere(0.13, (1, 1, 1.1)), "skin", (0, 0, 0), hand)
    hr = sc.objects[P + "hand_r"]
    mesh_obj(sc, "knife_handle", box(0.07, 0.18, 0.07), "wood", (0, -0.1, -0.02), hr)
    mesh_obj(sc, "knife_blade", box(0.04, 0.48, 0.17), "metal", (0, -0.42, -0.05), hr)
    mesh_obj(sc, "ladle_stick", cyl(0.04, 0.04, 0.7), "wood", (0, 0, 0.1), hr)
    mesh_obj(sc, "ladle_cup", sphere(0.13, (1, 1, 0.6)), "metal", (0, 0, -0.62), hr)

    # neck, head, hair with a bun, short chef's cap
    mesh_obj(sc, "neck", cyl(0.16, 0.16, 0.16), "skin", (0, 0, 2.24), body)
    head = empty(sc, "head", (0, 0, 2.76), body)
    mesh_obj(sc, "skull", sphere(0.7, (1.0, 0.92, 0.95)), "skin", (0, 0, 0), head)
    for side, sx in (("l", 0.69), ("r", -0.69)):
        mesh_obj(sc, "ear_" + side, sphere(0.14, (0.6, 1, 1)), "skin", (sx, 0.02, -0.05), head)
    mesh_obj(sc, "nose", sphere(0.09, (1, 1, 1.2)), "skin", (0, -0.68, -0.1), head)
    hair = cut(sphere(0.75, (1.0, 0.97, 0.95)),
               lambda co: co.z > 0.12 - 0.4 * max(0.0, co.y) / 0.75 or co.y > 0.25)
    mesh_obj(sc, "hair", hair, "hair", (0, 0.04, 0.0), head)
    mesh_obj(sc, "bun", sphere(0.27), "hair", (0, 0.66, 0.1), head)
    mesh_obj(sc, "cap", cyl(0.6, 0.62, 0.16), "cap", (0, 0.02, 0.66), head)
    mesh_obj(sc, "cap_puff", sphere(0.72, (1.0, 0.95, 0.5)), "cap", (0, 0.04, 0.8), head)
    face_points(sc, head)

    camera_and_light(sc)
    return root


def arm(side, shoulder=0, elbow=0, spread=0):
    o = bpy.context.scene.objects
    s = 1 if side == "l" else -1
    o[P + "shoulder_" + side].rotation_euler = (math.radians(shoulder), 0, math.radians(4 * s + spread))
    o[P + "elbow_" + side].rotation_euler = (math.radians(elbow), 0, 0)


def tools(knife=False, ladle=False):
    o = bpy.context.scene.objects
    # the ladle hangs down into the pot: turn the wrist against the forearm
    o[P + "hand_r"].rotation_euler = (math.radians(90 if ladle else 0), 0, 0)
    for n in ("knife_handle", "knife_blade"):
        o[P + n].hide_render = not knife
    for n in ("ladle_stick", "ladle_cup"):
        o[P + n].hide_render = not ladle


def walk(sc, rot, leg, armsw):
    o = sc.objects
    o[P + "root"].rotation_euler = (0, 0, math.radians(rot))
    o[P + "body"].location = (0, 0, 0)
    o[P + "hip_l"].rotation_euler = (math.radians(leg), 0, 0)
    o[P + "hip_r"].rotation_euler = (math.radians(-leg), 0, 0)
    arm("l", -armsw, -10)
    arm("r", armsw, -10)
    tools()


def act(sc, name, k):
    o = sc.objects
    o[P + "root"].rotation_euler = (0, 0, math.radians(90))      # in profile
    o[P + "body"].location = (0, 0, 0)
    o[P + "hip_l"].rotation_euler = (0, 0, 0)
    o[P + "hip_r"].rotation_euler = (0, 0, 0)
    if name == "chop":
        arm("l", -45, -40)                       # holds the food
        arm("r", -55, (-75, -15)[k])             # knife up / down
        tools(knife=True)
    elif name == "stir":
        arm("l", -35, -45)
        arm("r", -45, -45, (-22, 22)[k])         # ladle left / right in the pot
        tools(ladle=True)
    else:                                        # oven: reach in, lift out
        o[P + "body"].location = (0, 0, (-0.12, 0.0)[k])
        for side in ("l", "r"):
            arm(side, (-80, -60)[k], (0, -35)[k])
        tools()


FRAMES = ([("walk_%s%d" % (d, i), ("walk", rot, leg, a))
           for d, rot in (("down", 0), ("up", 180), ("right", 90))
           for i, (leg, a) in enumerate(((0, 0), (28, 24), (-28, -24)))]
          + [("act_%s%d" % (n, k), ("act", n, k)) for n in ("chop", "stir", "oven") for k in (0, 1)])


def setup(sc, kind, *args):
    (walk if kind == "walk" else act)(sc, *args)


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
            render_frames(sc, FRAMES, setup)
    finally:
        win.scene = old
    return sc


if __name__ == "__main__" or True:
    run(render=os.environ.get("CWL_NO_RENDER") is None)
