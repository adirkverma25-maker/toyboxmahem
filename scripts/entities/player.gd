class_name Player
extends RefCounted
## You: look, movement intent, weapons, abilities, camera and viewmodel (port of src/entities/Player.ts).
## deps: {input, combat, audio, fx, phys, nearby_prompt(a), teammates(), aim_targets()}

## controller look speed at full stick, rad/s (about 200°/s)
const PAD_TURN := 3.5
## vertical turns a bit slower than horizontal
const PAD_PITCH_RATIO := 0.7

var actor: Actor
var camera: Camera3D
var vm: Viewmodel
var deps: Dictionary
var intent := Actor.Intent.new()
var recoil_pitch := 0.0  # deg
var recoil_yaw := 0.0  # deg
var trauma := 0.0
var shake_t := randf() * 100
var land_dip := [0.0, 0.0]
var bob := 0.0
var bob_amt := 0.0
var fov_kick := 0.0
var tilt := 0.0
var sprint_amt := 0.0
var auto_reload_at := 0.0
var scope_kick := 0.0
## crosshair spread in degrees (for the HUD)
var spread_deg := 0.0
var death_pos := Vector3.ZERO
var killer: Actor = null
var death_cam_t := 0.0
var interact_prompt := ""
var was_alive := true
var last_mouse := Vector2.ZERO
var was_drawing := false
var prev_ads := 0.0
## teammate being watched while down
var spectating: Actor = null
## true while revive is held
var revive_held := false
## last ability that failed because it was cooling down (HUD flashes it)
var denied := {"key": "", "at": -9.0}


## Converts horizontal FOV (what players expect in settings) to the vertical FOV the camera uses.
static func h_fov_to_v(h_deg: float, aspect: float) -> float:
	return rad_to_deg(2 * atan(tan(deg_to_rad(h_deg) / 2) / aspect))


func _init(a: Actor, cam: Camera3D, viewmodel: Viewmodel, d: Dictionary) -> void:
	actor = a
	camera = cam
	vm = viewmodel
	deps = d


func add_trauma(t: float) -> void:
	trauma = minf(1, trauma + t)


func equip_current(instant := false) -> void:
	var ws := actor.weapon()
	if ws == null:
		return
	vm.set_weapon(ws.id, instant)
	vm.scope_hidden = ws.overlay()
	vm.set_optic(ws.scope.id if ws.scope.style == "reticle" else "")
	var audio = deps.audio
	var wid := ws.id
	ws.on_reload_beat = func(part: String) -> void: audio.reload_part(wid, part)


func switch_to(s: int, now: float) -> void:
	var a := actor
	if s == a.slot or a.weapons[s] == null:
		return
	if a.weapon():
		a.weapon().cancel_reload()
	a.slot = s
	a.weapon().equip(now)
	equip_current()
	deps.audio.weapon_switch()


## Called when the player respawns.
func on_spawn() -> void:
	recoil_pitch = 0
	recoil_yaw = 0
	trauma = 0
	equip_current(false)
	was_alive = true


## Mouse + right-stick look. Also used on its own during the countdown.
func look(dt: float, assist := true) -> void:
	var input: GInput = deps.input
	var a := actor
	var ws := a.weapon()
	var ads_zoom := 1 + (ws.zoom() - 1) * a.ads if ws else 1.0
	var ads_scale: float = Settings.get_v("adsSensitivity") / ads_zoom if a.ads > 0.5 else 1.0
	var sens: float = Settings.get_v("sensitivity") * 0.0022 * ads_scale
	var inv := -1.0 if Settings.get_v("invertY") else 1.0
	var dx := input.mouse_dx
	var dy := input.mouse_dy * inv
	last_mouse = Vector2(dx, dy)
	if not a.alive:
		return
	# right stick
	var curve := func(v: float) -> float: return signf(v) * pow(absf(v), 1.9)
	var rate: float = PAD_TURN * Settings.get_v("padSensitivity") * ads_scale
	var pad_yaw: float = curve.call(input.look_x) * rate * dt
	var pad_pitch: float = curve.call(input.look_y) * rate * PAD_PITCH_RATIO * dt * inv
	if assist and GInput.using_pad and Settings.get_v("padAimAssist"):
		var help := _aim_assist(dt, Vector2(input.look_x, input.look_y).length() > 0.08 or Vector2(input.move_x, input.move_y).length() > 0.2)
		pad_yaw *= help
		pad_pitch *= help
	a.yaw -= dx * sens + pad_yaw
	var dp := -dy * sens - pad_pitch
	# pulling down against recoil "absorbs" it so recovery never overshoots
	if dp < 0 and recoil_pitch > 0:
		var absorb := minf(deg_to_rad(recoil_pitch), -dp)
		recoil_pitch -= rad_to_deg(absorb)
		dp += absorb
	a.pitch = clampf(a.pitch + dp, -1.5, 1.5)


