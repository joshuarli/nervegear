import json
import math
import os
import shutil
import stat
import zipfile
from pathlib import Path, PurePosixPath

import bpy
from mathutils import Vector

root = Path(os.environ.get('NERVEGEAR_ROOT', Path.cwd())).expanduser().resolve()
source_directory = Path(os.environ.get('NERVEGEAR_ASUNA_SOURCE', Path.home() / 'Downloads' / 'asuna')).expanduser().resolve()
work_directory = Path(os.environ.get('NERVEGEAR_ASUNA_WORK', root / '.work' / 'tmp' / 'asuna-source')).expanduser().resolve()
output_directory = Path(os.environ.get('NERVEGEAR_ASUNA_OUTPUT', root / 'Assets' / 'Objects' / 'Characters' / 'Asuna')).expanduser().resolve()
review_directory = output_directory / 'review'


def extract_checked(archive_path, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive_path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            member = PurePosixPath(name)
            mode = entry.external_attr >> 16
            if '\\' in name or member.is_absolute() or any(part in ('', '.', '..') for part in member.parts):
                raise RuntimeError('unsafe archive path: ' + name)
            if stat.S_ISLNK(mode) or (mode and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode))):
                raise RuntimeError('unsupported archive entry type: ' + name)
            target = (destination / Path(*member.parts)).resolve()
            if target != destination and destination not in target.parents:
                raise RuntimeError('archive entry escapes destination: ' + name)
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open('wb') as output:
                    shutil.copyfileobj(source, output)


extract_checked(source_directory / 'asuna+fbx.zip', work_directory)
extract_checked(source_directory / 'texture.zip', work_directory)
fbx_path = work_directory / 'asuna.fbx'
body_texture = work_directory / 'texture' / 'badan.png'
face_texture = work_directory / 'texture' / 'wajah.png'
for path in (fbx_path, body_texture, face_texture):
    if not path.is_file() or path.is_symlink():
        raise RuntimeError('required source file is missing or invalid: ' + str(path))

output_directory.mkdir(parents=True, exist_ok=True)
texture_directory = output_directory / 'Textures'
texture_directory.mkdir(parents=True, exist_ok=True)
shutil.copy2(body_texture, texture_directory / 'badan.png')
shutil.copy2(face_texture, texture_directory / 'wajah.png')
review_directory.mkdir(parents=True, exist_ok=True)

