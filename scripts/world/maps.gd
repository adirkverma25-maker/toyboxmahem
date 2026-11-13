class_name Maps
## The three maps: builder, background life, jump pads + ziplines, objective spots, sky.

const MAP_ORDER := ["bedroom", "backyard", "toycity"]


static func get_map(id: String) -> Dictionary:
	match id:
		"backyard":
			return {
				"id": "backyard", "name": "Sandbox Showdown",
				"blurb": "A sunny backyard: sand castle in the middle, picnic table, back porch, kiddie pool, flower garden, dump truck, and a play tower with a slide.",
				"loading": "Mowing the lawn",
				"build": ArenaBackyard.build,
				"ambient": func(_arena, _phys, _fx, _audio): return YardAmbient.new(),
				"pads": ArenaBackyard.PADS, "zips": ArenaBackyard.ZIPS,
				"hillSites": ArenaBackyard.HILL_SITES.duplicate(true), "sectors": ArenaBackyard.sectors(), "homes": ArenaBackyard.HOMES.duplicate(),
				"highY": 6.4, "blockDrops": false,
				"sky": {"background": "#8fd0ff", "fog": ["#bfe6ff", 120.0, 420.0], "env": 0.5, "exposure": 0.8, "hemi": ["#cfe9ff", "#6f9b52", 0.85]},
				"menuCam": {"r": 22.0, "h": 12.0},
				"ffaIntro": "Seven toys start up high: on the picnic table, the porch and the play tower.",
			}
		"toycity":
			return {
				"id": "toycity", "name": "Toy City",
				"blurb": "New. A model city on a hobby table: five rooftops linked by ziplines, jump pads up from the streets, a fountain plaza, a park, a market square and a model railway round the edge.",
				"loading": "Painting the model city",
				"build": ArenaToyCity.build,
				"ambient": func(_arena, _phys, _fx, audio): return ToyCityAmbient.new(audio),
				"pads": ArenaToyCity.PADS, "zips": ArenaToyCity.ZIPS,
				"hillSites": ArenaToyCity.HILL_SITES.duplicate(true), "sectors": ArenaToyCity.sectors(), "homes": ArenaToyCity.HOMES.duplicate(),
				"highY": 8.0, "blockDrops": false,
				"sky": {"background": "#e9dcc6", "fog": ["#e9dcc6", 110.0, 300.0], "env": 0.5, "exposure": 0.95, "hemi": ["#fff4e0", "#9a7b5a", 0.9]},
				"menuCam": {"r": 33.0, "h": 34.0},
				"ffaIntro": "Seven toys start up on the rooftops. Jump pads and ziplines get you up there.",
			}
	return {
		"id": "bedroom", "name": "Bedroom Brawl",
		"blurb": "The original kid's bedroom: bed fortress, desk, closet maze, and a high shelf with a toy train.",
		"loading": "Building the bedroom",
		"build": ArenaBedroom.build,
		"ambient": func(arena, phys, fx, audio): return AmbientBedroom.new(arena, phys, fx, audio),
		"pads": ArenaBedroom.PADS, "zips": ArenaBedroom.ZIPS,
		"hillSites": _bedroom_sites(), "sectors": _bedroom_sectors(), "homes": [0, 2, 4],
		"highY": 20.0, "blockDrops": true,
		"sky": {"background": "#f2e2cc", "fog": ["#f1dfc6", 70.0, 190.0], "env": 0.42, "exposure": 0.98, "hemi": ["#fff1dc", "#7a5a3e", 0.62]},
		"menuCam": {"r": 18.0, "h": 9.0},
		"ffaIntro": "Seven toys are up on the shelves. Jump pads and ziplines lead up there.",
	}


static func _bedroom_sites() -> Array:
	return [
		{"name": "the Play Rug", "pos": Vector3(2, 0, 1), "radius": 5.2, "height": 6.0},
		{"name": "the Bed Fortress", "pos": Vector3(-25.5, 6, -21), "radius": 4.6, "height": 4.0},
		{"name": "the Toy Garage deck", "pos": Vector3(27.5, 4, 30), "radius": 4.2, "height": 4.0},
		{"name": "the Desk Outpost", "pos": Vector3(20.5, 8, -28.5), "radius": 4.6, "height": 4.5},
		{"name": "Dinosaur Kingdom", "pos": Vector3(-15, 0, 26.5), "radius": 5.0, "height": 5.0},
		{"name": "the Brick District", "pos": Vector3(-22, 0.3, 1.5), "radius": 4.6, "height": 5.0},
		{"name": "the Closet Maze", "pos": Vector3(25.5, 0, -3.8), "radius": 4.2, "height": 4.0},
	]


static func _bedroom_sectors() -> Array:
	var h := _bedroom_sites()
	return [
		Modes.sector(h[1], "B", "Bed"), Modes.sector(h[3], "D", "Desk"), Modes.sector(h[6], "C", "Closet"),
		Modes.sector(h[2], "G", "Garage"), Modes.sector(h[4], "K", "Dino"), Modes.sector(h[5], "R", "Bricks"),
	]


## The map chosen in the menu (maps are built once per load; changing it rebuilds the world).
static func selected() -> Dictionary:
	var id: String = Settings.get_v("map")
	return get_map(id if MAP_ORDER.has(id) else "bedroom")
