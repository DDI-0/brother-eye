"""Blender regression check of exported GLBs, not the authoring scene.
blender --background --python tools/qa/check_animated_characters.py
"""
from pathlib import Path
import bpy,json,math,struct
import numpy as np
R=Path(__file__).resolve().parents[2]
expected={'idle','walk','run','sit_down','sit_idle','stand_up'}
result={}
for kind in ['civilian','exceptional_agent']:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30
 path=R/'godot/models/animated'/(kind+'.glb');binary=path.read_bytes();length=struct.unpack_from('<I',binary,12)[0];gltf=json.loads(binary[20:20+length]);assert all('skin' in n for n in gltf['nodes'] if 'mesh' in n)
 bpy.ops.import_scene.gltf(filepath=str(path))
 rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh_names={n['name'] for n in gltf['nodes'] if 'mesh' in n};meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name in mesh_names];assert len(meshes)==len(mesh_names)
 assert set(a.name for a in bpy.data.actions)==expected
 assert len(rig.data.bones)>=19
 rig.animation_data.action=None
 for pb in rig.pose.bones:pb.matrix_basis.identity()
 bpy.context.view_layer.update()
 for o in meshes:
  assert any(m.type=='ARMATURE' for m in o.modifiers) or o.parent_type=='BONE',o.name
  for v in o.data.vertices:
   if o.parent_type!='BONE':
    w=sum(g.weight for g in v.groups);assert abs(w-1)<.0001,(o.name,v.index,w)
 rest={o.name:np.array([list(o.matrix_world@v.co) for v in o.data.vertices]) for o in meshes}
 sole={o.name:np.where(v[:,2]<.075)[0] for o in meshes if (o.name.startswith('Rubber_Sole') or kind=='exceptional_agent') for v in [rest[o.name]]}
 report={}
 rest_foot_dir={side:(rig.pose.bones[side+'Foot'].tail-rig.pose.bones[side+'Foot'].head).normalized().copy() for side in ['Left','Right']}
 for action in bpy.data.actions:
  rig.animation_data.action=action;lo,hi=action.frame_range;minimum=1e9;maximum=-1e9;max_edge=1.0
  foot_samples=[]
  for f in np.linspace(lo,hi,49):
   bpy.context.scene.frame_set(int(f),subframe=float(f)%1);bpy.context.view_layer.update();dep=bpy.context.evaluated_depsgraph_get();floor=1e9;side_floor={1:1e9,-1:1e9}
   for o in meshes:
    ev=o.evaluated_get(dep);vs=np.array([list(ev.matrix_world@v.co) for v in ev.data.vertices]);assert np.isfinite(vs).all()
    assert np.abs(vs).max()<4,(kind,action.name,o.name,'exploded bounds')
    if o.name in sole and len(sole[o.name]):
     floor=min(floor,float(vs[sole[o.name],2].min()))
     for sign in [1,-1]:
      ids=sole[o.name][rest[o.name][sole[o.name],0]*sign>0]
      if len(ids):side_floor[sign]=min(side_floor[sign],float(vs[ids,2].min()))
    edges=np.array([list(e.vertices) for e in o.data.edges]);before=np.linalg.norm(rest[o.name][edges[:,0]]-rest[o.name][edges[:,1]],axis=1);after=np.linalg.norm(vs[edges[:,0]]-vs[edges[:,1]],axis=1);valid=before>.005
    if valid.any():max_edge=max(max_edge,float((after[valid]/before[valid]).max()))
   minimum=min(minimum,floor);maximum=max(maximum,floor)
   foot_samples.append({side:np.array(rig.pose.bones[side+'Foot'].head) for side in ['Left','Right']})
   if kind=='civilian' and action.name=='sit_idle':
    hips=rig.pose.bones['Hips'].head
    for side in ['Left','Right']:
     hand=rig.pose.bones[side+'Hand'];direction=(hand.tail-hand.head).normalized()
     assert hand.head.y>hips.y+.20 and abs(hand.head.x)>.12,(side,'hand inside jacket')
     assert .04<hand.head.z-hips.z<.15 and direction.y>.9,(side,'hand not resting over lap')
   if action.name in ['sit_down','sit_idle','stand_up']:
    assert max(abs(z) for z in side_floor.values())<.012,(kind,action.name,'unplanted seated sole',side_floor)
    for side in ['Left','Right']:
     pb=rig.pose.bones[side+'Foot'];direction=(pb.tail-pb.head).normalized()
     assert direction.dot(rest_foot_dir[side])>.9999,(kind,action.name,side,'tilted sole')
  if action.name in ['sit_down','sit_idle','stand_up']:
   for side in ['Left','Right']:
    points=np.array([v[side] for v in foot_samples])
    assert np.ptp(points[:,0])<.004 and np.ptp(points[:,1])<.004,(kind,action.name,side,'sliding planted foot',np.ptp(points,axis=0))
  if action.name=='run':
   for side in ['Left','Right']:
    points=np.array([v[side] for v in foot_samples]);low=points[:,2].min()
    stance=[points[i+1,1]-points[i,1] for i in range(len(points)-1) if max(points[i,2],points[i+1,2])<low+.04]
    assert len(stance)>5 and np.mean(stance)<-.005,(kind,side,'backwards run stance',stance)
  assert minimum>-.025 and maximum<.025,(kind,action.name,'floor',minimum,maximum)
  report[action.name]={'lowest_sole_min_m':minimum,'lowest_sole_max_m':maximum,'max_edge_stretch_ratio':max_edge,'samples':49,'seated_plant_and_level_checked':action.name in ['sit_down','sit_idle','stand_up'],'forward_stance_checked':action.name=='run'}
 result[kind]=report
out=R/'godot/models/animated/export_qa.json';out.write_text(json.dumps(result,indent=2)+'\n')
print('EXPORTED_RIG_QA_PASS',json.dumps(result))
