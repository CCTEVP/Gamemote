class_name BlockBoard
extends Node3D
## Routine editor on the table: clay blocks snap edge to edge under a "When run" hat.
## Drag a tile out of the palette, drop it near a slot to snap it in. A Repeat block
## wraps the blocks dropped inside it. Tap a block to cycle its value. Drag a block
## back to the palette to delete it. Dragging a block takes the blocks below it along.
##
## The chain compiles to the same AST as the rest of the app (GmRoutine.compile).

signal run_requested(mode: String)   # "live" | "transfer" | "stop"
signal changed

const BLOCK_W := 3.0
const BLOCK_D := 0.52
const BLOCK_H := 0.2
const STEP := 0.62            # z distance between stacked blocks
const INDENT := 0.42          # x indent of a Repeat body
const FOOT := 0.5             # height of a Repeat footer
const SNAP := 0.95            # max distance from a slot to snap
const TAP_MOVE := 0.18
const LIFT := 0.35
const ORIGIN := Vector2(-1.4, -3.3)   # hat block centre (local)
const PALETTE_X := 3.6                # palette column centre (local x)
const PALETTE_TOP := -3.3
const PALETTE_STEP := 0.72
const RUN_Z := 3.55

const WAIT_STEPS := [250, 500, 1000, 2000]
const REPEAT_STEPS := [2, 3, 5, 10]

var info: Dictionary = {}
var chain: Array = []          # top-level block ids, in order
var blocks: Dictionary = {}    # id -> block dict
var _nodes: Dictionary = {}    # id -> {root: Node3D, mesh, label, spine, foot}
var _palette: Array = []       # {proto: Dictionary, center: Vector2, node, label}
var _run_buttons: Array = []   # {mode, center: Vector2, half: Vector2, node}
var _status: Label3D
var _hat: Node3D
var _next_id := 1
var _drag: Dictionary = {}     # active drag (one finger at a time edits blocks)
var _highlight = null


func _ready() -> void:
	_hat = _make_shape(Clay.BUTTER, "When run")
	_hat.position = Vector3(ORIGIN.x, 0, ORIGIN.y)
	_build_run_buttons()
	_status = Clay.label("", 30, Clay.INK, 0.02)
	_status.position = Vector3(ORIGIN.x, 0.02, RUN_Z + 0.62)
	add_child(_status)
	set_info({})


# ------------------------------------------------------------------ setup

## Rebuilds the palette from the device's capability descriptor.
func set_info(p_info: Dictionary) -> void:
	info = p_info
	for t in _palette:
		t.node.queue_free()
	_palette.clear()
	var protos: Array = []
	for c in info.get("channels", []):
		protos.append({"op": "set", "ch": int(c.id), "value": int(c.max)})
	for a in info.get("actions", []):
		var params := []
		for p in a.get("params", []):
			params.append(int(p.get("default", p.get("min", 0))))
		protos.append({"op": "trigger", "action": int(a.id), "params": params})
	protos.append({"op": "wait", "ms": 500})
	protos.append({"op": "repeat", "times": 3, "body": []})
	for i in protos.size():
		var proto: Dictionary = protos[i]
		var node := _make_shape(_color(proto.op), _text(proto), 2.5)
		var center := Vector2(PALETTE_X, PALETTE_TOP + i * PALETTE_STEP)
		node.position = Vector3(center.x, 0, center.y)
		_palette.append({"proto": proto, "center": center, "node": node})
	_relayout()


func _build_run_buttons() -> void:
	var specs := [["live", "▶ Live", Clay.MINT], ["transfer", "⇪ Transfer", Clay.SKY], ["stop", "■ Stop", Clay.PEACH]]
	for i in specs.size():
		var node := Node3D.new()
		var center := Vector2(ORIGIN.x - 0.95 + i * 1.65, RUN_Z)
		node.position = Vector3(center.x, 0, center.y)
		add_child(node)
		var mesh := Clay.pill(1.5, 0.62, 0.26, specs[i][2])
		node.add_child(mesh)
		var lbl := Clay.label(specs[i][1], 30, Clay.INK, 0.28)
		node.add_child(lbl)
		_run_buttons.append({"mode": specs[i][0], "center": center, "half": Vector2(0.75, 0.31),
				"node": node, "mesh": mesh, "y": 0.0, "vel": 0.0, "pressed": false})