## Controller aim assist against the closest visible enemy near the crosshair. Returns a look-speed multiplier.
func _aim_assist(dt: float, steering: bool) -> float:
	var a := actor
	var targets: Array = deps.aim_targets.call() if deps.has("aim_targets") else []
	if targets.is_empty():
		return 1.0
	var eye := a.eye_pos()
	var cp := cos(a.pitch)
	var best := {}
	for o in targets:
		if not o.alive or o.cloaked:
			continue
		var c: Vector3 = o.chest_pos()
		var d := c - eye
		var dist := d.length()
		if dist > 70 or dist < 0.5:
			continue
		var ty := atan2(-d.x, -d.z)
		var tp := asin(clampf(d.y / dist, -1, 1))
		var yaw_err := ty - a.yaw
		yaw_err = atan2(sin(yaw_err), cos(yaw_err))
		var pitch_err := tp - a.pitch
		var ang := Vector2(yaw_err * cp, pitch_err).length()
		# about a toy's width either side, never tiny at range, never huge up close
		var radius := clampf(atan2(0.9, dist), deg_to_rad(2.2), deg_to_rad(9))
		if ang > radius * 1.8:
			continue
		if not best.is_empty() and ang / radius >= best.ang / best.radius:
			continue
		if not deps.phys.los(eye, c, true):
			continue
		best = {"yaw_err": yaw_err, "pitch_err": pitch_err, "ang": ang, "radius": radius}
	var ads_start := a.ads > 0 and prev_ads == 0
	prev_ads = a.ads
	if best.is_empty():
		return 1.0
	var near := 1 - clampf(best.ang / (best.radius * 1.8), 0, 1)
	if ads_start and best.ang < best.radius * 1.6:
		a.yaw += best.yaw_err * 0.55
		a.pitch = clampf(a.pitch + best.pitch_err * 0.55, -1.5, 1.5)
		return 1.0
	if steering:
		var pull := (4.5 if a.ads > 0.5 else 2.8) * near * dt
		a.yaw += best.yaw_err * minf(1, pull)
		a.pitch = clampf(a.pitch + best.pitch_err * minf(1, pull), -1.5, 1.5)
	return 1 - near * (0.55 if a.ads > 0.5 else 0.4)


