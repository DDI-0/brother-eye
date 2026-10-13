"""Stage 3B: shared biped rigs, source motion transfer and authored idle/run.
Run with Blender --background --python tools/build_animated_characters.py.
Original downloads and the Stage 3A appearance are never modified.
"""
from pathlib import Path
import bpy, json, math, zipfile
from mathutils import Vector, Quaternion, Matrix
R=Path(__file__).resolve().parents[1]
FPS=30
S=Matrix.Diagonal(Vector((-1,-1,1,1))) # imported motion and astronaut face -Y
V=Vector
OUT=R/'godot/models/animated';OUT.mkdir(parents=True,exist_ok=True)
WORK=R/'assets/working/animated';WORK.mkdir(parents=True,exist_ok=True)
for name in ['space_engineers_astronaut','walk_cycle_animation','standing__sitting_animation']:
 destination=R/'assets/working/motion_sources'/name
 if not (destination/'scene.gltf').exists():
  destination.mkdir(parents=True,exist_ok=True)
  with zipfile.ZipFile(R/'assets/source'/(name+'.zip')) as archive:
   for member in archive.namelist():
    assert destination.resolve() in (destination/member).resolve().parents
   archive.extractall(destination)
bpy.ops.wm.read_factory_settings(use_empty=True)

# Sample evaluated joint directions rather than copying incompatible local Euler tracks.
def motion_source(name):
 before=set(bpy.data.objects)
 bpy.ops.import_scene.gltf(filepath=str(R/'assets/working/motion_sources'/name/'scene.gltf'))
 objects=set(bpy.data.objects)-before
 arm=next(o for o in objects if o.type=='ARMATURE')
 action=max(bpy.data.actions,key=lambda a:a.frame_range[1]-a.frame_range[0]) if name=='standing__sitting_animation' else arm.animation_data.action
 arm.animation_data.action=action
 keys=['Hips','Spine','Spine1','Spine2','Neck','Head']+[side+part for side in ['Left','Right'] for part in ['Arm','ForeArm','Hand','UpLeg','Leg','Foot','ToeBase']]
 names={key:next(b.name for b in arm.data.bones if b.name.split(':')[-1].rsplit('_',1)[0]==key) for key in keys}
 rest={k:(S.to_3x3()@(arm.matrix_world.to_3x3()@(arm.data.bones[n].tail_local-arm.data.bones[n].head_local))).normalized() for k,n in names.items()}
 hi=float(action.frame_range[1]);frames=[]
 for i in range(round(hi)+1):
  bpy.context.scene.frame_set(i);bpy.context.view_layer.update()
  frames.append({k:{'head':S@(arm.matrix_world@arm.pose.bones[n].head),'dir':(S.to_3x3()@(arm.matrix_world.to_3x3()@(arm.pose.bones[n].tail-arm.pose.bones[n].head))).normalized()} for k,n in names.items()})
 for o in objects:bpy.data.objects.remove(o,do_unlink=True)
 return {'frames':frames,'rest':rest,'end':hi,'seconds':hi/24}
walk=motion_source('walk_cycle_animation')
sitting=motion_source('standing__sitting_animation')
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
# Continuous sampling of positions and unit directions.
def sample(src,phase):
 f=max(0,min(src['end'],phase*src['end']));i=int(f);j=min(i+1,len(src['frames'])-1);t=f-i
 return {k:{'head':src['frames'][i][k]['head'].lerp(src['frames'][j][k]['head'],t),'dir':src['frames'][i][k]['dir'].lerp(src['frames'][j][k]['dir'],t).normalized()} for k in src['rest']}

def clamp(v):return max(0,min(1,v))
def smooth(v):v=clamp(v);return v*v*(3-2*v)
def blend_weights(z,stops):
 if z<=stops[0][0]:return {stops[0][1]:1}
 for (a,n),(b,m) in zip(stops,stops[1:]):
  if a<=z<=b:
   t=smooth((z-a)/(b-a));return {n:1-t,m:t}
 return {stops[-1][1]:1}

