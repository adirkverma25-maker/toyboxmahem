class_name GrenadeArc
extends Node3D
## Aiming a thrown gadget: while the gadget key is held, a dotted arc shows where it will fly (same speed and
## gravity as the real throw) and a ring on the ground shows where it lands and how big the blast / fire is.

const DOTS := 48

var _mm := MultiMesh.new()
var _ring := MeshInstance3D.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	name = "GrenadeArc"
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1, 0.86, 0.35, 0.9)
	_mat.no_depth_test = true
	_mat.render_priority = 5
	var dot := Geo.sphere(0.045, 8, 6).to_mesh(_mat)
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = dot
	_mm.instance_count = DOTS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var rmat := _mat.duplicate() as StandardMaterial3D
	rmat.albedo_color = Color(1, 0.45, 0.25, 0.75)
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.mesh = Geo.ring(0.88, 1.0, 48).to_mesh(rmat)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	hide_arc()


func hide_arc() -> void:
	_mm.visible_instance_count = 0
	_ring.visible = false


## Show the path of gadget `gid` thrown from origin along dir (simulated like the real projectile).
func show_arc(phys: Phys, gid: String, origin: Vector3, dir: Vector3) -> void:
	var g: Dictionary = Cfg.GADGETS[gid]
	var spec: Dictionary = g.projectile
	var vel: Vector3 = dir * float(spec.speed)
	var pos := origin
	var dt := 1.0 / 30.0
	var t := 0.0
	var n := 0
	var land = null
	var normal := Vector3.UP
	var since_dot := 0.0
	var traveled := 0.0
	while t < float(spec.life) and n < DOTS:
		vel.y -= float(spec.gravity) * dt
		var step := vel * dt
		var hit := phys.raycast(pos, step.normalized(), step.length() + float(spec.radius), true)
		if not hit.is_empty():
			land = hit.point
			normal = hit.normal
			break
		pos += step
		t += dt
		since_dot += step.length()
		traveled += step.length()
		# no dots right in front of the camera (they'd fill the screen)
		if since_dot >= 0.55 and traveled > 1.5:
			since_dot = 0.0
			_mm.set_instance_transform(n, Transform3D(Basis(), pos))
			n += 1
	_mm.visible_instance_count = n
	if land == null:
		land = pos
	# the ring: as wide as the blast (or the fire it leaves), lying on what it hits
	var ex: Dictionary = g.get("explosion", {})
	var r: float = ex.get("fire", {}).get("radius", ex.get("radius", 1.0)) if g.has("explosion") else 1.0
	if g.has("mine"):
		r = g.mine.trigger
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	_ring.transform = Transform3D(Basis(side, fwd, up) * Basis.from_scale(Vector3(r, r, 1)), (land as Vector3) + up * 0.05)
	_ring.visible = true
