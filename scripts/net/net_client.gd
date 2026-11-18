extends Node
## Online play: one WebSocket to the relay (server/worker.js). Autoload "Net" (port of src/net/NetClient.ts).
## It lives above the scene, so the connection survives the scene reload a map change needs.
## Game messages travel inside the relay's `relay` envelope. Messages that arrive while nobody is
## listening (during a reload) wait in `inbox` and are handed over once a session attaches.
##
## Roles: one HOST per room runs the real match (bots, damage, scores, mode rules); GUESTS move their own
## toy, check their own shots and tell the host. The relay only routes: guest -> host, host -> one or all.

const PROTOCOL_VERSION := 107
## host snapshots per second
const TICK_RATE := 20
## guest state messages per second
const GUEST_RATE := 30
## humans per room (host included)
const MAX_HUMANS := 8
## The online relay (Cloudflare Worker, see server/README.md; `npm run deploy` there fills this in).
## The Server box on the Multiplayer screen (Settings serverUrl) or --server=<url> override it.
const DEFAULT_SERVER := "wss://toybox-mayhem-relay.toybox-mayhem-relay.workers.dev"

## offline | connecting | online | error
var status := "offline"
## solo | host | guest
var role := "solo"
var id := ""
var room := ""
var player_name := ""
var host_id := ""
## everyone else in the room (host included, for guests): id -> name
var peers := {}
## round-trip time in ms (smoothed)
var rtt := 0.0
## server clock minus ours, ms
var clock_offset := 0.0
var last_error := ""
## (status: String, why: String)
var on_status := Callable()
## (m: Dictionary, from: String) -> void; while invalid, game messages wait in `inbox`
var on_game := Callable()
var on_peers := Callable()
var on_host_left := Callable()
## [[m, from], ...] game messages nobody has taken yet
var inbox: Array = []
## true while a session wants messages held (e.g. a map reload is about to happen)
var hold := false
## message counters (debug overlay / tests)
var sent := 0
var received := 0
var url := ""

var _ws: WebSocketPeer = null
var _opened := false
var _hello := {}
var _ping_at := 0.0
var _connect_deadline := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


## Where the relay is: --server=<url>, else the Settings override, else the online server.
static func default_server() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			return a.trim_prefix("--server=")
	var s: String = str(Settings.get_v("serverUrl")).strip_edges()
	return s if s != "" else DEFAULT_SERVER


## base url (ws://host:port or wss://host, with or without /ws) -> the room's socket url
static func socket_url(base: String, code: String) -> String:
	var b := base.strip_edges().trim_suffix("/")
	if not (b.begins_with("ws://") or b.begins_with("wss://")):
		b = ("ws://" if b.begins_with("localhost") or b.begins_with("127.") or b.begins_with("192.168.") else "wss://") + b
	if not b.ends_with("/ws"):
		b += "/ws"
	return "%s?room=%s" % [b, code]


## Room codes: letters and digits only, upper case, at most 8.
static func clean_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out.substr(0, 8)


## A fresh 5-letter room code (no 0/O/1/I so it reads out loud easily).
static func new_code() -> String:
	var abc := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s := ""
	for i in 5:
		s += abc[randi() % abc.length()]
	return s


func online() -> bool:
	return status == "online"


## Server clock now (ms), for comparing with snapshot `at` times.
func server_now() -> float:
	return now_ms() + clock_offset


func connect_room(base: String, nm: String, code: String, as_role: String) -> void:
	disconnect_room()
	if base.strip_edges() == "":
		_fail("Online play isn't set up yet: there's no game server. Put the relay online (server/README.md) or type a server address below.")
		return
	room = clean_code(code)
	player_name = nm
	role = as_role
	last_error = ""
	inbox.clear()
	hold = false
	rtt = 0
	clock_offset = 0
	url = socket_url(base, room)
	_hello = {"t": "hello", "v": PROTOCOL_VERSION, "name": nm, "room": room, "role": as_role}
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 21
	_ws.outbound_buffer_size = 1 << 21
	_ws.max_queued_packets = 4096
	_opened = false
	_connect_deadline = now_ms() + 8000
	_set_status("connecting")
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("Can't reach the game server at %s (error %d)." % [base, err])


