"""Run with Blender --background --python tools/build_civilian.py.
Appearance preparation only; original human and motion downloads remain untouched.
"""
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector
import math
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'godot/models/civilian'
WORK = ROOT/'assets/working/civilian'
PREVIEW = ROOT/'docs/previews/stage3a'
for path in (OUT,WORK,PREVIEW): path.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/source/human.glb'))
body = next(o for o in bpy.context.scene.objects if o.type=='MESH')
points = [body.matrix_world@v.co for v in body.data.vertices]
lo=Vector(tuple(min(v[i] for v in points) for i in range(3)))
hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
origin=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
for v in body.data.vertices: v.co=(body.matrix_world@v.co-origin)*(1.78/(hi.z-lo.z))
body.parent=None;body.matrix_world.identity();body.name='Civilian_Skin'
source_vertices=[v.co.copy() for v in body.data.vertices]
character=[body]

def material(name,color,roughness=.65,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=roughness;p.inputs['Metallic'].default_value=metal
 if not metal:p.inputs['Specular IOR Level'].default_value=.25
 return m
skin=material('Skin_WarmNatural',(.46,.245,.15),.62)
jacket=material('Jacket_MidnightNavy',(.018,.039,.070),.72)
panel=material('Jacket_SlatePanels',(.042,.071,.100),.78)
trim=material('Trim_Charcoal',(.012,.018,.025),.72)
pants=material('Trousers_Graphite',(.032,.039,.048),.82)
shoe=material('Shoes_MatteTechnical',(.018,.024,.033),.66)
sole=material('Soles_Rubber',(.008,.011,.014),.94)
teal=material('Details_MutedTeal',(.025,.23,.25),.5,.2)
zipmat=material('Zips_BrushedSteel',(.20,.29,.34),.46,.65)
hair=material('Hair_DarkBrown',(.006,.004,.003),.85)
white=material('Eyes_SoftIvory',(.42,.40,.34),.43)
iris=material('Eyes_Brown',(.035,.021,.012),.45)
body.data.materials.clear();body.data.materials.append(skin)
for p in body.data.polygons:p.use_smooth=True

def shell(name,predicate,offset,mat,smoothing=4,clips=None):
 vertices=[v.co.copy() for v in body.data.vertices]
 faces=[list(p.vertices) for p in body.data.polygons if predicate(sum((vertices[i] for i in p.vertices),Vector())/len(p.vertices))]
 used=sorted({i for f in faces for i in f});mapping={v:i for i,v in enumerate(used)}
 mesh=bpy.data.meshes.new(name);mesh.from_pydata([vertices[i] for i in used],[],[[mapping[i] for i in f] for f in faces]);mesh.update()
 obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(mat)
 if clips:
  bm=bmesh.new();bm.from_mesh(mesh)
  for height,lower in [(clips[0],True),(clips[1],False)]:
   bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,height),plane_no=(0,0,1),clear_inner=lower,clear_outer=not lower,dist=.00001)
  bm.to_mesh(mesh);bm.free();mesh.update()
 clipped={v.index:v.co.z for v in mesh.vertices if clips and min(abs(v.co.z-h) for h in clips)<.0001}
 if name=='Cropped_Hair':
  bm=bmesh.new();bm.from_mesh(mesh)
  boundary=[v for v in bm.verts if v.is_boundary]
  for _ in range(4):bmesh.ops.smooth_vert(bm,verts=boundary,factor=.5,use_axis_x=True,use_axis_y=True,use_axis_z=True)
  bm.to_mesh(mesh);bm.free();mesh.update()
 bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 if smoothing:
  mod=obj.modifiers.new('ClothRelax','SMOOTH');mod.factor=.6;mod.iterations=smoothing;bpy.ops.object.modifier_apply(modifier=mod.name)
 obj.data.update()
 normals=[v.normal.copy() for v in obj.data.vertices]
 for v,n in zip(obj.data.vertices,normals):
  v.co+=n*offset
  if v.index in clipped:v.co.z=clipped[v.index]
 for f in obj.data.polygons:f.use_smooth=True
 obj.select_set(False);character.append(obj);return obj

coat=shell('Technical_Jacket',lambda p: .84<p.z<1.57,.022,jacket,6,(.89,1.535))
coat.data.materials.append(panel);coat.data.materials.append(trim)
for v in coat.data.vertices:
 if v.co.z>1.475:
  relative=Vector((v.co.x/.077,(v.co.y-.006)/.066))
  if relative.length>1:
   relative.normalize();v.co.x=relative.x*.077;v.co.y=relative.y*.066+.006
# Separate bands have exact cut edges; no jagged per-triangle color boundaries.
shell('Jacket_Hem',lambda p:.84<p.z<.98 and abs(p.x)<.25,.034,trim,6,(.89,.935))
for side in (-1,1):
 shell('Sleeve_Cuff_'+str(side),lambda p:.84<p.z<1.01 and p.x*side>.27,.034,trim,6,(.89,.96))
