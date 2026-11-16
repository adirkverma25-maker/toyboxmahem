class_name MeleeModel
## The toy melee weapons (Cfg.MELEE): a plastic sword for Lights, a plastic spear for Mediums.
## Built pointing down -Z with the grip at the origin. Swings are keyframed: wind-up, strike, follow-through,
## recover. `pose` is first person (view space), `arm_dir` drives a toy's right arm in third person.

## first-person keyframes: [time 0..1, euler (x, y, z), position]; the first/last key is the ready pose
const VIEW_KEYS := {
	"sword": [
		[0.0, Vector3(0.25, -0.35, -0.55), Vector3(0.24, -0.26, -0.42)],
		[0.22, Vector3(0.95, 0.95, -1.1), Vector3(0.36, 0.06, -0.3)],  # wind-up: up and back over the right shoulder
		[0.5, Vector3(-0.55, -1.25, 0.7), Vector3(-0.22, -0.3, -0.5)],  # strike: a fast diagonal cut to lower left
		[0.66, Vector3(-0.7, -1.45, 0.9), Vector3(-0.3, -0.36, -0.44)],  # follow-through
		[1.0, Vector3(0.25, -0.35, -0.55), Vector3(0.24, -0.26, -0.42)],
	],
	"spear": [
		[0.0, Vector3(0.12, -0.05, -0.1), Vector3(0.2, -0.24, -0.35)],
		[0.3, Vector3(0.2, 0.06, -0.15), Vector3(0.24, -0.18, -0.08)],  # wind-up: drawn back, tip raised
		[0.48, Vector3(0.02, 0.0, -0.05), Vector3(0.08, -0.14, -0.95)],  # thrust
		[0.62, Vector3(0.02, 0.0, -0.05), Vector3(0.08, -0.15, -0.9)],  # hold
		[1.0, Vector3(0.12, -0.05, -0.1), Vector3(0.2, -0.24, -0.35)],
	],
}
## third-person keyframes: [time, arm direction in torso space (+Z forward), forearm bend]
const ARM_KEYS := {
	"sword": [[0.0, Vector3(-0.1, -0.2, 1), -0.2], [0.22, Vector3(0.6, 0.9, -0.1), -1.2], [0.5, Vector3(-0.8, -0.3, 0.9), -0.1], [0.66, Vector3(-0.9, -0.5, 0.6), -0.1], [1.0, Vector3(-0.1, -0.2, 1), -0.2]],
	"spear": [[0.0, Vector3(-0.1, -0.1, 1), -0.4], [0.3, Vector3(0.1, 0.1, 0.4), -1.3], [0.48, Vector3(-0.05, 0.05, 1), 0.0], [0.62, Vector3(-0.05, 0.05, 1), 0.0], [1.0, Vector3(-0.1, -0.1, 1), -0.4]],
}


static func build(kind: String, with_hand := false) -> Node3D:
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
	if with_hand:
		# a toy mitten wrapped round the grip
		var glove := Mats.plastic("#f4c7a1", {"rough": 0.6})
		root.add_child(Geo.rounded_box(0.09, 0.1, 0.11, 2, 0.04).mesh_instance(glove, Vector3(0, -0.01, 0.06), Basis(), false))
	return root


## Ease between keyframes (smooth in and out of each key).
static func _between(keys: Array, k: float) -> Array:
	k = clampf(k, 0, 1)
	for i in range(1, keys.size()):
		if k <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var t := U.smoothstep(0, 1, (k - a[0]) / maxf(0.0001, b[0] - a[0]))
			return [a, b, t]
	var last: Array = keys[keys.size() - 1]
	return [last, last, 0.0]


## First-person pose at swing progress k (0..1); k = 0 (or 1) is the ready pose.
static func pose(kind: String, k: float) -> Transform3D:
	var e := _between(VIEW_KEYS[kind], k)
	var qa := Quaternion(U.euler(e[0][1].x, e[0][1].y, e[0][1].z))
	var qb := Quaternion(U.euler(e[1][1].x, e[1][1].y, e[1][1].z))
	return Transform3D(Basis(qa.slerp(qb, e[2])), (e[0][2] as Vector3).lerp(e[1][2], e[2]))


## Third person: [right-arm direction (torso space), forearm bend] at swing progress k.
static func arm_dir(kind: String, k: float) -> Array:
	var e := _between(ARM_KEYS[kind], k)
	return [(e[0][1] as Vector3).lerp(e[1][1], e[2]).normalized(), lerpf(e[0][2], e[1][2], e[2])]
