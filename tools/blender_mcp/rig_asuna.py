import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


root = Path(__file__).resolve().parents[2]
asset_directory = root / 'Assets' / 'Objects' / 'Characters' / 'Asuna'
source_blend = asset_directory / 'asuna.blend'
review_directory = asset_directory / 'rig_review'
review_directory.mkdir(parents=True, exist_ok=True)
if source_blend.is_symlink() or not source_blend.is_file():
    raise RuntimeError('prepared Asuna Blender source is missing or invalid')

bpy.ops.wm.open_mainfile(filepath=str(source_blend))
bpy.ops.preferences.addon_enable(module='rigify')
scene = bpy.context.scene
root_object = bpy.data.objects.get('Asuna')
mesh_objects = sorted((obj for obj in scene.objects if obj.type == 'MESH'), key=lambda obj: obj.name)
if root_object is None or len(mesh_objects) != 5:
    raise RuntimeError('prepared asset must contain the Asuna root and five mesh parts')

for image in bpy.data.images:
    if image.source == 'FILE' and image.filepath:
        resolved = Path(bpy.path.abspath(image.filepath)).resolve()
        if resolved.is_file():
            image.filepath = str(resolved)

bpy.ops.object.armature_human_metarig_add()
metarig = bpy.context.object
metarig.name = 'Asuna_Rigify_Metarig'
metarig.rotation_euler.z = math.pi
metarig.scale = (1.7 / 1.98,) * 3
bpy.context.view_layer.objects.active = metarig
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

fit = {
    'spine': ((0, 0, 0.82), (0, 0, 0.97)),
    'spine.001': ((0, 0, 0.97), (0, 0, 1.11)),
    'spine.002': ((0, 0, 1.11), (0, 0, 1.27)),
    'spine.003': ((0, 0, 1.27), (0, 0, 1.41)),
    'spine.004': ((0, 0, 1.41), (0, 0, 1.48)),
    'spine.005': ((0, 0, 1.48), (0, 0, 1.54)),
    'spine.006': ((0, 0, 1.54), (0, 0, 1.65)),
}
for side, sign in (('L', -1), ('R', 1)):
    fit.update({
        f'shoulder.{side}': ((0, 0, 1.34), (sign * 0.145, 0.015, 1.34)),
        f'upper_arm.{side}': ((sign * 0.145, 0.015, 1.34), (sign * 0.175, 0.02, 1.08)),
        f'forearm.{side}': ((sign * 0.175, 0.02, 1.08), (sign * 0.195, 0.01, 0.81)),
        f'hand.{side}': ((sign * 0.195, 0.01, 0.81), (sign * 0.20, 0.0, 0.75)),
        f'thigh.{side}': ((sign * 0.085, 0.015, 0.91), (sign * 0.09, 0.02, 0.48)),
        f'shin.{side}': ((sign * 0.09, 0.02, 0.48), (sign * 0.09, -0.005, 0.09)),
        f'foot.{side}': ((sign * 0.09, -0.005, 0.09), (sign * 0.09, 0.12, 0.04)),
        f'toe.{side}': ((sign * 0.09, 0.12, 0.04), (sign * 0.09, 0.19, 0.04)),
    })
bpy.ops.object.mode_set(mode='EDIT')
for name, (head, tail) in fit.items():
    bone = metarig.data.edit_bones[name]
    bone.head = Vector(head)
    bone.tail = Vector(tail)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
metarig.select_set(True)
bpy.context.view_layer.objects.active = metarig
bpy.ops.pose.rigify_generate()
generated_rigs = [obj for obj in scene.objects if obj.type == 'ARMATURE' and obj != metarig]
if len(generated_rigs) != 1:
    raise RuntimeError('Rigify did not generate an armature')
rig = generated_rigs[0]
rig.name = 'Asuna_Rig'
metarig.hide_set(True)
metarig.hide_render = True
rig.parent = root_object
rig.show_in_front = True
for side in ('L', 'R'):
    rig.pose.bones[f'thigh_parent.{side}']['IK_FK'] = 1.0
    rig.pose.bones[f'upper_arm_parent.{side}']['IK_FK'] = 1.0