scene = bpy.context.scene
scene.camera = None
for obj in tuple(scene.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for collection in tuple(bpy.data.collections):
    bpy.data.collections.remove(collection)
for mesh in tuple(bpy.data.meshes):
    bpy.data.meshes.remove(mesh)
for material in tuple(bpy.data.materials):
    bpy.data.materials.remove(material)
for image in tuple(bpy.data.images):
    if image.name not in {'Render Result', 'Viewer Node'}:
        bpy.data.images.remove(image)
bpy.ops.import_scene.fbx(filepath=str(fbx_path))
mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
if not mesh_objects:
    raise RuntimeError('FBX importer produced no mesh objects')

for obj in mesh_objects:
    obj.data = obj.data.copy()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world.identity()

positions = [vertex.co.copy() for obj in mesh_objects for vertex in obj.data.vertices]
minimum = Vector((min(point.x for point in positions), min(point.y for point in positions), min(point.z for point in positions)))
maximum = Vector((max(point.x for point in positions), max(point.y for point in positions), max(point.z for point in positions)))
source_height = maximum.z - minimum.z
if not 0.1 <= source_height <= 10:
    raise RuntimeError('FBX bounds are implausible: ' + str(source_height))
scale = 1.7 / source_height
center_x = (minimum.x + maximum.x) * 0.5
center_y = (minimum.y + maximum.y) * 0.5
for obj in mesh_objects:
    for vertex in obj.data.vertices:
        vertex.co = Vector(((vertex.co.x - center_x) * scale, (vertex.co.y - center_y) * scale, (vertex.co.z - minimum.z) * scale))
    obj.data.update()

arms = next((obj for obj in mesh_objects if obj.name == 'tangan'), None)
if arms is None:
    raise RuntimeError('FBX is missing the arm mesh')
pose_angle = 0.78
for vertex in arms.data.vertices:
    side = 1 if vertex.co.x >= 0 else -1
    if abs(vertex.co.x) < 0.16:
        continue
    pivot = Vector((side * 0.16, 0.06, 1.28))
    offset = vertex.co - pivot
    angle = side * pose_angle
    vertex.co.x = pivot.x + offset.x * math.cos(angle) + offset.z * math.sin(angle)
    vertex.co.z = pivot.z - offset.x * math.sin(angle) + offset.z * math.cos(angle)
arms.data.update()

body_material = bpy.data.materials.get('badan')
face_material = bpy.data.materials.get('wajah')
if body_material is None or face_material is None:
    raise RuntimeError('FBX did not preserve its badan and wajah material slots')
body_material.name = 'asuna_body'
face_material.name = 'asuna_face'


def set_texture(material, image_path, material_color):
    material.use_nodes = True
    material.diffuse_color = material_color
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial')
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    shader.inputs['Roughness'].default_value = 0.78
    shader.inputs['Metallic'].default_value = 0.0
    image = bpy.data.images.load(str(image_path), check_existing=False)
    image.colorspace_settings.name = 'sRGB'
    image.filepath = '//Textures/' + image_path.name
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = image
    material.node_tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    material.node_tree.links.new(shader.outputs['BSDF'], output.inputs['Surface'])


set_texture(body_material, texture_directory / 'badan.png', (0.8, 0.72, 0.58, 1))
set_texture(face_material, texture_directory / 'wajah.png', (0.94, 0.78, 0.72, 1))

character_collection = bpy.data.collections.new('Asuna')
bpy.context.scene.collection.children.link(character_collection)
root_object = bpy.data.objects.new('Asuna', None)
root_object.empty_display_type = 'PLAIN_AXES'
character_collection.objects.link(root_object)
for obj in mesh_objects:
    for collection in tuple(obj.users_collection):
        collection.objects.unlink(obj)
    character_collection.objects.link(obj)
    obj.parent = root_object
    obj.matrix_parent_inverse.identity()

normalized_positions = [vertex.co for obj in mesh_objects for vertex in obj.data.vertices]
normalized_bounds = [[min(point[i] for point in normalized_positions), max(point[i] for point in normalized_positions)] for i in range(3)]
normalized_height = normalized_bounds[2][1] - normalized_bounds[2][0]
if abs(normalized_height - 1.7) > 0.002 or abs(normalized_bounds[2][0]) > 0.002:
    raise RuntimeError('normalized model bounds failed validation: ' + str(normalized_bounds))

catalog = {
    'version': 1,
    'terrainLayers': [],
    'materials': {
        'asuna_body': {
            'baseColorFactor': [1, 1, 1, 1],
            'roughnessFactor': 0.78,
            'metallicFactor': 0,
            'alphaCutoff': 0.5,
            'doubleSided': True,
            'baseColor': 'Textures/badan.png',
            'normal': None,
            'roughness': None,
            'metallic': None,
            'ambientOcclusion': None,
            'opacity': None,
            'uvScale': 1
        },
        'asuna_face': {
            'baseColorFactor': [1, 1, 1, 1],
            'roughnessFactor': 0.82,
            'metallicFactor': 0,
            'alphaCutoff': 0.5,
            'doubleSided': True,
            'baseColor': 'Textures/wajah.png',
            'normal': None,
            'roughness': None,
            'metallic': None,
            'ambientOcclusion': None,
            'opacity': None,
            'uvScale': 1
        }
    }
}
(output_directory / 'materials.json').write_text(json.dumps(catalog, indent=2) + '\n', encoding='utf-8')

settings = bpy.context.preferences.filepaths
settings.save_version = 0
blend_path = output_directory / 'asuna.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

for obj in bpy.context.scene.objects:
    obj.select_set(False)
for obj in mesh_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_objects[0]
obj_path = output_directory / 'asuna.obj'
bpy.ops.wm.obj_export(
    filepath=str(obj_path),
    forward_axis='NEGATIVE_Z',
    up_axis='Y',
    global_scale=1,
    apply_modifiers=True,
    apply_transform=True,
    export_selected_objects=True,
    export_uv=True,
    export_normals=True,
    export_colors=False,
    export_materials=True,
    export_pbr_extensions=True,
    path_mode='RELATIVE',
    export_triangulated_mesh=True,
    export_object_groups=True,
    export_material_groups=True
)

materials_file = output_directory / 'materials.json'
manifest = {
    'asset': 'Asuna',
    'sourceFiles': ['asuna+fbx.zip', 'texture.zip'],
    'sourceModel': 'asuna.fbx',
    'model': 'asuna.obj',
    'blenderSource': 'asuna.blend',
    'materialCatalog': 'materials.json',
    'textures': {'asuna_body': 'Textures/badan.png', 'asuna_face': 'Textures/wajah.png'},
    'sourceMeshes': [{'name': obj.name, 'vertices': len(obj.data.vertices), 'triangles': sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)} for obj in mesh_objects],
    'normalization': {'heightMetres': normalized_height, 'origin': 'ground center', 'blenderUpAxis': 'Z', 'exportUpAxis': 'Y', 'forwardAxis': '-Z', 'staticArmPoseRadians': pose_angle},
    'bounds': normalized_bounds,
    'rigged': False,
    'animationClips': [],
    'distribution': 'private local development prototype'
}
(output_directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')

scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 768
scene.render.resolution_y = 960
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'Standard'
if scene.world is None:
    scene.world = bpy.data.worlds.new('World')
scene.world.color = (0.12, 0.15, 0.18)
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.12, 0.15, 0.18, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.65

ground_material = bpy.data.materials.new('StudioGround')
ground_material.diffuse_color = (0.18, 0.21, 0.22, 1)
ground_material.use_nodes = True
ground_material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.18, 0.21, 0.22, 1)
ground_material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.92
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.008))
ground = bpy.context.object
ground.name = 'StudioGround'
ground.data.materials.append(ground_material)


