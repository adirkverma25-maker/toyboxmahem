class_name WeaponState
extends RefCounted
## Runtime state of one equipped weapon: ammo, reload, fire timing, bloom and recoil bookkeeping
## (port of src/weapons/WeaponState.ts). Shared by the player and the bots so both follow identical rules.

## Timeline of reload sounds/animation beats, as fractions of the reload.
const RELOAD_BEATS := {
	"plasti9": [[0.12, "out"], [0.3, "drop"], [0.55, "in"], [0.82, "charge"]],
	"foamFury": [[0.12, "out"], [0.3, "drop"], [0.5, "in"], [0.78, "charge"]],
	"brickbreaker": [[0.15, "out"], [0.32, "drop"], [0.52, "in"], [0.8, "charge"]],
	"thunderspring": [[0.1, "out"], [0.25, "drop"], [0.45, "in"], [0.72, "charge"]],
	"rapidRascal": [[0.14, "out"], [0.32, "drop"], [0.55, "in"], [0.85, "charge"]],
	"crayonCannon": [[0.15, "out"], [0.33, "drop"], [0.55, "in"], [0.82, "charge"]],
	"jackBlaster": [[0.12, "out"], [0.3, "drop"], [0.5, "in"], [0.8, "charge"]],
	"plungerBow": [[0.15, "out"], [0.55, "in"], [0.85, "charge"]],
	"popcornPopper": [[0.12, "out"], [0.3, "drop"], [0.52, "in"], [0.8, "charge"]],
	"walloper": [[0.12, "out"], [0.3, "drop"], [0.5, "in"], [0.82, "charge"]],
	"tumbleweed": [[0.13, "out"], [0.31, "drop"], [0.53, "in"], [0.8, "charge"]],
}

var id: String
var cfg: Dictionary
var mag: float
var reserve: int
var reloading := false
var reload_t := 0.0
var _shell_phase := "open"
var _shell_timer := 0.0
var _beat_idx := 0
var next_fire := 0.0
var shot_index := 0
var last_shot := -10.0
var bloom := 0.0
var recoil_pitch := 0.0
var recoil_yaw := 0.0
var lockout := false
var equip_t := 0.0
## charge weapons (bow): time the draw started, -1 when not drawing
var draw_start := -1.0
## per-shell reloads: "open" (hand to the shells), "shells" (one going in), "close"
func shell_phase() -> String:
	return _shell_phase if reloading and cfg.has("reloadPerShell") else ""


## 0..1 through the current shell being pushed in (1 = it's in)
func shell_t() -> float:
	if _shell_phase == "shells":
		return clampf(1 - _shell_timer / float(cfg.reloadPerShell), 0, 1)
	if _shell_phase == "open":
		return clampf(1 - _shell_timer / 0.25, 0, 1)
	return clampf(1 - _shell_timer / 0.3, 0, 1)


## charge (0..1) of the shot that was just released
var last_charge := 1.0
var on_reload_beat := Callable()
var on_reload_done := Callable()
var scope: Dictionary
var _burst_left := 0
var _burst_next := 0.0


func _init(weapon_id: String, scope_id := "") -> void:
	id = weapon_id
	cfg = Cfg.WEAPONS[weapon_id]
	var fits: Array = Cfg.WEAPON_SCOPES[weapon_id]
	scope = Cfg.SCOPES[scope_id if scope_id != "" and fits.has(scope_id) else fits[0]]
	mag = cfg.magSize
	reserve = int(cfg.reserve)


## zoom factor when fully aimed
func zoom() -> float:
	return float(scope.zoom) if scope.zoom != null else float(cfg.adsZoom)


func ads_time() -> float:
	return cfg.adsTime * scope.adsTimeMult


## full-screen scope picture when aimed
func overlay() -> bool:
	return scope.style == "overlay"


func is_energy() -> bool:
	return cfg.has("energy")


func is_charge() -> bool:
	return cfg.has("charge")


func drawing() -> bool:
	return draw_start >= 0


## 0..1 progress for HUD
func reload_progress() -> float:
	if not reloading:
		return 0.0
	if cfg.has("reloadPerShell"):
		return clampf(mag / cfg.magSize, 0, 1)
	return clampf(reload_t / cfg.reloadTime, 0, 1)


func interval() -> float:
	return 60.0 / cfg.rpm


