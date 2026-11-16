class_name MeleeModel
## The toy melee weapons (Cfg.MELEE): a plastic sword for Lights, a plastic spear for Mediums.
## Built pointing down -Z with the grip at the origin, so a parent can swing or thrust it.


static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "melee_" + kind
	var down := Basis(Vector3.RIGHT, PI / 2)  # cylinders run along Y; turn them to run along Z
	if kind == "spear":
		var shaft := Mats.plastic("#b5793c", {"rough": 0.55})
		var tip := Mats.plastic("#dfe7ef", {"rough": 0.25, "clearcoat": 0.6})
		var band := Mats.plastic("#e63946", {"rough": 0.35})
		root.add_child(Geo.cylinder(0.022, 0.022, 1.25, 10).mesh_instance(shaft, Vector3(0, 0, -0.45), down, false))
		root.add_child(Geo.cylinder(0.034, 0.034, 0.08, 12).mesh_instance(band, Vector3(0, 0, -1.02), down, false))
		root.add_child(Geo.cone(0.06, 0.24, 4).mesh_instance(tip, Vector3(0, 0, -1.18), Basis(Vector3.RIGHT, -PI / 2), false))
		root.add_child(Geo.sphere(0.035, 10, 8).mesh_instance(band, Vector3(0, 0, 0.18), Basis(), false))
	else:
		var blade := Mats.plastic("#c9d6e3", {"rough": 0.2, "clearcoat": 0.8})
		var guard := Mats.plastic("#ffd23f", {"rough": 0.3})
		var grip := Mats.plastic("#3a86ff", {"rough": 0.5})
		root.add_child(Geo.cylinder(0.026, 0.03, 0.16, 10).mesh_instance(grip, Vector3(0, 0, 0.05), down, false))
		root.add_child(Geo.sphere(0.04, 10, 8).mesh_instance(guard, Vector3(0, 0, 0.14), Basis(), false))
		root.add_child(Geo.rounded_box(0.2, 0.04, 0.05, 2, 0.015).mesh_instance(guard, Vector3(0, 0, -0.04), Basis(), false))
		root.add_child(Geo.rounded_box(0.07, 0.02, 0.62, 2, 0.008).mesh_instance(blade, Vector3(0, 0, -0.38), Basis(), false))
		root.add_child(Geo.cone(0.035, 0.1, 4).mesh_instance(blade, Vector3(0, 0, -0.74), Basis(Vector3.RIGHT, -PI / 2), false))
	return root


## Pose of a swing at progress k (0..1): where the weapon sits and how it is turned, in the holder's space
## (forward = -Z). The sword slashes right to left, the spear thrusts.
static func pose(kind: String, k: float) -> Transform3D:
	var out := U.smoothstep(0, 0.25, k) if k < 0.25 else 1.0 - U.smoothstep(0.7, 1.0, k)
	if kind == "spear":
		var reach := lerpf(0.05, 0.75, U.smoothstep(0.05, 0.35, k)) * out
		return Transform3D(U.euler(0.05, 0, 0), Vector3(0.12, -0.12, -reach))
	var sweep := lerpf(1.1, -1.1, U.smoothstep(0.1, 0.6, k))
	return Transform3D(U.euler(-0.35 * out, sweep, -0.5), Vector3(0.12 * out, -0.08, -0.1 * out))
