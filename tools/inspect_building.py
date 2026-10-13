import bpy, math, json
from mathutils import Vector
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(root/'assets/source/futuristic_building/scene.gltf'))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.name.startswith('Plane')]
pts=[o.matrix_world@Vector(p) for o in objects for p in o.bound_box]
lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
print('BUILDING_BOUNDS',list(lo),list(hi),'TRIANGLES',sum(len(o.data.polygons) for o in objects))
center=(lo+hi)/2;size=max(hi-lo)
for o in bpy.context.scene.objects:
 if o.type=='MESH' and o not in objects:o.hide_render=True
world=bpy.data.worlds.new('Studio');bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(0.11,0.15,0.20,1);world.node_tree.nodes['Background'].inputs[1].default_value=0.8
for offset,power,scale in [((1,-1,1.5),2000,1.2),((-1,-0.4,0.7),1500,1),((0,1,1),2300,1)]:
 bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*size)
 light=bpy.context.object;light.data.energy=power*size*size/20;light.data.shape='DISK';light.data.size=size*scale;light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=center+Vector((1.3,-1.8,0.85))*size)
cam=bpy.context.object;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=size*1.22;bpy.context.scene.camera=cam
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16;scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.filepath=str(root/'docs/previews/building-reference.png');bpy.ops.render.render(write_still=True)
