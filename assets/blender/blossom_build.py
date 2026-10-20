"""Build Blossom / Anthi (the storage keeper) in Blender and render her passes.

Run inside Blender (Blender MCP: exec(open(path).read())). Scene
"CWL_Blossom", objects "BLO_*". Shared helpers: cwl_char.py.

Blue dungarees with straps over a yellow t-shirt, red hair in a ponytail,
dark boots. Frames (id/shade passes, 4x size):
  walk_<dir><pose>    dir down/up/right, pose 0 idle, 1 walk 1, 2 walk 2
  carry_<dir><pose>   the same carrying a box in front
  act_shelf<k>        in profile (facing right): 0 box lifted to the chest,
                      1 arms out, putting it on the shelf
tools/charsheet.py turns them into assets/sprites/blossom.png,
blossom_carry.png and blossom_act.png.
"""

import math
import os

import bpy

HERE = r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\CookedWithLoveCPC\assets\blender"
OUT = os.environ.get("CWL_RENDER_DIR", r"\\wsl.localhost\Ubuntu\home\vasilhs\repos\CookedWithLoveCPC\build\render\blossom")
SCN = "CWL_Blossom"
P = "BLO_"
MATS = ["hair", "skin", "shirt", "overall", "buckle", "boots", "box", "tape",
        "eyes", "mouth", "brows"]

exec(open(os.path.join(HERE, "cwl_char.py")).read())


def build(sc):
    root = empty(sc, "root", (0, 0, 0))
    body = empty(sc, "body", (0, 0, 0), root)

    for side, sx in (("l", 0.2), ("r", -0.2)):
        hip = empty(sc, "hip_" + side, (sx, 0, 1.16), body)
        mesh_obj(sc, "leg_" + side, cyl(0.19, 0.17, 0.9), "overall", (0, 0, 0.02), hip)
        mesh_obj(sc, "boot_" + side, cyl(0.17, 0.17, 0.2), "boots", (0, -0.02, -0.86), hip)
        mesh_obj(sc, "toe_" + side, sphere(0.19, (1.0, 1.6, 0.6)), "boots", (0, -0.12, -1.05), hip)

    # t-shirt torso, dungarees: trousers part up to the waist, bib, straps
    mesh_obj(sc, "shirt", cyl(0.57, 0.5, 0.95, 0.64), "shirt", (0, 0, 2.12), body)
    mesh_obj(sc, "seat", cyl(0.5, 0.44, 0.3, 0.64), "overall", (0, 0, 1.4), body)
    mesh_obj(sc, "bib", poly([(-0.3, 1.82), (0.3, 1.82), (0.34, 1.32), (-0.34, 1.32)], 0.05),
             "overall", (0, -0.36, 0), body)
    for side, sx in (("l", 0.24), ("r", -0.24)):
        mesh_obj(sc, "strap_" + side, poly([(sx - 0.06, 2.1), (sx + 0.06, 2.1), (sx + 0.06, 1.8), (sx - 0.06, 1.8)], 0.04),
                 "overall", (0, -0.38, 0), body)
        mesh_obj(sc, "buckle_" + side, sphere(0.05), "buckle", (sx, -0.42, 1.82), body)

    # arms: short sleeve, bare arm, hand; the box in front of the chest
    for side, sx in (("l", 0.64), ("r", -0.64)):
        sh = empty(sc, "shoulder_" + side, (sx, 0, 1.93), body)
        mesh_obj(sc, "sleeve_" + side, cyl(0.16, 0.15, 0.28), "shirt", (0, 0, 0.06), sh)
        mesh_obj(sc, "upper_" + side, cyl(0.12, 0.11, 0.42), "skin", (0, 0, -0.1), sh)
        el = empty(sc, "elbow_" + side, (0, 0, -0.42), sh)
        mesh_obj(sc, "fore_" + side, cyl(0.11, 0.1, 0.36), "skin", (0, 0, 0), el)
        mesh_obj(sc, "hand_" + side, sphere(0.12, (1, 1, 1.1)), "skin", (0, -0.02, -0.42), el)
    crate = empty(sc, "box", (0, -0.66, 1.6), body)
    mesh_obj(sc, "box_m", box(0.8, 0.6, 0.6), "box", (0, 0, 0), crate, smooth=False)
    mesh_obj(sc, "box_tape", box(0.16, 0.62, 0.02), "tape", (0, 0, 0.31), crate, smooth=False)

    # neck, head, hair with a fringe and a ponytail
    mesh_obj(sc, "neck", cyl(0.16, 0.16, 0.16), "skin", (0, 0, 2.24), body)
    head = empty(sc, "head", (0, 0, 2.76), body)
    mesh_obj(sc, "skull", sphere(0.7, (1.0, 0.92, 0.95)), "skin", (0, 0, 0), head)
    for side, sx in (("l", 0.69), ("r", -0.69)):
        mesh_obj(sc, "ear_" + side, sphere(0.14, (0.6, 1, 1)), "skin", (sx, 0.02, -0.05), head)
    mesh_obj(sc, "nose", sphere(0.09, (1, 1, 1.2)), "skin", (0, -0.68, -0.1), head)
    hair = cut(sphere(0.76, (1.02, 0.98, 0.97)),
               lambda co: co.z > 0.18 - 0.42 * max(0.0, co.y) / 0.76 or co.y > 0.2)
    mesh_obj(sc, "hair", hair, "hair", (0, 0.04, 0.02), head)
    mesh_obj(sc, "fringe", sphere(0.42, (1.4, 0.45, 0.34)), "hair", (0.0, -0.44, 0.4), head)
    mesh_obj(sc, "tie", sphere(0.14), "hair", (0, 0.72, 0.2), head)
    mesh_obj(sc, "tail", sphere(0.22, (0.8, 0.8, 1.7)), "hair", (0, 0.8, -0.38), head)
    face_points(sc, head)

    camera_and_light(sc)
    return root