func update(dt: float, now: float) -> void:
	var input: GInput = deps.input
	var combat: Combat = deps.combat
	var audio = deps.audio
	var a := actor
	var reduced: bool = Settings.get_v("reducedMotion")
	# ---------------- look
	var ws := a.weapon()
	look(dt)
	# ---------------- movement intent
	var it := intent
	it.wish = Vector3.ZERO
	if a.alive:
		# keys and the left stick add up; a half-pushed stick walks slower
		var f := clampf((1.0 if input.act("forward") else 0.0) - (1.0 if input.act("back") else 0.0) - input.move_y, -1, 1)
		var r := clampf((1.0 if input.act("right") else 0.0) - (1.0 if input.act("left") else 0.0) + input.move_x, -1, 1)
		var sy := sin(a.yaw)
		var cy := cos(a.yaw)
		it.wish = Vector3(-sy * f + cy * r, 0, -cy * f - sy * r)
		if it.wish.length_squared() > 1:
			it.wish = it.wish.normalized()
	it.crouch_pressed = input.act_pressed("crouch")
	it.crouch = input.act("crouch")
	it.sprint = input.act("sprint") or input.pad_sprint
	it.jump = input.act_pressed("jump")
	it.dash = false  # set below if dash is one of your two abilities and you pressed its button
	var ads_held := input.act("aim") and a.alive and not (ws and ws.reloading and not ws.cfg.has("reloadPerShell"))
	it.ads = ads_held
	if ws:
		a.ads = clampf(a.ads + (dt / ws.ads_time() if ads_held else -dt / (ws.ads_time() * 0.8)), 0, 1)
	if it.sprint and it.wish.length_squared() > 0.01:
		a.ads = maxf(0, a.ads - dt * 6)
	# aiming cancels the controller's sprint latch
	if ads_held:
		input.pad_sprint = false
	# ---------------- weapons
	# reload, unless it shares a button with revive and a downed teammate is right here
	var reload_pressed := input.act_pressed("reload") and not (interact_prompt != "" and input.act("revive"))
	if a.alive and ws:
		if input.act_pressed("weapon1"):
			switch_to(0, now)
		if input.act_pressed("weapon2"):
			switch_to(1, now)
		if input.wheel != 0 or input.act_pressed("swap"):
			switch_to(1 if a.slot == 0 else 0, now)
		var cw := a.weapon()
		if reload_pressed:
			if cw.is_energy():
				cw.vent(now)
			elif cw.start_reload():
				vm.cancel_inspect()
		if input.act_pressed("inspect"):
			vm.inspect()
		var infinite := a.has_buff("infinite", now)
		var res := cw.pull_trigger(now, input.act_pressed("fire"), input.act("fire"), infinite)
		if cw.drawing() and not was_drawing:
			audio.bow_draw()
		was_drawing = cw.drawing()
		if res == -1 and input.act_pressed("fire"):
			audio.empty()
			if cw.can_start_reload():
				cw.start_reload()
		var moving := clampf(a.speed / Cfg.MOVE.walkSpeed, 0, 1.4)
		spread_deg = cw.spread(a.ads, moving, not a.grounded)
		if res > 0:
			a.spawn_protect_until = minf(a.spawn_protect_until, now)  # firing ends spawn protection
			for i in res:
				var eye := a.eye_pos()
				var dir := aim_dir()
				var muzzle := Viewmodel.muzzle_world(camera.global_transform, a.ads)
				var sp := cw.spread(a.ads, moving, not a.grounded)
				combat.fire(a, cw, eye, dir, muzzle, sp)
				var k := cw.kick(a.ads > 0.5)
				recoil_pitch += k.x
				recoil_yaw += k.y
				vm.on_fire(cw.id, a.ads > 0.5, reduced)
				audio.gunshot(cw.id, eye, true)
				if cw.id == "thunderspring":
					Engine.get_main_loop().create_timer(0.28).timeout.connect(func(): audio.spring_wind(null, true))
				add_trauma(cw.cfg.kick.shake * 0.6)
				input.rumble(0.25 + cw.cfg.kick.shake * 0.5, cw.cfg.kick.shake * 0.6, 60 if cw.cfg.auto else 110)
				scope_kick = 1.0 if cw.overlay() else scope_kick
				a.fire_kick = 1
			if cw.mag <= 0 and not cw.is_energy() and cw.reserve > 0:
				auto_reload_at = now + 0.3
		if auto_reload_at > 0 and now >= auto_reload_at:
			auto_reload_at = 0
			if a.weapon() == cw and cw.mag <= 0:
				cw.start_reload()
		# recoil recovery (frame-rate independent, after a short delay)
		if now - cw.last_shot > cw.cfg.recoveryDelay:
			var rate: float = cw.cfg.recoveryRate * dt
			recoil_pitch = maxf(0, recoil_pitch - rate) + minf(0, recoil_pitch + rate)
			if recoil_pitch < 0:
				recoil_pitch = minf(0, recoil_pitch + rate)
			var yr := rate * 0.8
			recoil_yaw = 0.0 if absf(recoil_yaw) <= yr else recoil_yaw - signf(recoil_yaw) * yr
	# ---------------- abilities (dash is part of movement)
	if a.alive:
		var adeps := {"combat": combat, "phys": deps.phys, "audio": audio}
		for k in [["ability1", 0], ["ability2", 1]]:
			if input.act_pressed(k[0]) and a.abilities.size() > k[1] and a.abilities[k[1]] != "":
				_use_ability(a.abilities[k[1]], now, adeps)
	revive_held = a.alive and input.act("revive")
	# interact: grab a zipline in reach (reviving a teammate takes priority)
	if a.alive and a.zip == null and input.act_pressed("revive") and deps.has("try_zip"):
		if deps.try_zip.call(a):
			input.rumble(0.2, 0.1, 80)
	interact_prompt = deps.nearby_prompt.call(a) if a.alive else ""
	# ---------------- spectating teammates while down
	if a.alive:
		spectating = null
	else:
		var mates: Array = deps.teammates.call()
		if spectating and not mates.has(spectating):
			spectating = null
		if mates.size() and death_cam_t > 1.3:
			var i := mates.find(spectating) if spectating else -1
			if spectating == null:
				spectating = mates[0]
			elif input.act_pressed("fire") or input.act_pressed("jump"):
				spectating = mates[(i + 1) % mates.size()]
			elif input.act_pressed("aim"):
				spectating = mates[(i - 1 + mates.size()) % mates.size()]
		if mates.is_empty():
			spectating = null
	scope_kick = maxf(0, scope_kick - dt * 1.8)