## 0..1 how far the bow is drawn right now
func charge_at(now: float) -> float:
	if not cfg.has("charge") or draw_start < 0:
		return 0.0
	return clampf((now - draw_start) / cfg.charge.time, 0, 1)


func cancel_draw() -> void:
	draw_start = -1


func equip(now: float, time := 0.32) -> void:
	cancel_reload()
	cancel_draw()
	_burst_left = 0
	equip_t = time
	next_fire = maxf(next_fire, now + time * 0.8)


func can_start_reload() -> bool:
	if is_energy() or reloading:
		return false
	return mag < cfg.magSize and reserve > 0


func start_reload() -> bool:
	if not can_start_reload():
		return false
	cancel_draw()
	reloading = true
	_burst_left = 0
	reload_t = 0
	_beat_idx = 0
	_shell_phase = "open"
	_shell_timer = 0.25
	if cfg.has("reloadPerShell"):
		_beat("open")
	return true


## Interrupting never refills: ammo is only granted when the reload (or a shell) completes.
func cancel_reload() -> void:
	reloading = false
	reload_t = 0
	_beat_idx = 0


func _beat(part: String) -> void:
	if on_reload_beat.is_valid():
		on_reload_beat.call(part)


## Energy weapon manual vent: skips the recharge delay.
func vent(now: float) -> bool:
	if not is_energy() or mag >= cfg.magSize:
		return false
	last_shot = now - (cfg.energy.rechargeDelay + 0.01)
	_beat("vent")
	return true


## How many shots should be fired this frame (0..2) given trigger state. Consumes ammo. -1 = dry fire.
func pull_trigger(now: float, pressed: bool, held: bool, infinite: bool) -> int:
	if equip_t > 0:
		return 0
	if cfg.has("charge"):
		return _pull_charge(now, pressed, held, infinite)
	if cfg.has("burst"):
		return _pull_burst(now, held, infinite)
	var wants := held if cfg.auto else pressed
	if not wants:
		return 0
	if lockout:
		return 0
	if mag <= 0 and not infinite:
		return -1
	if reloading:
		if cfg.has("reloadPerShell") and mag > 0:
			cancel_reload()
		elif not infinite:
			return 0
		else:
			cancel_reload()
	if now < next_fire:
		return 0
	var shots := 0
	# catch up at most one extra shot for low frame rates, never bank shots after a pause
	if next_fire < now - interval() * 2:
		next_fire = now
	while now >= next_fire and shots < 2 and (mag > 0 or infinite):
		shots += 1
		next_fire += interval()
		if not infinite:
			mag -= cfg.energy.perShot if is_energy() else 1
		if not cfg.auto:
			break
	if next_fire < now:
		next_fire = now + interval()
	if is_energy() and mag <= 0:
		mag = 0
		lockout = true
	if shots > 0:
		if now - last_shot > maxf(0.28, interval() * 2.2):
			shot_index = 0
		last_shot = now
	return shots


## Burst fire: one pull starts a burst that finishes on its own; holding the trigger keeps bursting.
func _pull_burst(now: float, held: bool, infinite: bool) -> int:
	var b: Dictionary = cfg.burst
	if _burst_left <= 0:
		if not held:
			return 0
		if mag <= 0 and not infinite:
			return -1
		if reloading:
			if not infinite:
				return 0
			cancel_reload()
		if now < next_fire:
			return 0
		_burst_left = b.count
		_burst_next = now
		if now - last_shot > maxf(0.28, interval() * 1.5):
			shot_index = 0
	if now < _burst_next:
		return 0
	if mag <= 0 and not infinite:
		_burst_left = 0
		next_fire = now + interval()
		return 0
	if not infinite:
		mag -= 1
	_burst_left -= 1
	_burst_next = now + b.gap
	last_shot = now
	if _burst_left <= 0:
		next_fire = now + interval()
	return 1


## Bow: hold to draw, release to loose. Returns 1 on release, -1 for a dry pull, else 0.
func _pull_charge(now: float, pressed: bool, held: bool, infinite: bool) -> int:
	if draw_start >= 0:
		if held:
			return 0
		last_charge = charge_at(now)
		draw_start = -1
		if not infinite:
			mag -= 1
		next_fire = now + interval()
		if now - last_shot > 1:
			shot_index = 0
		last_shot = now
		return 1
	if not held:
		return 0
	if mag <= 0 and not infinite:
		return -1 if pressed else 0
	if reloading:
		if not pressed:
			return 0
		cancel_reload()
	if now < next_fire:
		return 0
	draw_start = now
	return 0


