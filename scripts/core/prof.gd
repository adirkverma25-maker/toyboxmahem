class_name Prof
## Tiny section timer for performance checks (dev only).
static var acc := {}
static var _t := {}


static func begin(k: String) -> void:
	_t[k] = Time.get_ticks_usec()


static func end(k: String) -> void:
	acc[k] = acc.get(k, 0.0) + (Time.get_ticks_usec() - _t.get(k, Time.get_ticks_usec())) / 1000.0


static func report(frames: int) -> String:
	var out := []
	for k in acc:
		out.append("%s %.1f" % [k, acc[k] / maxf(1, frames)])
	acc.clear()
	return ", ".join(out)