func _use_ability(id: String, now: float, adeps: Dictionary) -> void:
	var a := actor
	var deny := func(key: String) -> void: denied = {"key": key, "at": now}
	match id:
		"dash":
			intent.dash = true
			if now < a.dash_ready_at and not a.dashing:
				deny.call("dash")
		"jab":
			if Abilities.try_jab(a, now, adeps):
				vm.punch()
				add_trauma(0.12)
			else:
				deny.call("jab")
		"grapple":
			var r = Abilities.try_grapple(a, aim_dir(), now, adeps)
			if r is bool and r == false:
				deny.call("grapple")
			elif not (r is String):
				add_trauma(0.1)
		"cloak":
			if not Abilities.try_cloak(a, now, adeps):
				deny.call("cloak")
		_:
			if not Abilities.try_shield(a, now, adeps):
				deny.call("shield")


## View direction including recoil.
func aim_dir() -> Vector3:
	var a := actor
	var p := a.pitch + deg_to_rad(recoil_pitch)
	var y := a.yaw - deg_to_rad(recoil_yaw)
	return Vector3(-sin(y) * cos(p), sin(p), -cos(y) * cos(p)).normalized()


func on_land(strength: float) -> void:
	land_dip[1] -= strength * 2.2
	vm.on_land(strength)


func on_damaged(amount: float) -> void:
	add_trauma(minf(0.35, amount / 120))
	deps.input.rumble(0.3, minf(1, 0.2 + amount / 60), 140)


func on_death(k: Actor) -> void:
	killer = k
	death_pos = actor.pos
	death_cam_t = 0
	was_alive = false
	spectating = null


static func _look_basis(from: Vector3, to: Vector3) -> Basis:
	var d := to - from
	if d.length_squared() < 1e-8:
		return Basis()
	return Basis.looking_at(d.normalized(), Vector3.UP)


