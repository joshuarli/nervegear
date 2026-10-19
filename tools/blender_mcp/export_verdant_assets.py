import bpy
import json
import os
from mathutils import Vector
from pathlib import Path

blend_path = Path(bpy.data.filepath)
if not blend_path.is_file():
    raise ValueError("save or open the source blend file before exporting")
blend_directory = blend_path.resolve().parent
source_root = Path(os.environ.get("NERVEGEAR_SOURCE_TEXTURES", blend_directory / "textures")).expanduser().resolve()
output_root = Path(os.environ.get("NERVEGEAR_ASSET_OUTPUT", blend_directory / "NervegearExport")).expanduser().resolve()
if not source_root.is_dir():
    raise FileNotFoundError(str(source_root))
if source_root == output_root:
    raise ValueError("asset output directory must differ from the source texture directory")
texture_root = output_root / "Textures"
texture_root.mkdir(parents=True, exist_ok=True)

asset_objects = {
    "Boulder_01": ("boulder_01.002", 1.0),
    "Boulder_02": ("boulder_01.003", 1.0),
    "Boulder_03": ("boulder_01.004", 1.0),
    "Rock_Face": ("rock_face", 1.0),
    "Rock_Face_2": ("rock_face_2.001", 1.0),
    "Rock_07": ("rock_07.001", 2.5),
    "Rock_08": ("rock_08.001", 2.0),
    "Shrub_02": ("shrub_02_a", 1.0),
    "Shrub_03": ("shrub_03_a", 2.2),
    "Shrub_04": ("shrub_04_c", 4.0),
    "Wild_Grass": ("grass_medium_02_e", 3.0),
    "Wild_Grass_B": ("grass_medium_02_d", 3.4),
    "Wild_Grass_C": ("grass_medium_02_c", 4.5),
    "Wild_Grass_D": ("grass_medium_02_b", 6.0),
}
texture_specs = {
    "boulder_01": {"baseColor": "boulder_01_diff.png", "normal": "boulder_01_nor_gl.png", "roughness": "boulder_01_rough.png"},
    "rock_face": {"baseColor": "rock_face_diff.png", "normal": "rock_face_nor_gl.png", "roughness": "rock_face_rough.png"},
    "rock_face_2": {"baseColor": "rock_face_2_diff.png", "normal": "rock_face_2_nor_gl.png", "roughness": "rock_face_2_rough.png"},
    "rock_07": {"baseColor": "rock_07_diff.png", "normal": "rock_07_nor_gl.png", "roughness": "rock_07_rough.png"},
    "rock_08": {"baseColor": "rock_08_diff.png", "normal": "rock_08_nor_gl.png", "roughness": "rock_08_rough.png"},
    "shrub_02": {"baseColor": "shrub_02_diff.png", "normal": "shrub_02_nor_gl.png", "roughness": "shrub_02_rough.png", "opacity": "shrub_02_alpha.png"},
    "shrub_03": {"baseColor": "shrub_03_diff.png", "normal": "shrub_03_nor_gl.png", "roughness": "shrub_03_rough.png", "opacity": "shrub_03_alpha.png"},
    "shrub_04": {"baseColor": "shrub_04_diff.png", "normal": "shrub_04_nor_gl.png", "roughness": "shrub_04_rough.png", "opacity": "shrub_04_alpha.png"},
    "grass_medium_02": {"baseColor": "grass_medium_02_diff.png", "normal": "grass_medium_02_nor_gl.png", "roughness": "grass_medium_02_rough.png", "opacity": "grass_medium_02_alpha.png"},
    "forest_ground_04": {"baseColor": "forest_ground_04_diff_2k.jpg", "normal": "forest_ground_04_nor_gl_2k.exr", "roughness": "forest_ground_04_rough_2k.exr"},
    "dirt_floor": {"baseColor": "dirt_floor_diff_4k.png", "normal": "dirt_floor_nor_gl_4k.png", "roughness": "dirt_floor_rough_4k.png"},
    "rock_face_01": {"baseColor": "rock_face_01_diff.png", "normal": "rock_face_01_nor_gl.png", "roughness": "rock_face_01_rough.png"},
}