reports={}
for kind in ['civilian','exceptional_agent']:
 bpy.data.orphans_purge(do_recursive=True)
 before=set(bpy.data.objects)
 path=R/'godot/models/civilian/civilian.glb' if kind=='civilian' else R/'assets/working/motion_sources/space_engineers_astronaut/scene.gltf'
 bpy.ops.import_scene.gltf(filepath=str(path))
 imported=set(bpy.data.objects)-before;meshes=[o for o in imported if o.type=='MESH']
 for o in meshes:
  mat=o.matrix_world.copy()
  for v in o.data.vertices:v.co=mat@v.co
  o.parent=None;o.matrix_world.identity()
 if kind=='exceptional_agent':
  points=[v.co for o in meshes for v in o.data.vertices];lo=min(v.z for v in points);hi=max(v.z for v in points);scale=1.95/(hi-lo)
  for o in meshes:
   for v in o.data.vertices:v.co=V((-v.co.x*scale,-v.co.y*scale,(v.co.z-lo)*scale))
  # Keep the supplied armor, backpack and helmet geometry; give the untextured source a city finish.
  palette=[('Suit_Graphite',(.045,.065,.08),.7,.15),('Visor_SmokedTeal',(.014,.055,.065),.25,.65),('Pack_Charcoal',(.025,.035,.045),.8,.15),('Helmet_Slate',(.12,.17,.21),.48,.4),('Helmet_Detail',(.035,.26,.29),.4,.3)]
  # Imported mesh order is not reliable: identify source components by original primitive vertex count.
  mapping={6463:0,46:1,2439:2,973:3,96:4}
  for o in meshes:
   idx=mapping[len(o.data.vertices)];name,col,rough,metal=palette[idx];o.name=name
   m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
   o.data.materials.clear();o.data.materials.append(m)
 for o in imported:
  if o not in meshes:bpy.data.objects.remove(o,do_unlink=True)
 # Measured joint landmarks for the two supplied rest poses, in meters, Blender +Y forward.
 agent=kind=='exceptional_agent'
 hip=1.04 if agent else .96;shoulder=1.51 if agent else 1.435
 elbow=1.23 if agent else 1.19;wrist=.99 if agent else .95
 sx=.225 if agent else .165;ex=.32 if agent else .29;wx=.385
 knee=.57 if agent else .53;ankle=.16 if agent else .135;legx=.115 if agent else .105
 pts={'Hips':((0,0,hip),(0,0,hip+.12),None),
 'Spine':((0,0,hip+.12),(0,0,1.33 if agent else 1.29),'Hips'),
 'Chest':((0,0,1.33 if agent else 1.29),(0,0,shoulder+.06),'Spine'),
 'Neck':((0,0,shoulder+.06),(0,0,1.65 if agent else 1.59),'Chest'),
 'Head':((0,0,1.65 if agent else 1.59),(0,0,1.90 if agent else 1.77),'Neck')}
 for side,sign in [('Left',1),('Right',-1)]:
  pts[side+'Arm']=((sign*sx,0,shoulder),(sign*ex,.012,elbow),'Chest')
  pts[side+'ForeArm']=((sign*ex,.012,elbow),(sign*wx,.015,wrist),side+'Arm')
  pts[side+'Hand']=((sign*wx,.015,wrist),(sign*(wx+.015),.015,wrist-.10),side+'ForeArm')
  pts[side+'UpLeg']=((sign*legx,0,hip-.025),(sign*legx,.025,knee),'Hips')
  pts[side+'Leg']=((sign*legx,.025,knee),(sign*legx,0,ankle),side+'UpLeg')
  pts[side+'Foot']=((sign*legx,0,ankle),(sign*legx,.16,.045),side+'Leg')
  pts[side+'Toe']=((sign*legx,.16,.045),(sign*legx,.235,.035),side+'Foot')
 if agent:
  pts['LeftUpLeg']=((.13,0,1.015),(.145,.13,.53),'Hips')
  pts['LeftLeg']=((.145,.13,.53),(.15,.015,.14),'LeftUpLeg')
  pts['LeftFoot']=((.15,.015,.14),(.15,.175,.045),'LeftLeg')
  pts['LeftToe']=((.15,.175,.045),(.15,.25,.035),'LeftFoot')
  pts['RightUpLeg']=((-.13,0,1.015),(-.135,.07,.515),'Hips')
  pts['RightLeg']=((-.135,.07,.515),(-.14,-.13,.14),'RightUpLeg')
  pts['RightFoot']=((-.14,-.13,.14),(-.14,.03,.045),'RightLeg')
  pts['RightToe']=((-.14,.03,.045),(-.14,.105,.035),'RightFoot')
  # The supplied astronaut's left hand is raised in its static pose.
  pts['RightArm']=((-.225,-.025,1.51),(-.32,.02,1.23),'Chest')
  pts['RightForeArm']=((-.32,.02,1.23),(-.33,.055,.97),'RightArm')
  pts['RightHand']=((-.33,.055,.97),(-.33,.065,.79),'RightForeArm')
  pts['LeftArm']=((.225,.025,1.51),(.315,.155,1.40),'Chest')
  pts['LeftForeArm']=((.315,.155,1.40),(.32,.345,1.665),'LeftArm')
  pts['LeftHand']=((.32,.345,1.665),(.32,.37,1.80),'LeftForeArm')
 else:
  for side,sign in [('Left',1),('Right',-1)]:
   pts[side+'Arm']=((sign*.175,-.065*sign,1.435),(sign*.275,-.112*sign,1.19),'Chest')
   pts[side+'ForeArm']=((sign*.275,-.112*sign,1.19),(sign*.36,-.08*sign,.94),side+'Arm')
   pts[side+'Hand']=((sign*.36,-.08*sign,.94),(sign*.38,-.04*sign,.82),side+'ForeArm')
 data=bpy.data.armatures.new(kind+'_Biped');rig=bpy.data.objects.new(kind+'_Rig',data);bpy.context.collection.objects.link(rig)
 bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 for n,(a,b,parent) in pts.items():
  bone=data.edit_bones.new(n);bone.head=a;bone.tail=b
  if parent:bone.parent=data.edit_bones[parent]
 bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
 rig['stage']='3B: rig and animation proof, no autonomous behavior'
 rig['forward']='+Y Blender / -Z Godot';rig['walk_speed_mps']=.72;rig['run_speed_mps']=2.4
 # Skinning follows measured anatomical regions, with smooth joint influence ramps.
 for o in meshes:
  armor_bind={}
  glove_vertices=set()
  if agent and o.name=='Suit_Graphite':
   parents=list(range(len(o.data.vertices)))
   def root(i):
    while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
    return i
   def join(a,b):parents[root(a)]=root(b)
   positions={}
   for v in o.data.vertices:
    key=tuple(round(c,5) for c in v.co)
    if key in positions:join(v.index,positions[key])
    else:positions[key]=v.index
   for e in o.data.edges:join(*e.vertices)
   components={}
   for v in o.data.vertices:components.setdefault(root(v.index),[]).append(v)
   largest=max(components,key=lambda k:len(components[k]))
   for key,verts in components.items():
    if key==largest:continue # connected flexible under-suit
    center=sum((v.co for v in verts),V())/len(verts);scores={}
    for n,(a,b,_) in pts.items():
     a=V(a);d=V(b)-a;t=clamp((center-a).dot(d)/d.length_squared)
     radius=.21 if n in ['Hips','Spine','Chest'] else .09
     scores[n]=(center-(a+d*t)).length/radius
    bone=min(scores,key=scores.get)
    if len(verts)==633:
     glove_vertices.update(v.index for v in verts)
     continue # Long glove cuffs span the wrist: skin them across both joints.
    if len(verts)==409:bone='Chest'
    for v in verts:armor_bind[v.index]=bone
  for n in pts:o.vertex_groups.new(name=n)
  for v in o.data.vertices:
   x,y,z=v.co;ax=abs(x);side='Left' if x>=0 else 'Right';name=o.name
   if agent and name.startswith(('Visor','Helmet')):weights={'Head':1}
   elif agent and name.startswith('Pack'):weights={'Chest':1}
   elif v.index in glove_vertices:
    wrist_pos=V(pts[side+'Hand'][0]);axis=(V(pts[side+'ForeArm'][1])-V(pts[side+'ForeArm'][0])).normalized()
    hand_mix=smooth(((v.co-wrist_pos).dot(axis)+.025)/.075)
    weights={side+'ForeArm':1-hand_mix,side+'Hand':hand_mix}
   elif v.index in armor_bind:weights={armor_bind[v.index]:1}
   elif not agent and name.startswith('Sleeve_Cuff'):weights={side+'ForeArm':1}
   elif name.startswith(('Eye_','Iris_','Cropped_Hair')):weights={'Head':1}
   elif name.startswith(('Rubber_Sole','Shoe_Upper','Technical_Shoes')):weights={side+'Foot':1}
   elif not agent and name=='Civilian_Skin' and z<1.3:weights={side+'Hand':1}
   elif not agent and name.startswith('Tailored_Trousers'):
    weights={}
    left=smooth((x+.04)/.08) if z>.65 else (1 if x>=0 else 0)
    for leg,factor in [('Left',left),('Right',1-left)]:
     ramp=blend_weights(z,[(ankle+.025,leg+'Foot'),(ankle+.10,leg+'Leg'),(knee-.10,leg+'Leg'),(knee+.10,leg+'UpLeg'),(hip-.15,leg+'UpLeg'),(hip-.015,'Hips')])
     for n,w in ramp.items():weights[n]=weights.get(n,0)+w*factor
   else:
    # Capsule distances account for torso volume rather than a hard X/Z cut.
    # This keeps adjacent waist/finger vertices from being assigned to different limbs.
    radii={'Hips':.21,'Spine':.18,'Chest':.205 if not agent else .225,'Neck':.055,'Head':.10}
    for s in ['Left','Right']:
     for part,radius in [('Arm',.075 if not agent else .10),('ForeArm',.065 if not agent else .09),('Hand',.07),('UpLeg',.095 if not agent else .12),('Leg',.075 if not agent else .105),('Foot',.095),('Toe',.07)]:radii[s+part]=radius
    candidates=list(pts)
    if name.startswith(('Technical_Jacket','Jacket_Hem','Front_Zipper','Torso_Seam','Pocket_Zip','Sleeve_Cuff','Soft_Stand_Collar','Collar_Accent','Civic_ID')):
     candidates=[n for n in candidates if not n.endswith(('UpLeg','Leg','Foot','Toe'))]
    elif name.startswith('Tailored_Trousers'):candidates=[n for n in candidates if n=='Hips' or n.endswith(('UpLeg','Leg','Foot'))]
    if name.startswith('Sleeve_Cuff'):candidates=[side+'Arm',side+'ForeArm',side+'Hand']
    raw={}
    for n in candidates:
     a=V(pts[n][0]);b=V(pts[n][1]);d=b-a;t=clamp((v.co-a).dot(d)/d.length_squared)
     distance=(v.co-(a+d*t)).length/radii[n]
     raw[n]=1/(.15+distance)**6
    if name=='Technical_Jacket':
     arm_mix=smooth((ax-(.23-.25*(z-1.0)))/.05)
     for n in raw:
      raw[n]*=arm_mix if n.endswith(('Arm','ForeArm','Hand')) else 1-arm_mix
    strongest=sorted(raw,key=raw.get,reverse=True)[:4];total=sum(raw[n] for n in strongest)
    weights={n:raw[n]/total for n in strongest}
   for n,w in weights.items():
    if w>.00001:o.vertex_groups[n].add([v.index],w,'REPLACE')
  mod=o.modifiers.new('BipedSkin','ARMATURE');mod.object=rig;o.parent=rig
  for p in o.data.polygons:p.use_smooth=True
 restQ={b.name:b.matrix_local.to_quaternion() for b in data.bones}
 restD={b.name:(b.tail_local-b.head_local).normalized() for b in data.bones}
 # Keys are baked as standard glTF skeletal animation; no runtime procedural deformation.
 for pb in rig.pose.bones:pb.rotation_mode='QUATERNION'
 source_map={'Hips':'Hips','Spine':'Spine','Chest':'Spine2','Neck':'Neck','Head':'Head'}
 for side in ['Left','Right']:
  for part in ['Arm','ForeArm','Hand','UpLeg','Leg','Foot','Toe']:source_map[side+part]=('Right' if side=='Left' else 'Left')+('ToeBase' if part=='Toe' else part)
 def reset():
  for b in rig.pose.bones:b.location=(0,0,0);b.rotation_quaternion=(1,0,0,0);b.scale=(1,1,1)
 def set_rotations(deltas,root):
  desired={}
  for n,(_,_,parent) in pts.items():
   desired[n]=deltas.get(n,Quaternion())@restQ[n]
   base=restQ[n] if not parent else restQ[parent].inverted()@restQ[n]
   rig.pose.bones[n].rotation_quaternion=base.inverted()@(desired[parent].inverted() if parent else Quaternion())@desired[n]
  rig.pose.bones['Hips'].location=restQ['Hips'].inverted()@(root-V(pts['Hips'][0]))
  bpy.context.view_layer.update()
 def transfer(src,phase,standing=False):
  f=sample(src,phase);d={}
  for n,key in source_map.items():
   if n.endswith(('Foot','Toe')) or n=='Head':d[n]=src['rest'][key].rotation_difference(f[key]['dir'])
   else:d[n]=restD[n].rotation_difference(f[key]['dir'])
  ref=sample(src,.5 if standing else 0)['Hips']['head'];root=V((0,0,hip))
  ratio=hip/ref.z
  root.z+=(f['Hips']['head'].z-ref.z)*ratio
  if standing:
   for n in ['Hips','Spine','Chest']:d[n]=Quaternion().slerp(d[n],.50)
   d['Head']=Quaternion();d['Neck']=Quaternion()
  if standing:root.y=(f['Hips']['head'].y-ref.y)*ratio
  root.x=(f['Hips']['head'].x-ref.x)*ratio*.35
  return d,root
 def authored(name,t):
  phase=2*math.pi*t;d={};root=V((0,0,hip))
  lean=-.11 if name=='run' else .007*math.sin(phase)
  for n in ['Hips','Spine','Chest','Neck','Head']:d[n]=Quaternion((1,0,0),lean)
  if name=='idle':d['Head']=Quaternion((0,0,1),.025*math.sin(phase));root.z+=.002*math.sin(phase)
  else:root.z-=.085;root.z+=.025*math.cos(phase*2)
  for side,sign,offset in [('Left',1,0),('Right',-1,math.pi)]:
   p=phase+offset
   upper=.5*math.cos(p+math.pi)+.10 if name=='run' else .025
   lower=upper+1.15 if name=='run' else .12
   d[side+'Arm']=restD[side+'Arm'].rotation_difference(V((sign*.10,math.sin(upper),-math.cos(upper))).normalized())
   d[side+'ForeArm']=restD[side+'ForeArm'].rotation_difference(V((sign*.025,math.sin(lower),-math.cos(lower))).normalized())
   d[side+'Hand']=restD[side+'Hand'].rotation_difference(V((sign*.025,math.sin(lower),-math.cos(lower))).normalized())
   if name=='run':
    # Two-link solve: level soles during stance; positive knee bend, no backward knees.
    h=V(pts[side+'UpLeg'][0])+root-V((0,0,hip));target=V(pts[side+'Foot'][0]);stride=(p%(2*math.pi))/(2*math.pi)
    # Constant stance velocity matches actual forward travel without skate-like sliding.
    target.y+=(.33-.66*stride*2) if stride<.5 else (-.33+.66*smooth((stride-.5)*2))
    target.z+=.24*max(0,-math.sin(p))
    a=(V(pts[side+'UpLeg'][1])-V(pts[side+'UpLeg'][0])).length;b=(V(pts[side+'Leg'][1])-V(pts[side+'Leg'][0])).length
    delta=target-h;dist=min(delta.length,a+b-.001);axis=delta.normalized();along=(a*a-b*b+dist*dist)/(2*dist);bend=math.sqrt(max(0,a*a-along*along))
    forward=V((0,1,0));pole=(forward-axis*forward.dot(axis)).normalized();k=h+axis*along+pole*bend
    d[side+'UpLeg']=restD[side+'UpLeg'].rotation_difference((k-h).normalized());d[side+'Leg']=restD[side+'Leg'].rotation_difference((target-k).normalized())
    d[side+'Foot']=Quaternion();d[side+'Toe']=Quaternion()
  return d,root
 def planted_sit(d,root,amount):
  # Independent world-space ankle targets keep BOTH soles level and planted.
  # Solve from evaluated hip sockets, including the pelvis rotation.
  root=V((0,-.28*amount,hip+( (.70 if agent else .62)-hip)*amount))
  d['Hips']=Quaternion()
  set_rotations(d,root)
  for side in ['Left','Right']:
   h=rig.pose.bones[side+'UpLeg'].head.copy()
   target=V(pts[side+'Foot'][0]);target.y=.12
   a=(V(pts[side+'UpLeg'][1])-V(pts[side+'UpLeg'][0])).length
   b=(V(pts[side+'Leg'][1])-V(pts[side+'Leg'][0])).length
   delta=target-h;dist=delta.length
   # Slightly bent standing knees avoid an unreachable straight-leg singularity.
   if dist>a+b-.002:
    root.z-=dist-(a+b-.002)
    set_rotations(d,root);h=rig.pose.bones[side+'UpLeg'].head.copy();delta=target-h;dist=delta.length
   axis=delta.normalized();along=(a*a-b*b+dist*dist)/(2*dist)
   pole=V((0,1,0));pole=(pole-axis*pole.dot(axis)).normalized()
   k=h+axis*along+pole*math.sqrt(max(0,a*a-along*along))
   d[side+'UpLeg']=restD[side+'UpLeg'].rotation_difference((k-h).normalized())
   d[side+'Leg']=restD[side+'Leg'].rotation_difference((target-k).normalized())
   d[side+'Foot']=Quaternion();d[side+'Toe']=Quaternion()
  return d,root
 def seated_hands(d,root,amount):
  # The source actor holds a hand at the waist; our jacket needs a lap pose.
  # Solve the arms to wrist targets above the thighs, then orient palms down.
  neutral,_=authored('idle',0)
  set_rotations(d,root)
  for side,sign in [('Left',1),('Right',-1)]:
   shoulder=rig.pose.bones[side+'Arm'].head.copy()
   target=V((sign*.15,.015,root.z+.08))
   a=(V(pts[side+'Arm'][1])-V(pts[side+'Arm'][0])).length
   b=(V(pts[side+'ForeArm'][1])-V(pts[side+'ForeArm'][0])).length
   delta=target-shoulder;dist=min(delta.length,a+b-.001);axis=delta.normalized()
   along=(a*a-b*b+dist*dist)/(2*dist)
   pole=V((sign,-.5,0));pole=(pole-axis*pole.dot(axis)).normalized()
   elbow=shoulder+axis*along+pole*math.sqrt(max(0,a*a-along*along))
   pose={side+'Arm':restD[side+'Arm'].rotation_difference((elbow-shoulder).normalized()),
         side+'ForeArm':restD[side+'ForeArm'].rotation_difference((target-elbow).normalized())}
   def frame(direction,normal):
    y=direction.normalized();z=(normal-y*normal.dot(y)).normalized();x=y.cross(z)
    return Matrix((x,y,z)).transposed().to_quaternion()
   pose[side+'Hand']=frame(V((-sign*.12,1,-.20)),V((0,0,-1)))@frame(restD[side+'Hand'],V((-sign,0,0))).inverted()
   for name,q in pose.items():d[name]=neutral[name].slerp(q,amount)
  return d,root
 foot_objects=[o for o in meshes if o.name.startswith(('Rubber_Sole','Shoe_Upper'))] if not agent else meshes
 foot_indices={o.name:[v.index for v in o.data.vertices if v.co.z<.09] for o in foot_objects}
 def floor_min():
  dep=bpy.context.evaluated_depsgraph_get();values=[]
  for o in foot_objects:
   ev=o.evaluated_get(dep)
   values.extend((ev.matrix_world@ev.data.vertices[i].co).z for i in foot_indices[o.name])
  return min(values)
 clips=[('idle',3.2),('walk',walk['seconds']),('run',.8),('sit_down',sitting['seconds']/2),('sit_idle',3.2),('stand_up',sitting['seconds']/2)]
 stats={}
 for clip,duration in clips:
  reset();action=bpy.data.actions.new(clip);action.use_fake_user=True;rig.animation_data_create();rig.animation_data.action=action
  count=round(duration*FPS);floor_samples=[];footpaths=[]
  for i in range(count+1):
   t=i/count;bpy.context.scene.frame_set(i+1)
   if clip=='walk':d,root=transfer(walk,t)
   elif clip in ['sit_down','stand_up','sit_idle']:
    phase=.5*(1-t) if clip=='sit_down' else (.5*t if clip=='stand_up' else 0)
    d,root=transfer(sitting,phase,True)
    amount=smooth(1-2*phase)
    d,root=planted_sit(d,root,amount)
    if not agent:d,root=seated_hands(d,root,amount)
    if clip=='sit_idle':d['Chest']=Quaternion((1,0,0),.005*math.sin(t*2*math.pi))@d['Chest']
   else:d,root=authored(clip,t)
   set_rotations(d,root)
   minimum=floor_min();root.z-=minimum;set_rotations(d,root)
   floor_samples.append(floor_min())
   footpaths.append({s:list(rig.pose.bones[s+'Foot'].head) for s in ['Left','Right']})
   for pb in rig.pose.bones:
    pb.keyframe_insert('rotation_quaternion',frame=i+1,group=pb.name)
    if pb.name=='Hips':pb.keyframe_insert('location',frame=i+1,group=pb.name)
  # Linear interpolation avoids Bezier overshoot at contacts.
  slot=action.slots[0]
  for layer in action.layers:
   for strip in layer.strips:
    bag=strip.channelbag(slot)
    for fc in bag.fcurves:
     for point in fc.keyframe_points:point.interpolation='LINEAR'
  stats[clip]={'duration_s':count/FPS,'frames':count+1,'min_sole_z_m':min(floor_samples),'max_lowest_sole_z_m':max(floor_samples),'foot_paths':footpaths}
 reset();rig.animation_data.action=None;bpy.context.scene.render.fps=FPS;bpy.context.scene.frame_set(1)
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 for o in meshes:o.select_set(True)
 bpy.context.view_layer.objects.active=rig
 # Export only this rig; action slots prevent other character/source actions being included.
 bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+'.glb')),export_format='GLB',use_selection=True,export_extras=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False,export_anim_slide_to_zero=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(WORK/(kind+'.blend')))
 reports[kind]={'height_m':1.95 if agent else 1.795257449,'bones':len(pts),'meshes':len(meshes),'clips':stats,'walk_source':'jlwande2 / CC-BY-4.0','sit_source':'abysmaljess / CC-BY-4.0','idle_run':'Original authored motion; no run.zip data copied'}
 for o in meshes+[rig]:bpy.data.objects.remove(o,do_unlink=True)
 # Keep only this character's actions out of the next character's export.
 for a in list(bpy.data.actions):bpy.data.actions.remove(a)
(OUT/'rig_report.json').write_text(json.dumps(reports,indent=2)+'\n')
print('ANIMATED_CHARACTERS_COMPLETE',[(k,v['bones'],list(v['clips'])) for k,v in reports.items()])