## Apply camera transform (after movement).
func update_camera(dt: float, _now: float) -> void:
	var a := actor
	var cam := camera
	var reduced: bool = Settings.get_v("reducedMotion")
	var shake_on := (0.3 if reduced else 1.0) if Settings.get_v("cameraShake") else 0.0
	var ws := a.weapon()
	# vertical FOV from horizontal setting, plus ADS zoom and a little sprint kick
	var sprinting := a.alive and intent.sprint and a.speed > Cfg.MOVE.walkSpeed * 1.1 and not a.crouching
	sprint_amt = U.damp(sprint_amt, 1.0 if sprinting else 0.0, 8, dt)
	fov_kick = U.damp(fov_kick, (4.0 if sprinting and not reduced else 0.0) + (8.0 if a.dashing and not reduced else 0.0), 8, dt)
	var zoom := 1 + (ws.zoom() - 1) * a.ads if ws and a.alive else 1.0
	var vs := cam.get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(1, vs.y)
	var base_v := h_fov_to_v(Settings.get_v("fov") + fov_kick, aspect)
	var v := rad_to_deg(2 * atan(tan(deg_to_rad(base_v) / 2) / zoom))
	if absf(cam.fov - v) > 0.01:
		cam.fov = v
	if not a.alive:
		# death cam: rise above the pieces and look at whoever got you
		death_cam_t += dt
		var sp := spectating
		if sp and sp.alive:
			# chase cam behind the teammate, pulled in if a wall is in the way
			var eye := sp.eye_pos()
			var f := sp.forward()
			var back := Vector3(-f.x, -f.y * 0.5 + 0.22 - f.y * 0.0, -f.z)
			back.y = -f.y * 0.5 + 0.22
			back = back.normalized()
			var room: float = deps.phys.ray_dist(eye, back, 3.8, true)
			var want := eye + back * maxf(0.6, minf(3.6, room - 0.3))
			cam.position = cam.position.lerp(want, 1 - exp(-10 * dt))
			var tq := Quaternion(_look_basis(cam.position, eye + f * 6))
			cam.quaternion = cam.quaternion.slerp(tq, 1 - exp(-12 * dt))
			return
		var t := minf(1, death_cam_t / 0.8)
		var target: Vector3 = killer.chest_pos() if killer and killer.alive else death_pos + Vector3(0, 0.5, 0)
		var bk := Vector3(sin(a.yaw), 0, cos(a.yaw)) * 3
		var want := death_pos + bk
		want.y = death_pos.y + 2.8 + t * 0.5
		cam.position = cam.position.lerp(want, 1 - exp(-4 * dt))
		var q := Quaternion(_look_basis(cam.position, target))
		cam.quaternion = cam.quaternion.slerp(q, 1 - exp(-5 * dt))
		return
	# landing spring
	var n := maxi(1, ceili(dt * 240))
	for i in n:
		var h := dt / n
		land_dip[1] += (-120 * land_dip[0] - 14 * land_dip[1]) * h
		land_dip[0] += land_dip[1] * h
	# head bob
	var moving := clampf(a.speed / 7, 0, 1.2) if a.grounded and not a.sliding else 0.0
	bob_amt = U.damp(bob_amt, moving * (1 - a.ads * 0.8), 8, dt)
	bob += dt * (6 + a.speed * 1.1)
	var bob_k := 0.25 if reduced else 1.0
	var bob_y := sin(bob * 2) * 0.025 * bob_amt * bob_k
	var bob_roll := sin(bob) * 0.004 * bob_amt * bob_k
	tilt = U.damp(tilt, (0.07 if a.sliding else 0.0) * (0.3 if reduced else 1.0), 10, dt)
	# shake (trauma^2, smooth noise)
	trauma = maxf(0, trauma - dt * 1.6)
	shake_t += dt * 22
	var sh := trauma * trauma * shake_on
	var nx := deg_to_rad((sin(shake_t * 1.13) + sin(shake_t * 2.71 + 1.3) * 0.5) * sh * 1.2)
	var ny := deg_to_rad((sin(shake_t * 1.37 + 2.1) + sin(shake_t * 3.11) * 0.5) * sh * 1.2)
	var nr := deg_to_rad(sin(shake_t * 0.93 + 4) * sh * 1.5)
	var eye := a.eye_pos()
	cam.position = Vector3(eye.x, eye.y + bob_y + land_dip[0] * 0.06 * (0.4 if reduced else 1.0), eye.z)
	var pitch := a.pitch + deg_to_rad(recoil_pitch) + ny
	var yaw := a.yaw - deg_to_rad(recoil_yaw) + nx
	cam.rotation_order = EULER_ORDER_YXZ
	cam.rotation = Vector3(pitch, yaw, bob_roll + tilt + nr)


func update_viewmodel(dt: float, now: float) -> void:
	var a := actor
	vm.visible = a.alive
	if not a.alive:
		return
	var ws := a.weapon()
	vm.update(dt, {
		"ws": ws, "ads": a.ads, "sprint": sprint_amt, "speed": a.speed, "grounded": a.grounded, "crouch": a.crouch_t,
		"mouseDX": last_mouse.x, "mouseDY": last_mouse.y, "now": now, "reducedMotion": Settings.get_v("reducedMotion"),
		"infinite": a.has_buff("infinite", now), "sliding": a.sliding, "charge": ws.charge_at(now) if ws else 0.0, "cloaked": a.cloaked,
	})
