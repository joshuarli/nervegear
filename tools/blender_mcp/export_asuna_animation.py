import json
import os
import shutil
from pathlib import Path

import bpy


root = Path(__file__).resolve().parents[2]
asset_directory = root / 'Assets' / 'Objects' / 'Characters' / 'Asuna'
source_blend = asset_directory / 'rig_review' / 'asuna_rigged.blend'
output_directory = asset_directory / 'animation'
staging_directory = root / '.work' / 'tmp' / 'asuna-animation-export'

if source_blend.is_symlink() or not source_blend.is_file():
    raise RuntimeError('Rigify Asuna source blend is missing or invalid')
if staging_directory == root or root not in staging_directory.parents:
    raise RuntimeError('animation staging directory is outside the repository')

shutil.rmtree(staging_directory, ignore_errors=True)
staging_directory.mkdir(parents=True)
bpy.ops.wm.open_mainfile(filepath=str(source_blend))
scene = bpy.context.scene
rig = bpy.data.objects.get('Asuna_Rig')
action = bpy.data.actions.get('Asuna_Walk_InPlace')
if rig is None or action is None:
    raise RuntimeError('Rigify walk action is missing')

mesh_names = {'body', 'kaki', 'kepala', 'rambut', 'tangan'}
mesh_objects = sorted(
    (obj for obj in bpy.context.view_layer.objects if obj.type == 'MESH' and obj.name in mesh_names),
    key=lambda obj: obj.name
)
if {obj.name for obj in mesh_objects} != mesh_names:
    raise RuntimeError('Rigify source does not contain all five Asuna meshes')

rig.animation_data.action = action
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 25
scene.render.image_settings.file_format = 'PNG'
frames = []
for index, frame in enumerate(range(1, 25)):
    scene.frame_set(frame)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    name = f'walk_{index:03d}.obj'
    bpy.ops.wm.obj_export(
        filepath=str(staging_directory / name),
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
    if not (staging_directory / name).is_file():
        raise RuntimeError('Blender did not export animation frame ' + name)
    frames.append(name)

output_directory.mkdir(parents=True, exist_ok=True)
material_library = 'newmtl asuna_body\nKd 1 1 1\nd 1.0\n\nnewmtl asuna_face\nKd 1 1 1\nd 1.0\n'
for staged_file in staging_directory.glob('*.mtl'):
    staged_file.write_text(material_library, encoding='utf-8')
for staged_file in staging_directory.iterdir():
    if staged_file.suffix in {'.obj', '.mtl'}:
        os.replace(staged_file, output_directory / staged_file.name)
manifest = {
    'version': 1,
    'frameRate': 30,
    'frames': frames
}
manifest_path = output_directory / 'walk.json'
manifest_staging_path = staging_directory / 'walk.json'
manifest_staging_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
os.replace(manifest_staging_path, manifest_path)
shutil.rmtree(staging_directory)
print(f'Exported {len(frames)} Asuna walk frames to {output_directory}')