def arm(side, shoulder=0, elbow=0, spread=0):
    o = bpy.context.scene.objects
    s = 1 if side == "l" else -1
    o[P + "shoulder_" + side].rotation_euler = (math.radians(shoulder), 0, math.radians(4 * s + spread))
    o[P + "elbow_" + side].rotation_euler = (math.radians(elbow), 0, 0)


def show_box(on, loc=(0, -0.66, 1.6)):
    o = bpy.context.scene.objects
    o[P + "box"].location = loc
    for n in ("box_m", "box_tape"):
        o[P + n].hide_render = not on


def legs(leg):
    o = bpy.context.scene.objects
    o[P + "hip_l"].rotation_euler = (math.radians(leg), 0, 0)
    o[P + "hip_r"].rotation_euler = (math.radians(-leg), 0, 0)


def walk(sc, rot, leg, armsw):
    sc.objects[P + "root"].rotation_euler = (0, 0, math.radians(rot))
    legs(leg)
    arm("l", -armsw, -10)
    arm("r", armsw, -10)
    show_box(False)


def carry(sc, rot, leg, armsw):
    sc.objects[P + "root"].rotation_euler = (0, 0, math.radians(rot))
    legs(leg)
    for side in ("l", "r"):                  # hands under the box
        arm(side, -38, -52, -14 if side == "l" else 14)
    show_box(True)


def act(sc, k):
    sc.objects[P + "root"].rotation_euler = (0, 0, math.radians(90))
    legs(0)
    if k == 0:                               # box lifted to the chest
        for side in ("l", "r"):
            arm(side, -60, -60, -14 if side == "l" else 14)
        show_box(True, (0, -0.64, 1.9))
    else:                                    # arms out: onto the shelf
        for side in ("l", "r"):
            arm(side, -88, -10, -14 if side == "l" else 14)
        show_box(True, (0, -1.12, 2.0))


WALK = ((0, 0), (28, 24), (-28, -24))
CARRY = ((0, 0), (22, 0), (-22, 0))
DIRS = (("down", 0), ("up", 180), ("right", 90))
FRAMES = ([("walk_%s%d" % (d, i), ("walk", rot, leg, a)) for d, rot in DIRS for i, (leg, a) in enumerate(WALK)]
          + [("carry_%s%d" % (d, i), ("carry", rot, leg, a)) for d, rot in DIRS for i, (leg, a) in enumerate(CARRY)]
          + [("act_shelf%d" % k, ("act", k)) for k in (0, 1)])


def setup(sc, kind, *args):
    {"walk": walk, "carry": carry, "act": act}[kind](sc, *args)


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