func set_run_enabled(live: bool, transfer: bool, stop: bool) -> void:
	var flags := {"live": live, "transfer": transfer, "stop": stop}
	for b in _run_buttons:
		b.enabled = flags[b.mode]
		var base: Color = {"live": Clay.MINT, "transfer": Clay.SKY, "stop": Clay.PEACH}[b.mode]
		Clay.set_color(b.mesh, base if b.enabled else Clay.DISABLED)


func set_status(text: String) -> void:
	_status.text = text


# ------------------------------------------------------------------ block model

func _color(op: String) -> Color:
	return {"set": Clay.SKY, "trigger": Clay.PINK, "wait": Clay.PEACH, "repeat": Clay.MINT}.get(op, Clay.GRAPE)


func _channel(ch: int) -> Dictionary:
	for c in info.get("channels", []):
		if int(c.id) == ch:
			return c
	return {"name": "ch%d" % ch, "min": 0, "max": 255, "neutral": 0}


func _action(id: int) -> Dictionary:
	for a in info.get("actions", []):
		if int(a.id) == id:
			return a
	return {"name": "action %d" % id}


func _text(b: Dictionary) -> String:
	match b.op:
		"set":
			return "Set %s  %d" % [_channel(b.ch).name, b.value]
		"trigger":
			return String(_action(b.action).name)
		"wait":
			return "Wait %s s" % str(b.ms / 1000.0)
		"repeat":
			return "Repeat %d×" % b.times
	return b.op


## Tap: cycle the block's value.
func _cycle(b: Dictionary) -> void:
	match b.op:
		"set":
			var c := _channel(b.ch)
			var options := [int(c.min), int(c.neutral), int(c.max)]
			b.value = options[(options.find(b.value) + 1) % options.size()]
		"wait":
			b.ms = WAIT_STEPS[(WAIT_STEPS.find(b.ms) + 1) % WAIT_STEPS.size()]
		"repeat":
			b.times = REPEAT_STEPS[(REPEAT_STEPS.find(b.times) + 1) % REPEAT_STEPS.size()]
	if _nodes.has(b.id):
		_nodes[b.id].label.text = _text(b)
	changed.emit()


func _new_block(proto: Dictionary) -> String:
	var b := proto.duplicate(true)
	b.id = "k%d" % _next_id
	_next_id += 1
	blocks[b.id] = b
	var node := _make_shape(_color(b.op), _text(b))
	_nodes[b.id] = {"root": node, "mesh": node.get_child(0), "label": node.get_child(1), "spine": null, "foot": null}
	if b.op == "repeat":
		var spine := Clay.pill(0.5, 0.3, BLOCK_H, _color("repeat"))
		node.add_child(spine)
		var foot := Clay.pill(BLOCK_W * 0.55, 0.3, BLOCK_H, _color("repeat"))
		node.add_child(foot)
		_nodes[b.id].spine = spine
		_nodes[b.id].foot = foot
	return b.id


func _make_shape(color: Color, text: String, width: float = BLOCK_W) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.add_child(Clay.pill(width, BLOCK_D, BLOCK_H, color))
	var lbl := Clay.label(text, 34, Clay.INK, BLOCK_H + 0.02)
	root.add_child(lbl)
	return root


func _delete(ids: Array) -> void:
	for id in ids:
		var b: Dictionary = blocks[id]
		if b.op == "repeat":
			_delete(b.body)
		_nodes[id].root.queue_free()
		_nodes.erase(id)
		blocks.erase(id)


## The AST for GmRoutine.compile.
func to_ast() -> Dictionary:
	return {"version": 0, "name": "Table routine", "blocks": _ast_list(chain)}


func _ast_list(ids: Array) -> Array:
	var out := []
	for id in ids:
		var b: Dictionary = blocks[id]
		match b.op:
			"set": out.append({"id": id, "op": "set", "ch": b.ch, "value": b.value})
			"trigger": out.append({"id": id, "op": "trigger", "action": b.action, "params": b.params})
			"wait": out.append({"id": id, "op": "wait", "ms": b.ms})
			"repeat": out.append({"id": id, "op": "repeat", "times": b.times, "body": _ast_list(b.body)})
	return out