trouser=shell('Tailored_Trousers',lambda p: .10<p.z<.96 and abs(p.x)<.255,.018,pants,8,(.135,.915))
# Relax the anatomical base into cloth rather than reproducing anatomy through fabric.
for v in trouser.data.vertices:
 if .82<v.co.z<1.0 and v.co.y>.095:v.co.y=.095
boots=shell('Technical_Shoes',lambda p:.03<p.z<.23,.014,shoe,3,(.055,.19))
haircap=shell('Cropped_Hair',lambda p:p.z>1.72 or (p.z>1.655 and p.y<-.005) or (p.z>1.69 and abs(p.x)>.069),.004,hair,1)

# Remove covered skin from runtime mesh, preserving the full original in assets/source.
bm=bmesh.new();bm.from_mesh(body.data)
remove=[f for f in bm.faces if not (f.calc_center_median().z>1.505 or (abs(f.calc_center_median().x)>.275 and f.calc_center_median().z<.905))]
bmesh.ops.delete(bm,geom=remove,context='FACES');bm.to_mesh(body.data);bm.free();body.data.update()
for v in body.data.vertices:
 if v.co.z<1.535 and abs(v.co.x)<.25 and v.co.z>1.4:
  relative=Vector((v.co.x/.061,(v.co.y-.006)/.056))
  if relative.length>1:
   relative.normalize();v.co.x=relative.x*.061;v.co.y=relative.y*.056+.006
body.data.update()

def mesh_obj(name,verts,faces,mat):
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update();obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(mat);character.append(obj);return obj

def collar():
 n=48;verts=[]
 for z,rx,ry in [(1.475,.095,.094),(1.535,.084,.085)]:
  for i in range(n):
   a=2*math.pi*i/n;verts.append((math.cos(a)*rx,math.sin(a)*ry+.006,z))
 obj=mesh_obj('Soft_Stand_Collar',verts,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],panel)
 for f in obj.data.polygons:f.use_smooth=True
collar()
# Ground-contact soles follow each source foot's footprint rather than a generic box.
def convex_hull(points):
 points=sorted(set(points))
 def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
 lower=[]
 for p in points:
  while len(lower)>=2 and cross(lower[-2],lower[-1],p)<=0:lower.pop()
  lower.append(p)
 upper=[]
 for p in reversed(points):
  while len(upper)>=2 and cross(upper[-2],upper[-1],p)<=0:upper.pop()
  upper.append(p)
 return lower[:-1]+upper[:-1]
for side in (-1,1):
 pts=[v for v in source_vertices if v.x*side>0 and v.z<.08]
 hull=convex_hull([(round(v.x,4),round(v.y,4)) for v in pts]);center=sum((Vector(p) for p in hull),Vector((0,0)))/len(hull)
 hull=[center+(Vector(p)-center)*1.045 for p in hull];n=len(hull)
 verts=[(v.x,v.y,z) for z in (-.012,.025) for v in hull]
 faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 obj=mesh_obj('Rubber_Sole_'+str(side),verts,faces,sole)
 bevel=obj.modifiers.new('SoftSoleEdge','BEVEL');bevel.width=.006;bevel.segments=2
 bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=bevel.name)
 # Continuous rounded shoe upper covers the source toes completely.
 verts=[]
 for scale,z in [(1.01,.025),(1.02,.065),(.91,.10),(.60,.13)]:
  for v in hull:
   point=center+(v-center)*scale;verts.append((point.x,point.y,z))
 faces=[(level*n+i,level*n+(i+1)%n,(level+1)*n+(i+1)%n,(level+1)*n+i) for level in range(3) for i in range(n)]
 faces.append(tuple(range(3*n,4*n)))
 upper=mesh_obj('Shoe_Upper_'+str(side),verts,faces,shoe)
 for f in upper.data.polygons:f.use_smooth=True
 bevel=upper.modifiers.new('RoundedUpper','BEVEL');bevel.width=.006;bevel.segments=2
 bpy.context.view_layer.objects.active=upper;bpy.ops.object.modifier_apply(modifier=bevel.name)

def front_surface(x,z,obj=coat):
 hit,co,normal,face=obj.ray_cast(Vector((x,1,z)),Vector((0,-1,0)))
 return Vector((x,co.y+.003,z)) if hit else Vector((x,.12,z))

def seam(name,points,mat,radius=.0018):
 curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=radius;curve.bevel_resolution=2;curve.resolution_u=1
 spline=curve.splines.new('POLY');spline.points.add(len(points)-1)
 for p,v in zip(spline.points,points):p.co=(*v,1)
 obj=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(obj);obj.data.materials.append(mat);character.append(obj);return obj