deform_names = {bone.name for bone in rig.data.bones if bone.name.startswith('DEF-')}


def required_bones(names):
    missing = set(names) - deform_names
    if missing:
        raise RuntimeError('Rigify generated missing deformation bones: ' + ', '.join(sorted(missing)))
    return names


spine_names = required_bones([f'DEF-spine{suffix}' for suffix in ('', '.001', '.002', '.003', '.004', '.005', '.006')])
required_bones([f'DEF-{part}.{side}' for side in ('L', 'R') for part in ('thigh', 'shin', 'foot', 'toe')])
required_bones([f'DEF-{part}.{side}' for side in ('L', 'R') for part in ('shoulder', 'upper_arm', 'forearm', 'hand')])


def segment_distance(point, head, tail):
    direction = tail - head
    magnitude = direction.length_squared
    if magnitude == 0:
        return (point - head).length
    fraction = max(0.0, min(1.0, (point - head).dot(direction) / magnitude))
    return (point - (head + fraction * direction)).length


def candidate_bones(obj, point):
    side = 'L' if point.x < 0 else 'R'
    if obj.name == 'kepala':
        return ['DEF-spine.006']
    if obj.name == 'kaki':
        if abs(point.x) < 0.045:
            return [f'DEF-{part}.{side}' for part in ('thigh', 'shin', 'foot', 'toe')] + [f'DEF-{part}.R' if side == 'L' else f'DEF-{part}.L' for part in ('thigh', 'shin', 'foot', 'toe')]
        return [f'DEF-{part}.{side}' for part in ('thigh', 'shin', 'foot', 'toe')]
    if obj.name == 'tangan':
        names = [f'DEF-{part}.{side}' for part in ('shoulder', 'upper_arm', 'forearm', 'hand')]
        if abs(point.x) < 0.06:
            names += ['DEF-spine.002', 'DEF-spine.003']
        return names
    if obj.name == 'rambut':
        return ['DEF-spine.003', 'DEF-spine.004', 'DEF-spine.005', 'DEF-spine.006']
    if point.z < 0.72:
        return ['DEF-spine']
    if point.z < 0.93:
        return ['DEF-spine', 'DEF-spine.001']
    names = spine_names[:5]
    if point.z > 1.25 and abs(point.x) > 0.14:
        names.append(f'DEF-shoulder.{side}')
    return names


def assign_weights(obj):
    values = {}
    for vertex in obj.data.vertices:
        point = obj.matrix_world @ vertex.co
        names = candidate_bones(obj, point)
        if len(names) == 1:
            values.setdefault(names[0], []).append((vertex.index, 1.0))
            continue
        distances = []
        for name in names:
            bone = rig.data.bones[name]
            distance = segment_distance(point, bone.head_local, bone.tail_local)
            distances.append((distance, name))
        closest = sorted(distances)[:2]
        scores = [math.exp(-((distance / 0.075) ** 2)) for distance, _ in closest]
        total = sum(scores)
        if total < 1e-8:
            scores = [1.0, 0.0]
            total = 1.0
        for score, (_, name) in zip(scores, closest):
            weight = score / total
            if weight > 0.001:
                values.setdefault(name, []).append((vertex.index, weight))
    for name, assignments in values.items():
        group = obj.vertex_groups.new(name=name)
        for index, weight in assignments:
            group.add([index], weight, 'REPLACE')
    modifier = obj.modifiers.new(name='AsunaArmature', type='ARMATURE')
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    if not obj.parent:
        obj.parent = root_object
    if sum(len(items) for items in values.values()) == 0:
        raise RuntimeError('mesh received no skin weights: ' + obj.name)
    for vertex in obj.data.vertices:
        total = sum(item.weight for item in vertex.groups)
        if not math.isfinite(total) or abs(total - 1.0) > 0.002:
            raise RuntimeError(f'invalid skin weight sum on {obj.name} vertex {vertex.index}: {total}')
    return {name: len(assignments) for name, assignments in values.items()}