func is_empty() -> bool:
	return chain.is_empty()


# ------------------------------------------------------------------ layout

var _slots: Array = []   # {list: Array (by reference), index: int, pos: Vector2}


func _relayout() -> void:
	_slots.clear()
	_layout_list(chain, ORIGIN.x, ORIGIN.y + STEP)


## Places a list of blocks top-down; returns the z after the last one.
func _layout_list(ids: Array, x: float, z: float) -> float:
	for i in ids.size():
		_slots.append({"list": ids, "index": i, "pos": Vector2(x, z)})
		var id: String = ids[i]
		var n: Dictionary = _nodes[id]
		n.root.position = Vector3(x, 0, z)
		var b: Dictionary = blocks[id]
		if b.op == "repeat":
			var body_top := z + STEP
			var end := _layout_list(b.body, x + INDENT, body_top)
			var inner := maxf(end - body_top, STEP * 0.6)
			# Spine on the left, from header to footer; footer closes the C.
			var spine: MeshInstance3D = n.spine
			spine.basis = Basis.from_euler(Vector3(0, PI / 2, 0)) * Basis(Vector3(0, 0, 1), PI / 2) \
					* Basis.from_scale(Vector3(BLOCK_H / 0.3, 1, 1))
			(spine.mesh as CapsuleMesh).height = inner + STEP
			spine.position = Vector3(-BLOCK_W * 0.5 + 0.15, BLOCK_H * 0.5, (inner + STEP) * 0.5)
			var foot: MeshInstance3D = n.foot
			foot.position = Vector3(-BLOCK_W * 0.5 + BLOCK_W * 0.275, BLOCK_H * 0.5, STEP + inner)
			z = body_top + inner + FOOT
		else:
			z += STEP
	_slots.append({"list": ids, "index": ids.size(), "pos": Vector2(x, z)})
	return z


# ------------------------------------------------------------------ touch routing

func _local(p: Vector3) -> Vector2:
	var l := to_local(p)
	return Vector2(l.x, l.z)


func _hit_rect(q: Vector2, center: Vector2, half: Vector2) -> bool:
	return absf(q.x - center.x) <= half.x and absf(q.y - center.y) <= half.y


## Finds the block under q (deepest first), returning [list, index] or [].
func _find(q: Vector2, ids: Array) -> Array:
	for i in ids.size():
		var b: Dictionary = blocks[ids[i]]
		if b.op == "repeat":
			var inner := _find(q, b.body)
			if not inner.is_empty():
				return inner
		var pos: Vector3 = _nodes[ids[i]].root.position
		if _hit_rect(q, Vector2(pos.x, pos.z), Vector2(BLOCK_W * 0.5, BLOCK_D * 0.6)):
			return [ids, i]
	return []


func try_press(index: int, p: Vector3) -> bool:
	if not _drag.is_empty():
		return false
	var q := _local(p)
	for rb in _run_buttons:
		if rb.get("enabled", true) and _hit_rect(q, rb.center, rb.half):
			rb.pressed = true
			_drag = {"touch": index, "kind": "button", "button": rb}
			return true
	for t in _palette:
		if _hit_rect(q, t.center, Vector2(1.25, BLOCK_D * 0.6)):
			var id := _new_block(t.proto)
			_start_drag(index, [id], q, Vector2(t.center.x, t.center.y), true, [], -1)
			return true
	var hit := _find(q, chain)
	if not hit.is_empty():
		var list: Array = hit[0]
		var i: int = hit[1]
		var group := list.slice(i)
		var top: Vector3 = _nodes[group[0]].root.position
		list.resize(i)
		_relayout()
		_start_drag(index, group, q, Vector2(top.x, top.z), false, list, i)
		return true
	return false


func _start_drag(index: int, group: Array, q: Vector2, top: Vector2, is_new: bool,
		origin_list: Array, origin_index: int) -> void:
	_drag = {"touch": index, "kind": "blocks", "group": group, "offset": top - q, "start": q,
			"moved": false, "new": is_new, "origin_list": origin_list, "origin_index": origin_index}
	_place_group(top, LIFT)