def add_area_light(name, location, energy, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.shape = 'DISK'
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector((0, 0, 0.9)) - light.location).to_track_quat('-Z', 'Y').to_euler()
    return light


add_area_light('KeyLight', (3.2, -3.6, 4.8), 180, 3.6, (1.0, 0.86, 0.72))
add_area_light('FillLight', (-3.4, -2.2, 2.8), 120, 4.2, (0.72, 0.83, 1.0))
add_area_light('RimLight', (0.2, 3.4, 3.7), 220, 3.0, (1.0, 0.88, 0.70))

camera_data = bpy.data.cameras.new('ReviewCamera')
camera = bpy.data.objects.new('ReviewCamera', camera_data)
scene.collection.objects.link(camera)
camera_data.lens = 55
scene.camera = camera


def render_view(name, position, target, lens):
    camera.location = position
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data.lens = lens
    scene.render.filepath = str(review_directory / (name + '.png'))
    bpy.ops.render.render(write_still=True)


render_view('front', (0, 3.3, 1.05), (0, 0, 0.88), 55)
render_view('back', (0, -3.3, 1.05), (0, 0, 0.88), 55)
render_view('three_quarter', (1.35, 3.2, 1.08), (0, 0, 0.88), 55)
render_view('face_closeup', (0, 1.0, 1.50), (0, 0, 1.48), 70)

result = {
    'blend': str(blend_path),
    'obj': str(obj_path),
    'materials': str(materials_file),
    'manifest': str(output_directory / 'manifest.json'),
    'renders': [str(path) for path in sorted(review_directory.glob('*.png'))],
    'bounds': normalized_bounds,
    'sourceHeightMetres': source_height,
    'normalizedHeightMetres': normalized_height,
    'meshes': len(mesh_objects),
    'vertices': sum(len(obj.data.vertices) for obj in mesh_objects),
    'triangles': sum(sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons) for obj in mesh_objects),
    'materials': [material.name for material in (body_material, face_material)]
}