def settle_rock(mesh):
    mesh.update()
    bounds = [vertex.co for vertex in mesh.vertices]
    dimensions = [max(vertex[axis] for vertex in bounds) - min(vertex[axis] for vertex in bounds) for axis in range(3)]
    plane_tolerance = max(dimensions) * 0.015
    groups = {}
    for polygon in mesh.polygons:
        normal = polygon.normal.normalized()
        offset = normal.dot(polygon.center)
        key = tuple(round(component / 0.05) for component in normal) + (round(offset / plane_tolerance),)
        area, normal_sum, centers, vertex_ids = groups.get(key, (0.0, Vector(), [], set()))
        groups[key] = (area + polygon.area, normal_sum + normal * polygon.area, centers + [polygon.center.copy()], vertex_ids.union(polygon.vertices))
    volume = 0.0
    weighted_center = Vector()
    for polygon in mesh.polygons:
        vertices = [mesh.vertices[index].co for index in polygon.vertices]
        for index in range(1, len(vertices) - 1):
            first, second, third = vertices[0], vertices[index], vertices[index + 1]
            signed_volume = first.dot(second.cross(third)) / 6.0
            volume += signed_volume
            weighted_center += (first + second + third) * (signed_volume / 4.0)
    center_of_mass = weighted_center / volume if abs(volume) > 1e-8 else sum(bounds, Vector()) / len(bounds)
    candidates = []
    for key, (area, normal_sum, centers, vertex_ids) in groups.items():
        contact_normal = normal_sum.normalized()
        plane_center = sum(centers, Vector()) / len(centers)
        points = [mesh.vertices[index].co for index in vertex_ids]
        if max(abs((point - plane_center).dot(contact_normal)) for point in points) > plane_tolerance:
            continue
        reference_axis = Vector((0.0, 0.0, 1.0)) if abs(contact_normal.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        tangent = contact_normal.cross(reference_axis).normalized()
        bitangent = contact_normal.cross(tangent).normalized()
        projected = sorted({(round(point.dot(tangent), 6), round(point.dot(bitangent), 6)) for point in points})
        hull = []
        for point in projected:
            while len(hull) >= 2 and (hull[-1][0] - hull[-2][0]) * (point[1] - hull[-1][1]) - (hull[-1][1] - hull[-2][1]) * (point[0] - hull[-1][0]) <= 0:
                hull.pop()
            hull.append(point)
        lower_hull = len(hull)
        for point in reversed(projected[:-1]):
            while len(hull) >= lower_hull + 1 and (hull[-1][0] - hull[-2][0]) * (point[1] - hull[-1][1]) - (hull[-1][1] - hull[-2][1]) * (point[0] - hull[-1][0]) <= 0:
                hull.pop()
            hull.append(point)
        hull.pop()
        if len(hull) < 3:
            continue
        center_2d = (center_of_mass.dot(tangent), center_of_mass.dot(bitangent))
        margins = []
        for index, first in enumerate(hull):
            second = hull[(index + 1) % len(hull)]
            edge_x, edge_y = second[0] - first[0], second[1] - first[1]
            edge_length = (edge_x * edge_x + edge_y * edge_y) ** 0.5
            margins.append((edge_x * (center_2d[1] - first[1]) - edge_y * (center_2d[0] - first[0])) / edge_length)
        margin = min(margins)
        if margin > max(dimensions) * 0.005:
            candidates.append((area * margin, area, key, contact_normal, margin))
    if not candidates:
        raise ValueError("rock has no broad support face containing its center of mass")
    _, _, _, contact_normal, margin = max(candidates)
    rotation = contact_normal.normalized().rotation_difference(Vector((0.0, 0.0, -1.0)))
    center = sum(bounds, Vector()) / len(bounds)
    for vertex in mesh.vertices:
        vertex.co = center + rotation @ (vertex.co - center)
    mesh.update()
    return margin

surface_materials = {}
image_settings = bpy.context.scene.render.image_settings
previous_image_settings = (image_settings.color_depth, image_settings.color_mode, image_settings.quality)
previous_selection = tuple(bpy.context.selected_objects)
previous_active_object = bpy.context.view_layer.objects.active
try:
    for material_name, maps in texture_specs.items():
        surface = {
            "baseColorFactor": [0.48, 1.0, 0.36, 1.0] if material_name == "grass_medium_02" else ([0.48, 1.0, 0.62, 1.0] if material_name.startswith("shrub_") else [1.0, 1.0, 1.0, 1.0]),
            "roughnessFactor": 1.0,
            "metallicFactor": 0.0,
            "alphaCutoff": 0.48,
            "doubleSided": material_name.startswith("shrub_") or material_name == "grass_medium_02",
        }
        for channel, filename in maps.items():
            source = source_root / filename
            if not source.is_file():
                raise FileNotFoundError(str(source))
            source_image = bpy.data.images.load(str(source), check_existing=False)
            try:
                source_image.colorspace_settings.name = "sRGB" if channel == "baseColor" else "Non-Color"
                width, height = (int(source_image.size[0]), int(source_image.size[1]))
                max_dimension = 2048 if channel == "baseColor" or material_name in {"forest_ground_04", "dirt_floor", "rock_face_01"} else 1024
                scale = min(1.0, max_dimension / max(width, height))
                if scale < 1.0:
                    source_image.scale(max(1, round(width * scale)), max(1, round(height * scale)))
                suffix = "jpg" if channel == "baseColor" else "png"
                output_name = f"{material_name}_{channel}.{suffix}"
                destination = texture_root / output_name
                source_image.filepath_raw = str(destination)
                source_image.file_format = "JPEG" if suffix == "jpg" else "PNG"
                image_settings.color_depth = "8"
                image_settings.color_mode = "RGB" if channel in ("baseColor", "normal") else "BW"
                image_settings.quality = 91
                source_image.save()
            finally:
                bpy.data.images.remove(source_image)
            surface[channel] = f"Textures/{output_name}"
        if material_name in {"forest_ground_04", "dirt_floor", "rock_face_01"}:
            surface["uvScale"] = {"forest_ground_04": 0.42, "dirt_floor": 0.34, "rock_face_01": 0.3}[material_name]
        surface_materials[material_name] = surface
finally:
    image_settings.color_depth, image_settings.color_mode, image_settings.quality = previous_image_settings

exports = []
for asset_name, (source_name, scale_factor) in asset_objects.items():
    source = bpy.data.objects.get(source_name)
    if source is None or source.type != "MESH":
        raise ValueError(f"missing mesh object: {source_name}")
    material_names = [slot.material.name for slot in source.material_slots if slot.material]
    if len(material_names) != 1:
        raise ValueError(f"expected one material on {source_name}, got {material_names}")
    material_name = material_names[0]
    if material_name not in surface_materials:
        raise ValueError(f"missing material catalog entry: {material_name}")
    duplicate = source.copy()
    duplicate.data = source.data.copy()
    duplicate_mesh = duplicate.data
    bpy.context.scene.collection.objects.link(duplicate)
    try:
        duplicate.parent = None
        duplicate.matrix_world = source.matrix_world.copy()
        duplicate.location = (0.0, 0.0, 0.0)
        duplicate.scale = tuple(float(value) * scale_factor for value in duplicate.scale)
        bpy.ops.object.select_all(action="DESELECT")
        duplicate.select_set(True)
        bpy.context.view_layer.objects.active = duplicate
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        support_margin = settle_rock(duplicate.data) if asset_name.startswith(("Boulder_", "Rock_")) else None
        xs = [float(vertex.co.x) for vertex in duplicate.data.vertices]
        ys = [float(vertex.co.y) for vertex in duplicate.data.vertices]
        zs = [float(vertex.co.z) for vertex in duplicate.data.vertices]
        center_x = (min(xs) + max(xs)) * 0.5
        center_y = (min(ys) + max(ys)) * 0.5
        min_z = min(zs)
        for vertex in duplicate.data.vertices:
            vertex.co.x -= center_x
            vertex.co.y -= center_y
            vertex.co.z -= min_z
        filepath = output_root / f"{asset_name}.obj"
        filepath.unlink(missing_ok=True)
        (output_root / f"{asset_name}.mtl").unlink(missing_ok=True)
        bpy.ops.wm.obj_export(
            filepath=str(filepath),
            export_selected_objects=True,
            export_materials=True,
            export_pbr_extensions=False,
            path_mode="STRIP",
            forward_axis="NEGATIVE_Z",
            up_axis="Y",
            apply_modifiers=False,
            apply_transform=True,
            export_uv=True,
            export_normals=True,
            export_triangulated_mesh=True,
            export_object_groups=False,
            export_material_groups=True,
        )
        mtl_path = output_root / f"{asset_name}.mtl"
        surface = surface_materials[material_name]
        lines = [f"newmtl {material_name}", "Ka 0.000000 0.000000 0.000000", "Kd 1.000000 1.000000 1.000000", "Ks 0.000000 0.000000 0.000000", "Ns 32.000000", "d 1.000000"]
        lines.append(f"map_Kd {surface['baseColor']}")
        if "opacity" in surface:
            lines.append(f"map_d {surface['opacity']}")
        mtl_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        vertex_count = sum(1 for line in filepath.read_text(encoding="utf-8").splitlines() if line.startswith("v "))
        exports.append({"asset": asset_name, "source": source_name, "material": material_name, "faces": len(duplicate.data.polygons), "obj_vertices": vertex_count, "scale_factor": scale_factor, "support_margin": support_margin})
    finally:
        bpy.data.objects.remove(duplicate, do_unlink=True)
        bpy.data.meshes.remove(duplicate_mesh)

bpy.ops.object.select_all(action="DESELECT")
for selected_object in previous_selection:
    selected_object.select_set(True)
bpy.context.view_layer.objects.active = previous_active_object

catalog = {
    "version": 1,
    "terrainLayers": ["forest_ground_04", "dirt_floor", "rock_face_01"],
    "materials": surface_materials,
}
(output_root / "materials.json").write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n", encoding="utf-8")
result = {"output": str(output_root), "exports": exports, "texture_count": sum(len(spec) for spec in texture_specs.values()), "output_bytes": sum(path.stat().st_size for path in output_root.rglob("*") if path.is_file())}
print(json.dumps(result, indent=2))
