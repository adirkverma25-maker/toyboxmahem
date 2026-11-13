extends Node
## Player accounts, saved on this computer (port of src/core/Accounts.ts). Autoload "Accounts".
## Each account gets its own coins, unlocks, career stats, loadout, settings and key bindings.
## Passwords are never stored: only a salted, iterated SHA-256 hash (the original game's "sha256x" scheme).

signal switched(info: Dictionary)

const KEY := "toybox-mayhem.accounts.v1"
const GUEST := "__guest__"
const GUEST_INFO := {"id": "", "name": "Guest", "guest": true}
const MIN_PASSWORD := 4
const ITER := 4000

var info: Dictionary = GUEST_INFO.duplicate()
var _name_rule := RegEx.create_from_string("^[A-Za-z0-9 _-]{2,14}$")


func _ready() -> void:
	var s := _read()
	var sess = s.session
	if sess is String and sess != GUEST and s.users.has(sess):
		_apply({"id": sess, "name": s.users[sess].name, "guest": false}, false)


func _read() -> Dictionary:
	var s = Store.get_json(KEY)
	if not (s is Dictionary):
		s = {}
	return {"users": s.users if s.get("users") is Dictionary else {}, "session": s.session if s.get("session") is String else null}


func _write(s: Dictionary) -> void:
	Store.set_json(KEY, s)


func current() -> Dictionary:
	return info


## true until the player has chosen to log in, register or play as guest once
func needs_choice() -> bool:
	return _read().session == null


func _hash(password: String, salt: String, iter: int) -> String:
	var h := (salt + ":" + password).to_utf8_buffer()
	for i in iter:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(h)
		h = ctx.finish()
	return h.hex_encode()


func _salt() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Point settings, stats, bindings and progress at this account's storage.
func _apply(a: Dictionary, notify := true, seed_from_current := false) -> void:
	info = a
	Settings.use_profile(a.id, seed_from_current)
	if not a.guest:
		Settings.set_v("playerName", a.name)
	Binds.load_binds()
	Progress.use_profile(a.id)
	if notify:
		switched.emit(a)


## Returns "" on success or an error message.
func register(name: String, password: String) -> String:
	name = name.strip_edges()
	if _name_rule.search(name) == null:
		return "Names are 2 to 14 letters, numbers, spaces, - or _."
	if password.length() < MIN_PASSWORD:
		return "Passwords need at least %d characters." % MIN_PASSWORD
	var s := _read()
	var id := name.to_lower()
	if id == GUEST or s.users.has(id):
		return "That name is taken on this computer. Try another, or log in."
	var salt := _salt()
	s.users[id] = {"name": name, "salt": salt, "hash": _hash(password, salt, ITER), "algo": "sha256x", "iter": ITER, "created": Time.get_unix_time_from_system()}
	s.session = id
	_write(s)
	# a new account keeps your controls and settings but starts its own coins, unlocks and stats
	_apply({"id": id, "name": name, "guest": false}, true, true)
	return ""


## Returns "" on success or an error message.
func login(name: String, password: String) -> String:
	var s := _read()
	var id := name.strip_edges().to_lower()
	if not s.users.has(id):
		return "No account with that name on this computer."
	var u: Dictionary = s.users[id]
	if _hash(password, u.salt, int(u.get("iter", ITER))) != u.hash:
		return "Wrong password."
	s.session = id
	_write(s)
	_apply({"id": id, "name": u.name, "guest": false})
	return ""


func play_as_guest() -> Dictionary:
	var s := _read()
	s.session = GUEST
	_write(s)
	_apply(GUEST_INFO.duplicate())
	return info


func logout() -> void:
	play_as_guest()


## Names of accounts saved on this computer (for the login screen).
func saved_names() -> Array:
	var out := []
	for u in _read().users.values():
		out.append(u.name)
	return out