seam('Front_Zipper',[front_surface(0,.94+i*.025) for i in range(21)],zipmat,.002)
for side in (-1,1):
 seam('Torso_Seam_'+str(side),[front_surface(side*(.10+.02*math.sin(i/14*math.pi)),.96+i*.027) for i in range(15)],jacket,.001)
 seam('Pocket_Zip_'+str(side),[front_surface(side*(.09+i*.007),1.035+i*.004) for i in range(8)],zipmat,.002)
 # Small non-emissive identity accent; intentionally no armor or glowing body strips.
 seam('Collar_Accent_'+str(side),[(side*.077,.026,1.51),(side*.07,.053,1.51)],teal,.002)

# Chest identity tab follows the front surface; a muted civic detail, not a police badge.
def badge():
 p=front_surface(-.095,1.355)
 bpy.ops.mesh.primitive_cube_add(size=1,location=p+Vector((0,.002,0)));obj=bpy.context.object;obj.name='Civic_ID_Tab';obj.dimensions=(.035,.006,.018);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);obj.data.materials.append(teal);character.append(obj)
 bevel=obj.modifiers.new('RoundedTab','BEVEL');bevel.width=.002;bevel.segments=2;bpy.ops.object.modifier_apply(modifier=bevel.name)
badge()

# Surface-conforming eye patches follow the sculpted sockets without floating spheres.
bpy.context.view_layer.update()
for side in (-1,1):
 cx=-.025 if side<0 else .052;cz=1.667
 def eye_patch(name,rx,rz,mat,depth):
  verts=[]
  for x,z in [(cx,cz)]+[(cx+rx*math.cos(i*2*math.pi/24),cz+rz*math.sin(i*2*math.pi/24)) for i in range(24)]:
   hit,point,normal,face=body.ray_cast(Vector((x,1,z)),Vector((0,-1,0)))
   verts.append((x,point.y+depth,z))
  return mesh_obj(name,verts,[(0,(i+1)%24+1,i+1) for i in range(24)],mat)
 eye_patch('Eye_'+str(side),.011,.0035,white,.0015)
 eye_patch('Iris_'+str(side),.0033,.0033,iris,.0020)

# Convert authored curves, triangulate and normalize ground contact for glTF and later skinning.
for obj in character:
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
 if obj.type=='CURVE':bpy.ops.object.convert(target='MESH')
 if obj.type=='MESH':
  for poly in obj.data.polygons:poly.use_smooth=True
  mod=obj.modifiers.new('ExportTriangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
min_z=min((o.matrix_world@v.co).z for o in character for v in o.data.vertices)
for obj in character:obj.location.z-=min_z
bpy.ops.object.select_all(action='DESELECT')
for obj in character:obj.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
character_root=bpy.data.objects.new('Civilian_Appearance_v1',None);bpy.context.collection.objects.link(character_root)
character_root['source']='Human by aaron.kalvin, CC-BY-4.0';character_root['stage']='3A appearance; unrigged'
for obj in character:obj.parent=character_root
character_root.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'civilian.glb'),export_format='GLB',use_selection=True,export_extras=True,export_yup=True)
triangles=sum(len(o.data.polygons) for o in character)
report={'source':'assets/source/human.glb','height_m':max((o.matrix_world@v.co).z for o in character for v in o.data.vertices),'triangles':triangles,'mesh_objects':len(character),'rigged':False,'animations':0,'materials':[m.name for m in bpy.data.materials if m.users]}
(OUT/'appearance_report.json').write_text(json.dumps(report,indent=2)+'\n')
# Neutral review studio, saved with the editable character and excluded from GLB export.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=48
scene.render.resolution_x=1000;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
world=bpy.data.worlds.new('ReviewStudio');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.035,.055,.085,1);world.node_tree.nodes['Background'].inputs[1].default_value=.4
floor_mat=material('StudioFloor',(.025,.04,.06),.9)
bpy.ops.mesh.primitive_plane_add(size=200);bpy.context.object.name='STUDIO_Floor';bpy.context.object.data.materials.append(floor_mat);bpy.context.object.location.z=-.001
for pos,power,size in [((2,3,4),450,3),((-3,1,2),250,3),((1,-3,3),600,2)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name='STUDIO_Light';o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2,3,1.6));cam=bpy.context.object;cam.name='STUDIO_Camera';scene.camera=cam;cam.data.type='ORTHO'
for name,pos,target,scale in [('front',(0,4,1.2),(0,0,.9),2.1),('three-quarter',(2,3,1.5),(0,0,.92),2.1),('back',(-2,-3,1.4),(0,0,.92),2.1),('detail',(.7,2,1.75),(0,0,1.48),.72)]:
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;scene.render.filepath=str(PREVIEW/(name+'.png'));bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'civilian_appearance.blend'))
print('CIVILIAN_APPEARANCE',json.dumps(report))
