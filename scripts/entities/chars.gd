class_name Chars
## Character definitions (the data half of src/entities/ToyModels.ts). Variants reuse another toy's body
## (`base`) with new paint (`recolor`: old hex -> new hex).

const CHARACTERS := {
	"captainClick": {"id": "captainClick", "name": "Captain Click", "colors": ["#5b7a3a", "#7c9a52", "#3e5527", "#c9b27c"], "accent": "#8fbf5a", "hitbox": {"headY": 1.56, "headR": 0.27, "bodyBottom": 0.15, "bodyTop": 1.3, "bodyR": 0.36}, "voicePitch": 0.9},
	"rexRampage": {"id": "rexRampage", "name": "Rex Rampage", "colors": ["#3fae49", "#f4a261", "#2d6a4f", "#ffffff"], "accent": "#5cd65c", "hitbox": {"headY": 1.58, "headR": 0.32, "bodyBottom": 0.15, "bodyTop": 1.3, "bodyR": 0.4}, "voicePitch": 0.7},
	"boltBuddy": {"id": "boltBuddy", "name": "Bolt Buddy", "colors": ["#b8c4d6", "#3a86ff", "#e0e7ff", "#ffbe0b"], "accent": "#5aa9ff", "hitbox": {"headY": 1.55, "headR": 0.28, "bodyBottom": 0.15, "bodyTop": 1.28, "bodyR": 0.36}, "voicePitch": 1.4},
	"princessPanic": {"id": "princessPanic", "name": "Princess Panic", "colors": ["#ff70a6", "#c77dff", "#ffd670", "#ffffff"], "accent": "#ff8fc7", "hitbox": {"headY": 1.55, "headR": 0.27, "bodyBottom": 0.15, "bodyTop": 1.28, "bodyR": 0.36}, "voicePitch": 1.5},
	"turboTim": {"id": "turboTim", "name": "Turbo Tim", "colors": ["#e63946", "#ffffff", "#1d3557", "#ffd166"], "accent": "#ff5c5c", "hitbox": {"headY": 1.56, "headR": 0.28, "bodyBottom": 0.15, "bodyTop": 1.28, "bodyR": 0.35}, "voicePitch": 1.15},
	"mechaMax": {"id": "mechaMax", "name": "Mecha Max", "colors": ["#4a4e69", "#ffb703", "#22223b", "#9a8c98"], "accent": "#ffc23d", "hitbox": {"headY": 1.58, "headR": 0.28, "bodyBottom": 0.15, "bodyTop": 1.32, "bodyR": 0.42}, "voicePitch": 0.6},
	"blockhead": {"id": "blockhead", "name": "Blockhead", "colors": ["#d6342c", "#f2c12e", "#1f6fd1", "#2f9e44"], "accent": "#ff9f1c", "hitbox": {"headY": 1.56, "headR": 0.3, "bodyBottom": 0.15, "bodyTop": 1.3, "bodyR": 0.38}, "voicePitch": 1.0},
	"sergeantSnap": {"id": "sergeantSnap", "name": "Sergeant Snap", "base": "captainClick", "recolor": {"#5b7a3a": "#c2a36b", "#3e5527": "#7a5c33", "#c9b27c": "#3b3024"}, "colors": ["#c2a36b", "#7a5c33", "#3b3024", "#ffd8b5"], "accent": "#e7c98a", "hitbox": {"headY": 1.56, "headR": 0.27, "bodyBottom": 0.15, "bodyTop": 1.3, "bodyR": 0.36}, "voicePitch": 0.8},
	"dinaMite": {"id": "dinaMite", "name": "Dina-Mite", "base": "rexRampage", "recolor": {"#3fae49": "#9b5de5", "#f4c27a": "#fee440", "#f77f00": "#00f5d4", "#2d6a4f": "#5a189a", "#1b4332": "#240046"}, "colors": ["#9b5de5", "#fee440", "#5a189a", "#00f5d4"], "accent": "#c39bff", "hitbox": {"headY": 1.58, "headR": 0.32, "bodyBottom": 0.15, "bodyTop": 1.3, "bodyR": 0.4}, "voicePitch": 0.85},
	"sparky": {"id": "sparky", "name": "Sparky", "base": "boltBuddy", "recolor": {"#b8c4d6": "#ffd60a", "#3a86ff": "#ff006e"}, "colors": ["#ffd60a", "#ff006e", "#fff3b0", "#3a86ff"], "accent": "#ffe14d", "hitbox": {"headY": 1.55, "headR": 0.28, "bodyBottom": 0.15, "bodyTop": 1.28, "bodyR": 0.36}, "voicePitch": 1.6},
	"duchessDazzle": {"id": "duchessDazzle", "name": "Duchess Dazzle", "base": "princessPanic", "recolor": {"#ff70a6": "#2ec4b6", "#c77dff": "#3a0ca3", "#7b2cbf": "#f4a261", "#9d4edd": "#4361ee"}, "colors": ["#2ec4b6", "#3a0ca3", "#f4a261", "#ffd670"], "accent": "#5ef0e0", "hitbox": {"headY": 1.55, "headR": 0.27, "bodyBottom": 0.15, "bodyTop": 1.28, "bodyR": 0.36}, "voicePitch": 1.35},
	"nitroNina": {"id": "nitroNina", "name": "Nitro Nina", "base": "turboTim", "recolor": {"#e63946": "#2dc653", "#1d3557": "#3c096c"}, "colors": ["#2dc653", "#ffffff", "#3c096c", "#ffd166"], "accent": "#4dff88", "hitbox": {"headY": 1.56, "headR": 0.28, "bodyBottom": 0.15, "bodyTop": 1.28, "bodyR": 0.35}, "voicePitch": 1.3},
	"gearboxGus": {"id": "gearboxGus", "name": "Gearbox Gus", "base": "mechaMax", "recolor": {"#4a4e69": "#9d0208", "#ffb703": "#e9ecef", "#22223b": "#370617", "#ff4d6d": "#4dd6ff"}, "colors": ["#9d0208", "#e9ecef", "#370617", "#4dd6ff"], "accent": "#ff6b6b", "hitbox": {"headY": 1.58, "headR": 0.28, "bodyBottom": 0.15, "bodyTop": 1.32, "bodyR": 0.42}, "voicePitch": 0.55},
	"brickette": {"id": "brickette", "name": "Brickette", "base": "blockhead", "recolor": {"#d6342c": "#2f9e44", "#1f6fd1": "#ff922b", "#f2c12e": "#e64980"}, "colors": ["#2f9e44", "#ff922b", "#e64980", "#ffffff"], "accent": "#69db7c", "hitbox": {"headY": 1.56, "headR": 0.3, "bodyBottom": 0.15, "bodyTop": 1.3, "bodyR": 0.38}, "voicePitch": 1.2},
	"player": {"id": "player", "name": "You", "colors": ["#1fb5ad", "#ff8c1a", "#ffffff", "#ffd23f"], "accent": "#ffd23f", "hitbox": {"headY": 1.56, "headR": 0.27, "bodyBottom": 0.15, "bodyTop": 1.3, "bodyR": 0.36}, "voicePitch": 1.0},
}

## The original seven
const BOT_ROSTER := ["captainClick", "rexRampage", "boltBuddy", "princessPanic", "turboTim", "mechaMax", "blockhead"]
## The seven newcomers (in Free-for-All they start on the high shelves)
const SHELF_ROSTER := ["sergeantSnap", "dinaMite", "sparky", "duchessDazzle", "nitroNina", "gearboxGus", "brickette"]
const ALL_BOTS := ["captainClick", "rexRampage", "boltBuddy", "princessPanic", "turboTim", "mechaMax", "blockhead",
	"sergeantSnap", "dinaMite", "sparky", "duchessDazzle", "nitroNina", "gearboxGus", "brickette"]