weight_counts = {obj.name: assign_weights(obj) for obj in mesh_objects}


def key_rotation(bone_name, frame, angles):
    pose_bone = rig.pose.bones.get(bone_name)
    if pose_bone is None:
        raise RuntimeError('Rigify control is missing: ' + bone_name)
    pose_bone.rotation_mode = 'XYZ'
    pose_bone.rotation_euler = angles
    pose_bone.keyframe_insert(data_path='rotation_euler', frame=frame, group=bone_name)


def make_action(name, frames):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    for frame, pose in frames:
        for bone_name, angles in pose.items():
            key_rotation(bone_name, frame, angles)
    return action


idle_pose = {
    'thigh_fk.L': (0.0, 0.0, 0.0),
    'thigh_fk.R': (0.0, 0.0, 0.0),
    'shin_fk.L': (0.0, 0.0, 0.0),
    'shin_fk.R': (0.0, 0.0, 0.0),
    'foot_fk.L': (0.0, 0.0, 0.0),
    'foot_fk.R': (0.0, 0.0, 0.0),
    'upper_arm_fk.L': (0.0, 0.0, 0.0),
    'upper_arm_fk.R': (0.0, 0.0, 0.0),
    'forearm_fk.L': (0.0, 0.0, 0.0),
    'forearm_fk.R': (0.0, 0.0, 0.0),
    'chest': (0.015, 0.0, 0.0),
    'torso': (-0.006, 0.0, 0.0),
}
idle_rest_pose = {name: (0.0, 0.0, 0.0) for name in idle_pose}
idle_action = make_action('Asuna_Idle', [(1, idle_rest_pose), (25, idle_pose), (49, idle_rest_pose)])

walk_frames = []
for frame, phase in ((1, 0.0), (7, 1.0), (13, 2.0), (19, 3.0), (25, 4.0)):
    swing = math.sin(phase * math.pi / 2) * 0.38
    bend_left = max(0.0, swing) * 0.45
    bend_right = max(0.0, -swing) * 0.45
    pose = {
        'thigh_fk.L': (swing, 0.0, 0.0),
        'thigh_fk.R': (-swing, 0.0, 0.0),
        'shin_fk.L': (bend_left, 0.0, 0.0),
        'shin_fk.R': (-bend_right, 0.0, 0.0),
        'foot_fk.L': (-bend_left * 0.5, 0.0, 0.0),
        'foot_fk.R': (bend_right * 0.5, 0.0, 0.0),
        'upper_arm_fk.L': (-swing * 0.23, 0.0, 0.0),
        'upper_arm_fk.R': (swing * 0.23, 0.0, 0.0),
        'forearm_fk.L': (0.035, 0.0, 0.0),
        'forearm_fk.R': (0.035, 0.0, 0.0),
        'torso': (0.018, 0.0, 0.0),
    }
    walk_frames.append((frame, pose))
walk_action = make_action('Asuna_Walk_InPlace', walk_frames)

scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 768
scene.render.resolution_y = 960
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'Standard'
if scene.world is None:
    scene.world = bpy.data.worlds.new('World')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.12, 0.15, 0.18, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.65

ground_material = bpy.data.materials.get('AsunaRigReviewGround') or bpy.data.materials.new('AsunaRigReviewGround')
ground_material.use_nodes = True
ground_material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.18, 0.21, 0.22, 1)
ground_material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.92
ground = bpy.data.objects.get('AsunaRigReviewGround')
if ground is None:
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.008))
    ground = bpy.context.object
    ground.name = 'AsunaRigReviewGround'
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


for name, location, energy, size, color in (
    ('AsunaRigKey', (3.2, 3.6, 4.8), 180, 3.6, (1.0, 0.86, 0.72)),
    ('AsunaRigFill', (-3.4, 2.2, 2.8), 120, 4.2, (0.72, 0.83, 1.0)),
    ('AsunaRigRim', (0.2, -3.4, 3.7), 220, 3.0, (1.0, 0.88, 0.70)),
):
    add_area_light(name, location, energy, size, color)

