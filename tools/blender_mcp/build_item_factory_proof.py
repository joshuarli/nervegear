import json
import math
import os
import random
import shutil
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


WORKSPACE = Path(bpy.path.abspath("//")).resolve()
REPOSITORY = Path(os.environ.get("NERVEGEAR_ITEM_REPO", WORKSPACE)).resolve()
OUTPUT = Path(os.environ.get("NERVEGEAR_ITEM_OUTPUT", REPOSITORY / "Assets/Items/FactoryProof")).resolve()
AINCRAD2 = Path(os.environ.get("AINCRAD2_ROOT", "/Users/josh/d/aincrad2")).resolve()
REFERENCE_DIR = OUTPUT / "references"
EXPORT_DIR = OUTPUT / "exports"
REVIEW_DIR = OUTPUT / "review"

ITEMS = [
    {
        "name": "Tolbana Iron Sword",
        "slug": "tolbana-iron-sword",
        "family": "forged sword",
        "source": 'content/floors/1/codex.kdl:item "Tolbana Iron Sword"',
        "form": "Straight double-edged iron blade, plain crossguard, disc pommel.",
        "estimate": "Overall length and grip proportions are estimated; bell stamp is represented as a shallow circular inset.",
        "size": (0.09, 0.025, 0.92),
    },
    {
        "name": "Field Lantern",
        "slug": "field-lantern",
        "family": "sheet-metal assembly",
        "source": 'content/floors/1/codex.kdl:item "Field Lantern"',
        "form": "Tin lamp with a horn window, wire bail, and a stable base.",
        "estimate": "A compact hand lantern is shown; exact dimensions and hinge details are unspecified.",
        "size": (0.18, 0.15, 0.28),
    },
    {
        "name": "Lamp Oil",
        "slug": "lamp-oil",
        "family": "filled flask",
        "source": 'content/floors/1/codex.kdl:item "Lamp Oil"',
        "form": "Yellow seed oil sold by the flask.",
        "estimate": "The flask is an illustrative container, not a specified canonical vessel; its size is estimated.",
        "size": (0.105, 0.08, 0.17),
    },
    {
        "name": "Sawn Timber",
        "slug": "sawn-timber",
        "family": "cut lumber",
        "source": 'content/floors/1/codex.kdl:item "Sawn Timber"',
        "form": "Oak and ash boards from Horunka's sawpit.",
        "estimate": "Board count and dimensions are estimated; both species are suggested through two restrained wood tones.",
        "size": (0.34, 0.12, 0.085),
    },
    {
        "name": "Kobold Iron",
        "slug": "kobold-iron",
        "family": "raw metal",
        "source": 'content/floors/1/codex.kdl:item "Kobold Iron"',
        "form": "Dark, soft bog-ore iron lump from the warrens' forge.",
        "estimate": "A single irregular lump stands for a sale unit; its size and exact ore texture are estimated.",
        "size": (0.13, 0.105, 0.10),
    },
    {
        "name": "Hollow Amber",
        "slug": "hollow-amber",
        "family": "polished resin",
        "source": 'content/floors/1/codex.kdl:item "Hollow Amber"',
        "form": "Thumb-sized clear yellow resin bead polished like glass.",
        "estimate": "A small uneven bead is used instead of a perfect sphere; exact dimensions are estimated.",
        "size": (0.034, 0.029, 0.041),
    },
    {
        "name": "Nepent Ovule",
        "slug": "nepent-ovule",
        "family": "plant seed-bulb",
        "source": 'content/floors/1/codex.kdl:item "Nepent Ovule"',
        "form": "Pale seed-bulb taken whole from beneath a flowering nepent bloom.",
        "estimate": "The exact plant anatomy is deliberately left plain because the codex does not describe it.",
        "size": (0.052, 0.042, 0.075),
    },
    {
        "name": "Brown Cap Mushroom",
        "slug": "brown-cap-mushroom",
        "family": "fungus",
        "source": 'content/floors/1/codex.kdl:item "Brown Cap Mushroom"',
        "form": "Firm brown cap mushroom from leaf litter beneath Horunka's oaks.",
        "estimate": "A single representative specimen is modeled; cap, gill, and stem proportions are estimated.",
        "size": (0.095, 0.095, 0.105),
    },
    {
        "name": "Mutton Pie",
        "slug": "mutton-pie",
        "family": "baked food",
        "source": 'content/floors/1/codex.kdl:item "Mutton Pie"',
        "form": "Wedge of chopped mutton and thyme beneath a thick butter crust, with gravy added through a lid hole.",
        "estimate": "Wedge angle and serving size are estimated from the description and icon.",
        "size": (0.12, 0.13, 0.055),
    },
    {
        "name": "Wolf Fang",
        "slug": "wolf-fang",
        "family": "bone tooth",
        "source": 'content/floors/1/codex.kdl:item "Wolf Fang"',
        "form": "Canine worked as bone for rivets, edge settings, and toggles.",
        "estimate": "A single canine is shown; curvature and dimensions are estimated.",
        "size": (0.027, 0.024, 0.084),
    },
    {
        "name": "Boar Hide",
        "slug": "boar-hide",
        "family": "cured hide",
        "source": 'content/floors/1/codex.kdl:item "Boar Hide"',
        "form": "Tanned frenzy-boar skin, thick over the shoulder and thinner at the belly.",
        "estimate": "A flattened shoulder-heavy hide silhouette is used; fold and thickness are illustrative.",
        "size": (0.34, 0.27, 0.035),
    },
    {
        "name": "Wild Honey",
        "slug": "wild-honey",
        "family": "honeycomb",
        "source": 'content/floors/1/codex.kdl:item "Wild Honey"',
        "form": "Dark comb cut from a hollow oak.",
        "estimate": "The amount and cut outline are estimated; cells are a readable stylized representation.",
        "size": (0.12, 0.075, 0.045),
    },
]