func _place_group(top: Vector2, lift: float) -> void:
	var saved := _slots
	_slots = []
	_layout_list(_drag.group, top.x, top.y)
	_slots = saved
	for id in _all_ids(_drag.group):
		_nodes[id].root.position.y = lift


func _all_ids(ids: Array) -> Array:
	var out := []
	for id in ids:
		out.append(id)
		if blocks[id].op == "repeat":
			out.append_array(_all_ids(blocks[id].body))
	return out


func move(index: int, p: Vector3) -> bool:
	if _drag.is_empty() or _drag.touch != index:
		return false
	if _drag.kind == "blocks":
		var q := _local(p)
		if q.distance_to(_drag.start) > TAP_MOVE:
			_drag.moved = true
		_place_group(q + _drag.offset, LIFT)
	return true


func release(index: int, p: Vector3 = Vector3.INF) -> bool:
	if _drag.is_empty() or _drag.touch != index:
		return false
	var d := _drag
	_drag = {}
	if d.kind == "button":
		d.button.pressed = false
		run_requested.emit(d.button.mode)
		return true
	var q: Vector2 = d.start if p == Vector3.INF else _local(p)
	var top: Vector2 = q + d.offset
	var group: Array = d.group
	if not d.moved and not d.new:
		# Tap: put it back and cycle its value.
		_insert(d.origin_list, d.origin_index, group)
		_cycle(blocks[group[0]])
		return true
	if top.x > PALETTE_X - 1.6:
		_delete(group)      # dropped on the palette: delete
	else:
		var slot := _nearest_slot(top)
		if not slot.is_empty():
			_insert(slot.list, slot.index, group)
		elif d.new:
			_delete(group)
		else:
			_insert(d.origin_list, d.origin_index, group)
	_relayout()
	changed.emit()
	return true


func _insert(list: Array, at: int, group: Array) -> void:
	for k in group.size():
		list.insert(at + k, group[k])
	for id in _all_ids(group):
		_nodes[id].root.position.y = 0.0
	_relayout()


func _nearest_slot(top: Vector2) -> Dictionary:
	_relayout()
	var best := {}
	var best_d := SNAP
	for s in _slots:
		var dist: float = (s.pos as Vector2).distance_to(top)
		if dist < best_d:
			best_d = dist
			best = s
	return best


## Drops into a slot programmatically (tests, defaults): appends a new block built from `proto`
## to `parent_id`'s body (or the top-level chain when empty). Returns the new id.
func add_block(proto: Dictionary, parent_id: String = "") -> String:
	var id := _new_block(proto)
	var list: Array = chain if parent_id == "" else blocks[parent_id].body
	list.append(id)
	_relayout()
	changed.emit()
	return id


func block_center_world(id: String) -> Vector3:
	return to_global(_nodes[id].root.position + Vector3(0, BLOCK_H, 0))


func palette_center_world(i: int) -> Vector3:
	var c: Vector2 = _palette[i].center
	return to_global(Vector3(c.x, BLOCK_H, c.y))


func run_button_world(mode: String) -> Vector3:
	for rb in _run_buttons:
		if rb.mode == mode:
			return to_global(Vector3(rb.center.x, 0.3, rb.center.y))
	return Vector3.ZERO


func slot_world(list_owner: String, index: int) -> Vector3:
	_relayout()
	var list: Array = chain if list_owner == "" else blocks[list_owner].body
	for s in _slots:
		if is_same(s.list, list) and s.index == index:
			return to_global(Vector3(s.pos.x, 0, s.pos.y))
	return Vector3.ZERO


# ------------------------------------------------------------------ running

func set_highlight(block_id) -> void:
	if _highlight != null and _nodes.has(_highlight):
		Clay.set_glow(_nodes[_highlight].mesh, false)
	_highlight = block_id
	if block_id != null and _nodes.has(block_id):
		Clay.set_glow(_nodes[block_id].mesh, true)


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	for rb in _run_buttons:
		var s := Clay.spring(rb.y, rb.vel, -0.08 if rb.pressed else 0.0, delta)
		rb.y = s.x
		rb.vel = s.y
		rb.node.position.y = rb.y