func disconnect_room() -> void:
	if _ws:
		_ws.close(1000, "bye")
		_ws = null
	_opened = false
	peers.clear()
	host_id = ""
	id = ""
	role = "solo"
	inbox.clear()
	hold = false
	if status != "offline":
		_set_status("offline")


## Send a game message: guests always reach the host; the host reaches `to` or every guest.
func send_game(m: Dictionary, to := "") -> void:
	var env := {"t": "relay", "m": m}
	if to != "":
		env.to = to
	_send(env)


func _send(m: Dictionary) -> void:
	if _ws and _opened and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(m, "", false))
		sent += 1


func _process(_dt: float) -> void:
	if _ws:
		_ws.poll()
		var st := _ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN and not _opened:
			_opened = true
			_send(_hello)
			_ping()
		while _ws and _ws.get_available_packet_count() > 0:
			var txt := _ws.get_packet().get_string_from_utf8()
			var m = JSON.parse_string(txt)
			if m is Dictionary and m.has("t"):
				received += 1
				_handle(m)
		if _ws:
			st = _ws.get_ready_state()
			if st == WebSocketPeer.STATE_OPEN and now_ms() >= _ping_at:
				_ping()
			elif st == WebSocketPeer.STATE_CONNECTING and now_ms() > _connect_deadline:
				_fail("Can't reach the game server (%s). Check your internet connection." % url.split("?")[0])
			elif st == WebSocketPeer.STATE_CLOSED:
				var was_online := id != ""
				_ws = null
				if status == "error":
					pass
				elif was_online:
					_fail("Lost the connection to the game server.")
				else:
					_fail("Can't reach the game server (%s)." % url.split("?")[0])
	_dispatch()


func _ping() -> void:
	_ping_at = now_ms() + 1000
	_send({"t": "ping", "at": now_ms()})


func _dispatch() -> void:
	while inbox.size() and not hold and on_game.is_valid():
		var e: Array = inbox.pop_front()
		on_game.call(e[0], e[1])
	# nobody listening for a while (map loading): old snapshots are useless, keep everything else
	if inbox.size() > 400:
		inbox = inbox.filter(func(e): return e[0].get("g", "") != "snap")


func _handle(m: Dictionary) -> void:
	match m.t:
		"welcome":
			id = m.id
			room = m.room
			role = m.role
			host_id = str(m.get("hostId", ""))
			peers.clear()
			for p in m.peers:
				peers[p.id] = p.name
			_set_status("online")
			if on_peers.is_valid():
				on_peers.call()
		"join":
			peers[m.p.id] = m.p.name
			if on_peers.is_valid():
				on_peers.call()
		"leave":
			peers.erase(m.id)
			if on_peers.is_valid():
				on_peers.call()
		"hostLeft":
			var cb := on_host_left
			_ws = null
			disconnect_room()
			if cb.is_valid():
				cb.call()
		"relay":
			if m.m is Dictionary:
				inbox.append([m.m, str(m.get("from", ""))])
				_dispatch()
		"pong":
			var now := now_ms()
			var r: float = now - float(m.at)
			rtt = rtt * 0.8 + r * 0.2 if rtt > 0 else r
			var off: float = float(m.server) + r / 2 - now
			clock_offset = clock_offset * 0.8 + off * 0.2 if clock_offset != 0 else off
		"error":
			_fail(str(m.get("message", "The game server refused the connection.")))


func _fail(message: String) -> void:
	last_error = message
	if _ws:
		_ws.close()
		_ws = null
	_opened = false
	role = "solo"
	id = ""
	peers.clear()
	inbox.clear()
	_set_status("error", message)


func _set_status(s: String, why := "") -> void:
	status = s
	if on_status.is_valid():
		on_status.call(s, why)