PALETTE = {
    "iron": ((0.19, 0.22, 0.24, 1), 0.38, 0.82),
    "bright_iron": ((0.43, 0.49, 0.53, 1), 0.25, 0.88),
    "wood_oak": ((0.27, 0.145, 0.067, 1), 0.76, 0.0),
    "wood_ash": ((0.48, 0.32, 0.18, 1), 0.72, 0.0),
    "leather": ((0.20, 0.10, 0.055, 1), 0.84, 0.0),
    "brass": ((0.55, 0.31, 0.075, 1), 0.31, 0.68),
    "horn": ((0.69, 0.48, 0.24, 1), 0.48, 0.0),
    "glass_gold": ((0.82, 0.47, 0.12, 1), 0.19, 0.0),
    "oil": ((0.92, 0.56, 0.11, 1), 0.26, 0.0),
    "ore": ((0.105, 0.11, 0.105, 1), 0.88, 0.34),
    "amber": ((0.96, 0.39, 0.045, 1), 0.16, 0.0),
    "seed": ((0.76, 0.73, 0.56, 1), 0.56, 0.0),
    "seed_seam": ((0.55, 0.52, 0.39, 1), 0.72, 0.0),
    "mushroom_cap": ((0.24, 0.095, 0.04, 1), 0.76, 0.0),
    "mushroom_under": ((0.64, 0.43, 0.22, 1), 0.82, 0.0),
    "mushroom_stem": ((0.79, 0.66, 0.46, 1), 0.86, 0.0),
    "crust": ((0.57, 0.30, 0.10, 1), 0.68, 0.0),
    "crust_light": ((0.78, 0.47, 0.21, 1), 0.72, 0.0),
    "filling": ((0.32, 0.16, 0.07, 1), 0.9, 0.0),
    "bone": ((0.83, 0.75, 0.58, 1), 0.73, 0.0),
    "hide": ((0.47, 0.29, 0.14, 1), 0.91, 0.0),
    "hide_edge": ((0.25, 0.13, 0.07, 1), 0.92, 0.0),
    "wax": ((0.51, 0.28, 0.09, 1), 0.74, 0.0),
    "honey": ((0.28, 0.115, 0.025, 1), 0.38, 0.0),
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    scene = bpy.context.scene
    collection = bpy.data.collections.new("Floor 1 Item Factory Proof")
    scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def material(name, color, roughness, metallic=0.0, noise=0.0):
    existing = bpy.data.materials.get(name)
    if existing:
        bpy.data.materials.remove(existing)
    value = bpy.data.materials.new(name)
    value.diffuse_color = color
    value.use_nodes = True
    nodes = value.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if noise:
        texture = nodes.new("ShaderNodeTexNoise")
        texture.inputs["Scale"].default_value = 36.0
        texture.inputs["Detail"].default_value = 2.0
        ramp = nodes.new("ShaderNodeValToRGB")
        low = tuple(component * (1.0 - noise) for component in color[:3]) + (1,)
        high = tuple(min(1.0, component * (1.0 + noise)) for component in color[:3]) + (1,)
        ramp.color_ramp.elements[0].position = 0.23
        ramp.color_ramp.elements[0].color = low
        ramp.color_ramp.elements[1].position = 0.77
        ramp.color_ramp.elements[1].color = high
        value.node_tree.links.new(texture.outputs["Fac"], ramp.inputs["Fac"])
        value.node_tree.links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
    return value


def materials_for(slug):
    result = {}
    for key, (color, roughness, metallic) in PALETTE.items():
        result[key] = material(f"{slug}_{key}", color, roughness, metallic, 0.08 if key in {"wood_oak", "wood_ash", "hide"} else 0.025 if key in {"iron", "ore"} else 0.0)
    return result


def assign(obj, mat):
    obj.data.materials.append(mat)
    return obj


def cube(name, location, dimensions, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    if bevel:
        modifier = obj.modifiers.new("Soft working edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
        normal = obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
        normal.keep_sharp = True
    return obj


def sphere(name, location, scale, mat, subdivisions=3):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    modifier = obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    modifier.keep_sharp = True
    return obj


def cylinder(name, location, radius, depth, mat, vertices=24, radius_top=None, bevel=0.0):
    if radius_top is None or radius_top == radius:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius_top, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    if bevel:
        modifier = obj.modifiers.new("Soft edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def lathe(name, profile, mat, segments=32):
    vertices = []
    faces = []
    for radius, z in profile:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((radius * math.cos(angle), radius * math.sin(angle), z))
    for row in range(len(profile) - 1):
        for index in range(segments):
            a = row * segments + index
            b = row * segments + (index + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    faces.append(tuple(range(segments - 1, -1, -1)))
    faces.append(tuple((len(profile) - 1) * segments + index for index in range(segments)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign(obj, mat)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def ring_curve(name, points, radius, mat, resolution=8):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 16
    curve.bevel_depth = radius
    curve.bevel_resolution = resolution
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, coordinate in zip(spline.points, points):
        point.co = (*coordinate, 1)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    for selected in bpy.context.selected_objects:
        if selected != obj:
            selected.select_set(False)
    return obj


def mesh_object(name, vertices, faces, mat, smooth=False):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign(obj, mat)
    if smooth:
        for face in obj.data.polygons:
            face.use_smooth = True
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def make_sword(m):
    parts = []
    sections = [(0.205, 0.032), (0.27, 0.041), (0.79, 0.026), (0.91, 0.0)]
    vertices = []
    for z, width in sections:
        thickness = max(0.0015, width * 0.115)
        vertices.extend([
            (-width * 0.5, 0, z),
            (0, -thickness, z),
            (width * 0.5, 0, z),
            (0, thickness, z),
        ])
    faces = []
    for row in range(len(sections) - 1):
        for side in range(4):
            a = row * 4 + side
            b = row * 4 + (side + 1) % 4
            faces.append((a, b, b + 4, a + 4))
    faces.append((0, 1, 2, 3))
    tip = len(vertices)
    vertices.append((0, 0, 0.94))
    for side in range(4):
        a = (len(sections) - 1) * 4 + side
        b = (len(sections) - 1) * 4 + (side + 1) % 4
        faces.append((a, b, tip))
    parts.append(mesh_object("Double edged blade", vertices, faces, m["bright_iron"]))
    parts.append(cube("Plain crossguard", (0, 0, 0.205), (0.14, 0.026, 0.024), m["bright_iron"], 0.008))
    parts.append(cylinder("Wooden grip", (0, 0, 0.126), 0.014, 0.13, m["wood_oak"], vertices=16, bevel=0.003))
    for index in range(4):
        z = 0.077 + index * 0.031
        parts.append(cube("Grip binding", (0, 0, z), (0.029, 0.029, 0.004), m["leather"], 0.0015))
    parts.append(cylinder("Disc pommel", (0, 0, 0.035), 0.028, 0.018, m["brass"], vertices=32, bevel=0.004))
    parts.append(cylinder("Pommel boss", (0, 0, 0.035), 0.010, 0.020, m["bright_iron"], vertices=24))
    return parts


def make_lantern(m):
    parts = [
        cylinder("Tin foot", (0, 0, 0.018), 0.078, 0.036, m["iron"], bevel=0.006),
        lathe("Tin lamp body", [(0.068, 0.035), (0.073, 0.052), (0.074, 0.175), (0.067, 0.19)], m["iron"]),
        cylinder("Lower rim", (0, 0, 0.052), 0.078, 0.012, m["bright_iron"], bevel=0.002),
        cylinder("Upper rim", (0, 0, 0.18), 0.076, 0.012, m["bright_iron"], bevel=0.002),
        lathe("Vent hood", [(0.07, 0.188), (0.052, 0.21), (0.026, 0.236), (0.014, 0.244)], m["iron"]),
        cylinder("Cap", (0, 0, 0.244), 0.017, 0.012, m["brass"], bevel=0.002),
        ring_curve("Wire bail", [(0.085 * math.cos(t), 0, 0.187 + 0.105 * math.sin(t)) for t in [math.pi * index / 32 for index in range(33)]], 0.003, m["iron"]),
        cylinder("Horn window", (0, -0.071, 0.118), 0.039, 0.003, m["horn"], vertices=32),
    ]
    parts[-1].rotation_euler.x = math.pi / 2
    for side in (-1, 1):
        parts.append(cube("Window post", (side * 0.052, -0.074, 0.118), (0.009, 0.009, 0.126), m["bright_iron"], 0.003))
        parts.append(cube("Window brace", (0, -0.074, 0.073 if side < 0 else 0.161), (0.11, 0.009, 0.009), m["bright_iron"], 0.003))
    return parts


def make_oil(m):
    parts = [
        lathe("Oil flask", [(0.0, 0.006), (0.031, 0.006), (0.045, 0.02), (0.049, 0.045), (0.044, 0.072), (0.028, 0.092), (0.015, 0.098), (0.014, 0.14), (0.020, 0.142)], m["glass_gold"]),
        lathe("Seed oil fill", [(0.0, 0.010), (0.027, 0.010), (0.038, 0.025), (0.039, 0.054), (0.031, 0.068), (0.0, 0.068)], m["oil"]),
        cylinder("Flask neck lip", (0, 0, 0.142), 0.021, 0.008, m["brass"], vertices=32, bevel=0.002),
        cylinder("Wood stopper", (0, 0, 0.157), 0.014, 0.024, m["wood_oak"], vertices=24, radius_top=0.012, bevel=0.002),
    ]
    return parts


def make_timber(m):
    return [
        cube("Oak board", (0, 0, 0.028), (0.33, 0.083, 0.046), m["wood_oak"], 0.004),
        cube("Ash board", (0.012, 0.012, 0.069), (0.32, 0.078, 0.034), m["wood_ash"], 0.0035),
        cube("Oak board", (-0.009, -0.009, 0.099), (0.31, 0.073, 0.028), m["wood_oak"], 0.003),
    ]


def make_ore(m):
    rng = random.Random(19)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=(0, 0, 0.052))
    obj = bpy.context.object
    obj.name = "Bog iron lump"
    for vertex in obj.data.vertices:
        factor = rng.uniform(0.78, 1.18)
        vertex.co.x *= 0.065 * factor
        vertex.co.y *= 0.053 * factor
        vertex.co.z *= 0.048 * factor
    assign(obj, m["ore"])
    return [obj]


def make_amber(m):
    obj = sphere("Polished resin bead", (0, 0, 0.022), (0.016, 0.0135, 0.020), m["amber"])
    obj.rotation_euler = (0.14, 0.22, 0.0)
    return [obj]


def make_ovule(m):
    parts = [sphere("Pale seed bulb", (0, 0, 0.035), (0.024, 0.019, 0.034), m["seed"])]
    parts.append(sphere("Ovule tip", (0, 0, 0.067), (0.009, 0.008, 0.013), m["seed_seam"], subdivisions=2))
    parts.append(ring_curve("Seed seam", [(0.019 * math.cos(t), 0.015 * math.sin(t), 0.026 + 0.011 * math.cos(t)) for t in [math.tau * i / 32 for i in range(33)]], 0.001, m["seed_seam"], 4))
    return parts


def make_mushroom(m):
    parts = [
        cylinder("Stem", (0, 0, 0.038), 0.014, 0.066, m["mushroom_stem"], vertices=32, radius_top=0.010, bevel=0.002),
        lathe("Gill skirt", [(0.012, 0.063), (0.044, 0.063), (0.049, 0.068), (0.034, 0.078)], m["mushroom_under"], segments=40),
        lathe("Brown cap", [(0.0, 0.074), (0.018, 0.075), (0.036, 0.082), (0.046, 0.094), (0.043, 0.104), (0.031, 0.111), (0.016, 0.114), (0.0, 0.112)], m["mushroom_cap"], segments=40),
    ]
    return parts


def wedge(name, radius, z_bottom, z_top, start_angle, end_angle, mat, segments=18):
    vertices = [(0, 0, z_bottom), (0, 0, z_top)]
    angles = [start_angle + (end_angle - start_angle) * index / segments for index in range(segments + 1)]
    bottom_start = 2
    for angle in angles:
        vertices.append((radius * math.cos(angle), radius * math.sin(angle), z_bottom))
    top_start = len(vertices)
    for angle in angles:
        vertices.append((radius * math.cos(angle), radius * math.sin(angle), z_top))
    faces = []
    for index in range(segments):
        a = bottom_start + index
        b = bottom_start + index + 1
        c = top_start + index
        d = top_start + index + 1
        faces.extend([(0, b, a), (1, c, d), (a, b, d, c)])
    faces.extend([(0, bottom_start, top_start), (0, bottom_start + segments, top_start + segments)])
    return mesh_object(name, vertices, faces, mat)


def make_pie(m):
    segments = 18
    angles = [-0.56 + 1.12 * index / segments for index in range(segments + 1)]
    radii = [(0.024, 0.064), (0.068, 0.063), (0.12, 0.052)]
    vertices = []
    for radius, z in radii:
        vertices.extend((radius * math.cos(angle), radius * math.sin(angle), z) for angle in angles)
    faces = []
    for row in range(len(radii) - 1):
        for index in range(segments):
            a = row * len(angles) + index
            b = a + 1
            c = (row + 1) * len(angles) + index
            d = c + 1
            faces.append((a, b, d, c))
    top = mesh_object("Domed butter crust", vertices, faces, m["crust_light"])
    parts = [
        wedge("Mutton and thyme filling", 0.12, 0.008, 0.052, -0.56, 0.56, m["filling"]),
        top,
        cylinder("Gravy vent", (0.064, 0, 0.064), 0.004, 0.0015, m["filling"], vertices=20),
    ]
    return parts


def make_fang(m):
    sections = [(0.0, 0.011), (0.018, 0.012), (0.038, 0.009), (0.058, 0.006), (0.078, 0.002)]
    vertices = []
    sides = 16
    for z, radius in sections:
        center_x = 0.018 * (z / 0.078) ** 2
        center_y = 0.004 * math.sin(z * 30)
        for index in range(sides):
            angle = math.tau * index / sides
            vertices.append((center_x + radius * math.cos(angle), center_y + radius * math.sin(angle), z))
    faces = []
    for row in range(len(sections) - 1):
        for index in range(sides):
            a = row * sides + index
            b = row * sides + (index + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(range(sides)))
    parts = [mesh_object("Curved canine", vertices, faces, m["bone"], smooth=True)]
    parts.append(sphere("Root enamel", (0, 0, 0.007), (0.012, 0.012, 0.014), m["bone"], subdivisions=2))
    return parts


def make_hide(m):
    outline = [(-0.15, -0.11), (-0.11, -0.14), (-0.02, -0.12), (0.06, -0.125), (0.145, -0.09), (0.162, -0.015), (0.12, 0.025), (0.14, 0.09), (0.09, 0.12), (0.035, 0.08), (-0.005, 0.14), (-0.07, 0.115), (-0.115, 0.08), (-0.16, 0.035), (-0.13, -0.025)]
    vertices = [(0.0, 0.0, 0.032)]
    ring_scales = (0.32, 0.66, 1.0)
    for scale in ring_scales:
        for x, y in outline:
            shoulder = math.exp(-(((x - 0.05) / 0.11) ** 2 + ((y + 0.015) / 0.10) ** 2))
            z = 0.021 + 0.004 * (1.0 - scale) + 0.007 * shoulder
            vertices.append((x * scale, y * scale, z))
    faces = []
    outline_count = len(outline)
    for index in range(outline_count):
        faces.append((0, 1 + index, 1 + (index + 1) % outline_count))
    for ring_index in range(len(ring_scales) - 1):
        inner_start = 1 + ring_index * outline_count
        outer_start = inner_start + outline_count
        for index in range(outline_count):
            following = (index + 1) % outline_count
            faces.append((inner_start + index, outer_start + index, outer_start + following, inner_start + following))
    hide = mesh_object("Shoulder-heavy cured hide", vertices, faces, m["hide"], smooth=True)
    subdivision = hide.modifiers.new("Soft hide surface", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 2
    hide_solid = hide.modifiers.new("Hide thickness", "SOLIDIFY")
    hide_solid.thickness = 0.005
    hide_bevel = hide.modifiers.new("Soft hide edge", "BEVEL")
    hide_bevel.width = 0.002
    hide_bevel.segments = 2
    return [hide]


def make_honey(m):
    parts = []
    radius = 0.010
    rows = 5
    columns = 7
    for row in range(rows):
        for column in range(columns):
            x = (column - (columns - 1) / 2) * radius * 1.72 + (row % 2) * radius * 0.86
            y = (row - (rows - 1) / 2) * radius * 1.49
            variation = 0.003 * math.sin(column * 1.7 + row * 2.1)
            bottom = 0.007 + variation
            top = 0.040 + variation
            vertices = []
            for z, r in ((bottom, radius), (top, radius), (bottom + 0.001, radius * 0.68), (top - 0.004, radius * 0.68)):
                for index in range(6):
                    angle = math.tau * index / 6
                    vertices.append((x + r * math.cos(angle), y + r * math.sin(angle), z))
            faces = []
            for index in range(6):
                nxt = (index + 1) % 6
                faces.append((index, nxt, nxt + 6, index + 6))
                faces.append((12 + index, 12 + nxt, 18 + nxt, 18 + index))
                faces.append((6 + index, 6 + nxt, 18 + nxt, 18 + index))
            cell = mesh_object("Dark honeycomb cell", vertices, faces, m["wax"])
            cell.data.materials.append(m["honey"])
            for face in cell.data.polygons:
                if len(face.vertices) == 4 and face.index % 3 == 1:
                    face.material_index = 1
            parts.append(cell)
    return parts


BUILDERS = {
    "tolbana-iron-sword": make_sword,
    "field-lantern": make_lantern,
    "lamp-oil": make_oil,
    "sawn-timber": make_timber,
    "kobold-iron": make_ore,
    "hollow-amber": make_amber,
    "nepent-ovule": make_ovule,
    "brown-cap-mushroom": make_mushroom,
    "mutton-pie": make_pie,
    "wolf-fang": make_fang,
    "boar-hide": make_hide,
    "wild-honey": make_honey,
}


def join_item(name, parts, collection):
    meshes = []
    for obj in parts:
        if obj.type == "CURVE":
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.ops.object.convert(target="MESH")
        obj = bpy.data.objects.get(obj.name)
        if obj and obj.type == "MESH":
            meshes.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    item = bpy.context.object
    item.name = name.replace(" ", "_")
    item.data.name = f"{item.name}_mesh"
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    move_to_collection(item, collection)
    return item


def track_to(obj, point):
    direction = Vector(point) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def image_card_material(name, image):
    value = bpy.data.materials.new(name)
    value.use_nodes = True
    value.surface_render_method = "BLENDED"
    nodes = value.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    value.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    value.node_tree.links.new(texture.outputs["Color"], shader.inputs["Emission Color"])
    shader.inputs["Emission Strength"].default_value = 0.8
    value.node_tree.links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
    value.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    image.pack()
    return value


def plane(name, x, y, z, width, height, mat):
    vertices = [(x - width / 2, y, z - height / 2), (x + width / 2, y, z - height / 2), (x + width / 2, y, z + height / 2), (x - width / 2, y, z + height / 2)]
    obj = mesh_object(name, vertices, [(0, 1, 2, 3)], mat)
    obj.data.uv_layers.new(name="UVMap")
    for loop_index, uv in zip(obj.data.uv_layers.active.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop_index.uv = uv
    return obj


def add_text(name, body, location, size, material_value, rotation=(math.pi / 2, 0, 0), align="LEFT"):
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = body
    curve.size = size
    curve.align_x = align
    curve.extrude = 0
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    curve.materials.append(material_value)
    return obj


def add_area_light(name, location, target, power, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    track_to(obj, target)
    return obj


def set_world(color, strength):
    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("Item proof world")
        bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = color
    background.inputs["Strength"].default_value = strength


def render_settings(width, height, transparent=False):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 48
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = transparent
    scene.view_settings.view_transform = "AgX"
    scene.camera.data.type = "ORTHO"
    scene.camera.data.lens = 50


def create_camera(name, location, target, ortho_scale):
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    track_to(obj, target)
    bpy.context.scene.camera = obj
    return obj


def add_studio_background(material_value, width, depth, z):
    return cube("Studio ground", (0, 0, z - 0.02), (width, depth, 0.04), material_value, 0.02)


def render_item_angles(item, definition, materials):
    collection = bpy.data.collections.new(f"Review {definition['slug']}")
    bpy.context.scene.collection.children.link(collection)
    item.hide_render = False
    duplicate = item.copy()
    duplicate.data = item.data
    collection.objects.link(duplicate)
    bpy.context.scene.camera = None
    item_scale = max(float(value) for value in item.dimensions)
    focus = (0, 0, max(float(item.dimensions.z) * 0.5, 0.002))
    camera = create_camera("Item review camera", (0, -item_scale * 4, item_scale * 3), focus, item_scale * 1.9)
    floor_size = max(item_scale * 2.6, 0.22)
    ground = cube("Review floor", (0, 0, -0.015), (floor_size, floor_size, 0.03), materials["wood_ash"], 0.01)
    add_area_light("Key", (1.3, -1.2, 1.6), (0, 0, 0.1), 90, 0.75, (1.0, 0.83, 0.66))
    add_area_light("Fill", (-1.1, -0.4, 0.8), (0, 0, 0.1), 45, 0.9, (0.62, 0.75, 1.0))
    set_world((0.12, 0.15, 0.14, 1), 0.25)
    render_settings(512, 512, True)
    scene = bpy.context.scene
    angle_views = [
        ("three-quarter", Vector((1.0, -1.3, 1.05))),
        ("front", Vector((0.0, -1.0, 0.5))),
        ("side", Vector((1.0, 0.0, 0.5))),
        ("back", Vector((0.0, 1.0, 0.5))),
        ("top", Vector((0.0, 0.0, 1.0))),
    ]
    for view, direction in angle_views:
        direction.normalize()
        camera.location = Vector(focus) + direction * item_scale * 4
        track_to(camera, focus)
        camera.data.ortho_scale = max(item_scale * 1.9, 0.08)
        scene.render.filepath = str(REVIEW_DIR / "angles" / f"{definition['slug']}_{view}.png")
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(duplicate, do_unlink=True)
    for obj in [camera, ground]:
        bpy.data.objects.remove(obj, do_unlink=True)
    for light in [obj for obj in scene.objects if obj.type == "LIGHT"]:
        bpy.data.objects.remove(light, do_unlink=True)
    bpy.data.collections.remove(collection)
    item.hide_render = True


def create_contact_sheet(items_by_slug, collection):
    scene = bpy.context.scene
    board_collection = bpy.data.collections.new("Contact Sheet Presentation")
    scene.collection.children.link(board_collection)
    board_mat = material("Proof board deep forest", (0.055, 0.115, 0.10, 1), 0.82)
    tile_mat = material("Proof tile warm slate", (0.12, 0.18, 0.16, 1), 0.88)
    text_mat = material("Proof lettering", (0.93, 0.85, 0.67, 1), 0.6)
    backing = cube("Contact sheet backing", (0, 0.13, 1.5), (5.3, 0.20, 3.55), board_mat, 0.06)
    move_to_collection(backing, board_collection)
    title = add_text("Contact sheet title", "AINCRAD 2  /  FLOOR 1  /  ITEM STUDY", (-2.35, -0.02, 3.08), 0.14, text_mat)
    subtitle = add_text("Contact sheet subtitle", "REFERENCE ICON  +  PROCEDURAL MESH  /  CATALOG VIEWS NORMALIZED", (-2.34, -0.02, 2.86), 0.067, text_mat)
    move_to_collection(title, board_collection)
    move_to_collection(subtitle, board_collection)
    tile_width = 1.25
    row_step = 0.88
    col_x = [-1.91, -0.63, 0.65, 1.93]
    row_z = [2.12, 1.18, 0.24]
    for index, definition in enumerate(ITEMS):
        col = index % 4
        row = index // 4
        center_x = col_x[col]
        base_z = row_z[row]
        tile = cube(f"Tile {definition['name']}", (center_x, 0.0, base_z + 0.27), (1.17, 0.05, 0.78), tile_mat, 0.02)
        move_to_collection(tile, board_collection)
        icon_path = REFERENCE_DIR / f"{definition['slug']}.webp"
        image = bpy.data.images.load(str(icon_path), check_existing=True)
        icon_material = image_card_material(f"Icon {definition['slug']}", image)
        card = plane(f"Icon {definition['name']}", center_x - 0.36, -0.035, base_z + 0.28, 0.34, 0.34, icon_material)
        move_to_collection(card, board_collection)
        model = items_by_slug[definition["slug"]]
        display = model.copy()
        display.data = model.data
        display.hide_render = False
        board_collection.objects.link(display)
        maximum = max(model.dimensions)
        display.scale = (0.36 / maximum,) * 3
        display.location = (center_x + 0.19, -0.09, base_z + 0.09)
        if definition["slug"] in {"sawn-timber", "mutton-pie", "boar-hide", "wild-honey"}:
            display.rotation_euler.x = math.pi / 2
        name_label = add_text(f"Name {definition['slug']}", definition["name"], (center_x - 0.53, -0.075, base_z - 0.075), 0.062, text_mat)
        move_to_collection(name_label, board_collection)
    camera = create_camera("Contact sheet camera", (0, -8.0, 1.5), (0, 0, 1.5), 6.25)
    scene.camera = camera
    add_area_light("Board key", (-3.2, -3.0, 5.4), (0, 0, 1.5), 420, 5.0, (1.0, 0.87, 0.70))
    add_area_light("Board fill", (3.0, -2.0, 2.0), (0, 0, 1.4), 210, 3.5, (0.70, 0.82, 1.0))
    set_world((0.055, 0.08, 0.07, 1), 0.35)
    render_settings(2000, 1400)
    scene.render.filepath = str(REVIEW_DIR / "contact_sheet.png")
    bpy.ops.render.render(write_still=True)
    board_collection.hide_render = True


def create_gameplay_distance(items_by_slug):
    scene = bpy.context.scene
    distance_collection = bpy.data.collections.new("Gameplay Distance Preview")
    scene.collection.children.link(distance_collection)
    ground = material("Distance preview grass", (0.16, 0.23, 0.12, 1), 0.98, noise=0.12)
    plank = material("Distance preview table", (0.21, 0.13, 0.07, 1), 0.74, noise=0.08)
    label = material("Distance preview title", (0.91, 0.85, 0.68, 1), 0.6)
    cube("Ground plane", (0, 0, -0.08), (8.0, 5.0, 0.12), ground, 0.03)
    cube("Showcase tabletop", (0, 0.12, 0.35), (3.5, 2.45, 0.12), plank, 0.04)
    for x in (-1.55, 1.55):
        for y in (-0.87, 1.11):
            cube("Table leg", (x, y, 0.16), (0.13, 0.13, 0.34), plank, 0.015)
    x_positions = [-1.20, -0.40, 0.40, 1.20]
    y_positions = [-0.65, 0.0, 0.65]
    for index, definition in enumerate(ITEMS):
        col = index % 4
        row = index // 4
        model = items_by_slug[definition["slug"]]
        display = model.copy()
        display.data = model.data
        display.hide_render = False
        distance_collection.objects.link(display)
        display.location = (x_positions[col], y_positions[row], 0.41)
        marker = cylinder("Placement marker", (x_positions[col], y_positions[row], 0.414), 0.22, 0.008, plank, vertices=48)
        move_to_collection(marker, distance_collection)
    reference_material = material("Scale reference", (0.58, 0.26, 0.14, 1), 0.8)
    cylinder("Scale reference body", (2.18, -0.55, 0.86), 0.14, 1.25, reference_material, vertices=20, radius_top=0.11)
    sphere("Scale reference head", (2.18, -0.55, 1.58), (0.12, 0.12, 0.14), reference_material)
    add_text("Scale reference label", "1.70 m", (1.75, -0.72, 1.72), 0.08, label)
    add_text("Gameplay scale title", "TRUE-SIZE DISPLAY  /  4.5 m CAMERA DISTANCE", (-2.50, -1.20, 0.64), 0.09, label)
    camera = create_camera("Gameplay distance camera", (1.9, -3.65, 1.9), (0, 0.2, 0.54), 7.0)
    camera.data.type = "PERSP"
    camera.data.lens = 35
    scene.camera = camera
    add_area_light("Distance key", (-3.5, -4.0, 7.0), (0, 0, 0), 760, 5.0, (1.0, 0.85, 0.65))
    add_area_light("Distance fill", (3.0, 1.0, 4.5), (0, 0, 0.4), 380, 4.0, (0.69, 0.82, 1.0))
    set_world((0.28, 0.37, 0.31, 1), 0.65)
    render_settings(1800, 1100)
    scene.render.filepath = str(REVIEW_DIR / "gameplay_distance.png")
    bpy.ops.render.render(write_still=True)


def export_items(items_by_slug):
    catalog = {"version": 1, "terrainLayers": [], "materials": {}}
    for item in items_by_slug.values():
        for material_value in item.data.materials:
            shader = material_value.node_tree.nodes.get("Principled BSDF")
            color = list(material_value.diffuse_color)
            catalog["materials"][material_value.name] = {
                "baseColorFactor": color,
                "roughnessFactor": float(shader.inputs["Roughness"].default_value),
                "metallicFactor": float(shader.inputs["Metallic"].default_value),
                "alphaCutoff": 0.48,
                "doubleSided": material_value.name.endswith("_hide"),
                "baseColor": None,
                "normal": None,
                "roughness": None,
                "metallic": None,
                "ambientOcclusion": None,
                "opacity": None,
                "uvScale": 1.0,
            }
    (EXPORT_DIR / "materials.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    summaries = []
    for definition in ITEMS:
        item = items_by_slug[definition["slug"]]
        bpy.ops.object.select_all(action="DESELECT")
        item.select_set(True)
        bpy.context.view_layer.objects.active = item
        filepath = EXPORT_DIR / f"{definition['slug']}.obj"
        bpy.ops.wm.obj_export(
            filepath=str(filepath),
            export_selected_objects=True,
            export_materials=True,
            export_uv=True,
            export_normals=True,
            export_colors=True,
            export_pbr_extensions=True,
            export_triangulated_mesh=False,
            forward_axis="NEGATIVE_Z",
            up_axis="Y",
            global_scale=1.0,
            path_mode="COPY",
        )
        summaries.append({"name": item.name, "vertices": len(item.data.vertices), "faces": len(item.data.polygons), "bounds_m": [round(float(value), 4) for value in item.dimensions], "obj": filepath.name})
    bpy.ops.object.select_all(action="DESELECT")
    return summaries


def build_scene():
    for path in (OUTPUT, REFERENCE_DIR, EXPORT_DIR, REVIEW_DIR, REVIEW_DIR / "angles"):
        path.mkdir(parents=True, exist_ok=True)
    items_collection = clear_scene()
    for definition in ITEMS:
        source_icon = AINCRAD2 / "content" / "icons" / f"{definition['slug']}.webp"
        local_icon = REFERENCE_DIR / f"{definition['slug']}.webp"
        if not source_icon.is_file():
            raise FileNotFoundError(source_icon)
        shutil.copy2(source_icon, local_icon)
    items_by_slug = {}
    material_catalog = {}
    for definition in ITEMS:
        mats = materials_for(definition["slug"].replace("-", "_"))
        parts = BUILDERS[definition["slug"]](mats)
        item = join_item(definition["name"], parts, items_collection)
        items_by_slug[definition["slug"]] = item
        material_catalog[definition["slug"]] = mats
    for item in items_by_slug.values():
        item.hide_render = True
    for definition in ITEMS:
        render_item_angles(items_by_slug[definition["slug"]], definition, material_catalog[definition["slug"]])
    create_contact_sheet(items_by_slug, items_collection)
    create_gameplay_distance(items_by_slug)
    summaries = export_items(items_by_slug)
    scene = bpy.context.scene
    scene.render.filepath = str(REVIEW_DIR / "contact_sheet.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "floor1_item_factory.blend"))
    return {
        "blender": bpy.app.version_string,
        "item_count": len(ITEMS),
        "blend": str(OUTPUT / "floor1_item_factory.blend"),
        "contact_sheet": str(REVIEW_DIR / "contact_sheet.png"),
        "gameplay_distance": str(REVIEW_DIR / "gameplay_distance.png"),
        "exports": summaries,
    }


result = build_scene()