camera_data = bpy.data.cameras.get('AsunaRigReviewCamera') or bpy.data.cameras.new('AsunaRigReviewCamera')
camera = bpy.data.objects.get('AsunaRigReviewCamera')
if camera is None:
    camera = bpy.data.objects.new('AsunaRigReviewCamera', camera_data)
    scene.collection.objects.link(camera)
scene.camera = camera


def render_view(name, position, target, lens, frame, action):
    rig.animation_data.action = action
    scene.frame_set(frame)
    camera.location = position
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data.lens = lens
    scene.render.filepath = str(review_directory / (name + '.png'))
    bpy.ops.render.render(write_still=True)


render_view('front', (0, 3.3, 1.05), (0, 0, 0.88), 55, 1, idle_action)
render_view('three_quarter', (1.35, 3.2, 1.08), (0, 0, 0.88), 55, 1, idle_action)
render_view('walk_midstep', (0, 3.3, 1.05), (0, 0, 0.88), 55, 7, walk_action)
render_view('walk_opposite_step', (0, 3.3, 1.05), (0, 0, 0.88), 55, 19, walk_action)

rig.animation_data.action = idle_action
scene.frame_set(1)
scene.frame_end = 49
blend_path = review_directory / 'asuna_rigged.blend'
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

mesh_statistics = []
for obj in mesh_objects:
    mesh_statistics.append({
        'name': obj.name,
        'vertices': len(obj.data.vertices),
        'triangles': sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons),
        'weightedVertices': len(obj.data.vertices),
        'armatureModifier': any(modifier.type == 'ARMATURE' and modifier.object == rig for modifier in obj.modifiers),
        'deformationGroups': len(weight_counts[obj.name]),
    })
report = {
    'source': str(source_blend),
    'blend': str(blend_path),
    'rig': rig.name,
    'rigifyMetarig': metarig.name,
    'rigBones': len(rig.data.bones),
    'deformBones': len(deform_names),
    'actions': [
        {'name': idle_action.name, 'frames': [1, 49], 'fps': scene.render.fps, 'inPlace': True},
        {'name': walk_action.name, 'frames': [1, 25], 'fps': scene.render.fps, 'inPlace': True},
    ],
    'meshes': mesh_statistics,
    'renders': ['front.png', 'three_quarter.png', 'walk_midstep.png', 'walk_opposite_step.png'],
    'runtimeSkeletalRenderer': False,
    'sourceModelWasRigged': False,
    'notes': 'Rigify human metarig fitted to the prepared 1.70 m relaxed-arm pose. Existing split mesh parts receive distance-weighted deformation groups. Hair and skirt have no independent secondary motion; the current proof focuses on body locomotion and should be reviewed before runtime integration.'
}
(review_directory / 'rig_report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

markdown = [
    '# Asuna Rigify Review',
    '',
    'The supplied model had no skeleton or source animations. This local Blender proof uses a generated Rigify human rig fitted to the prepared 1.70 m pose.',
    '',
    f'- Rig: {rig.name}, {len(rig.data.bones)} generated bones including controls and {len(deform_names)} deformation bones.',
    f'- Meshes: {len(mesh_statistics)} parts, {sum(item["vertices"] for item in mesh_statistics)} vertices, {sum(item["triangles"] for item in mesh_statistics)} triangles.',
    f'- Actions: `{idle_action.name}` (49 frames) and `{walk_action.name}` (25 frames), both in place at {scene.render.fps} fps.',
    '- Skinning uses focused spatial weights over the existing disconnected mesh parts. The skirt and long hair have no independent secondary motion; the current proof focuses on body locomotion and should be reviewed before runtime use.',
    '- This proof does not add a Nervegear skeletal renderer or change the prepared static OBJ/Blend files.',
    '',
    '## Previews',
    '',
    '![Front](front.png)',
    '',
    '![Three quarter](three_quarter.png)',
    '',
    '![Walk midstep](walk_midstep.png)',
    '',
    '![Walk opposite step](walk_opposite_step.png)',
]
(review_directory / 'review.md').write_text('\n'.join(markdown) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2))
