class_name Clay
extends RefCounted
## Soft-toy / clay look: matte pastel materials, rounded pills and discs, flat labels.
## Every shape lies on the table (XZ plane), seen from above.

const TABLE := Color("e8ddcf")
const SHADOW_TINT := Color("c9b9a6")
const INK := Color("4a3f55")
const PAD := Color("b9a7e6")       # lavender gamepad body
const PAD_DARK := Color("8f7cc4")
const STICK := Color("6f62a6")
const MINT := Color("9fdcc2")
const PEACH := Color("ffc4a3")
const SKY := Color("a8d3f5")
const PINK := Color("f5b3cf")
const STOP := Color("f0736d")
const BUTTER := Color("ffe08a")
const GRAPE := Color("c7b3f2")
const DISABLED := Color("d8d2cb")

## Pixel size of Label3D text (world units per font pixel).
const TEXT_PIXEL := 0.008


static func mat(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	# No specular highlight and no rim: clay is matte, and both blow out under a sun.
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.metallic_specular = 0.0
	return m


## A pill lying along X: `length` (x) by `depth` (z), `thickness` tall (y), resting on y = 0.
static func pill(length: float, depth: float, thickness: float, color: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = depth * 0.5
	mesh.height = maxf(length, depth)
	mesh.radial_segments = 24
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	# Capsule axis is local Y: turn it to world X, then flatten the world-Y thickness (local X).
	mi.basis = Basis(Vector3(0, 0, 1), PI / 2) * Basis.from_scale(Vector3(thickness / depth, 1, 1))
	mi.position.y = thickness * 0.5
	return mi


## A flat rounded disc (button cap), resting on y = 0.
static func disc(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.92
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position.y = height * 0.5
	return mi


## A soft dome (stick knob top, button bulge), resting on y = 0.
static func dome(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height * 2.0
	mesh.is_hemisphere = true
	mesh.radial_segments = 32
	mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	return mi


## Text lying flat on a surface at height `y`, readable from above.
static func label(text: String, font_size: int = 40, color: Color = INK, y: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = TEXT_PIXEL
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.rotation.x = -PI / 2
	l.position.y = y
	return l


static func set_color(mi: MeshInstance3D, color: Color) -> void:
	(mi.material_override as StandardMaterial3D).albedo_color = color


static func set_glow(mi: MeshInstance3D, on: bool, color: Color = Color("fff3b0")) -> void:
	var m := mi.material_override as StandardMaterial3D
	m.emission_enabled = on
	m.emission = color
	m.emission_energy_multiplier = 0.3


## Critically-ish damped spring step (a little overshoot reads as "squishy toy").
static func spring(pos: float, vel: float, target: float, delta: float,
		stiffness: float = 520.0, damping: float = 22.0) -> Vector2:
	vel += (target - pos) * stiffness * delta
	vel *= exp(-damping * delta)
	pos += vel * delta
	return Vector2(pos, vel)