## Recoil kick (deg) for the current shot; advances the spray index. Returns Vector2(pitch, yaw).
func kick(ads: bool) -> Vector2:
	var r: Dictionary = cfg.recoil
	var pitch := 0.0
	var yaw := 0.0
	var i := shot_index
	if r.kind == "pattern":
		var k := i
		var n: int = r.pitch.size()
		if k >= n:
			k = int(r.loopFrom) + ((k - int(r.loopFrom)) % (n - int(r.loopFrom)))
		pitch = r.pitch[k] + U.rand(-r.jitter, r.jitter)
		yaw = r.yaw[k] + U.rand(-r.jitter, r.jitter)
	else:
		pitch = minf(r.pitchMax, r.pitch + r.pitchGrowth * i)
		var yv: float = r.yaw + r.yawGrowth * i
		yaw = U.rand(-yv, yv) + r.yawBias * mini(i, 8)
	var mult: float = cfg.adsRecoilMult if ads else 1.0
	pitch *= mult
	yaw *= mult
	recoil_pitch += pitch
	recoil_yaw += yaw
	bloom = minf(cfg.spread.bloomMax, bloom + cfg.spread.bloomPerShot)
	shot_index += 1
	return Vector2(pitch, yaw)


## Current spread cone half-angle in degrees.
func spread(ads: float, moving: float, airborne: bool) -> float:
	var s: Dictionary = cfg.spread
	var base: float = s.hip + (s.ads - s.hip) * ads
	return base + s.move * moving * (1 - ads * 0.6) + (s.air if airborne else 0.0) + bloom


func update(dt: float, now: float) -> void:
	if equip_t > 0:
		equip_t = maxf(0, equip_t - dt)
	bloom = U.move_toward_f(bloom, 0, cfg.spread.bloomDecay * dt * (1.0 if now - last_shot > 0.15 else 0.35))
	# camera recoil recovery
	if now - last_shot > cfg.recoveryDelay:
		var rate: float = cfg.recoveryRate * dt
		recoil_pitch = U.move_toward_f(recoil_pitch, 0, rate)
		recoil_yaw = U.move_toward_f(recoil_yaw, 0, rate * 0.8)
	# energy recharge
	if is_energy():
		var e: Dictionary = cfg.energy
		if now - last_shot > e.rechargeDelay and mag < cfg.magSize:
			mag = minf(cfg.magSize, mag + e.rechargeRate * dt)
		if lockout and mag >= e.lockoutUntil:
			lockout = false
		return
	if not reloading:
		return
	if cfg.has("reloadPerShell"):
		_shell_timer -= dt
		if _shell_timer <= 0:
			if _shell_phase == "open":
				_shell_phase = "shells"
				_shell_timer = cfg.reloadPerShell
			elif _shell_phase == "shells":
				if mag < cfg.magSize and reserve > 0:
					mag += 1
					reserve -= 1
					_beat("shell")
				if mag >= cfg.magSize or reserve <= 0:
					_shell_phase = "close"
					_shell_timer = 0.3
					_beat("pump")
				else:
					_shell_timer = cfg.reloadPerShell
			else:
				reloading = false
				if on_reload_done.is_valid():
					on_reload_done.call()
		return
	reload_t += dt
	var beats: Array = RELOAD_BEATS.get(id, [])
	var f: float = reload_t / cfg.reloadTime
	while _beat_idx < beats.size() and f >= beats[_beat_idx][0]:
		_beat(beats[_beat_idx][1])
		_beat_idx += 1
	if reload_t >= cfg.reloadTime:
		var need := int(cfg.magSize - mag)
		var take := mini(need, reserve)
		mag += take
		reserve -= take
		reloading = false
		if on_reload_done.is_valid():
			on_reload_done.call()


## Refill from an ammo pickup (same weapon picked up again).
func add_ammo() -> void:
	if is_energy():
		mag = cfg.magSize
		return
	reserve = int(minf(cfg.reserve * 1.5, reserve + ceilf(cfg.reserve * 0.6)))
