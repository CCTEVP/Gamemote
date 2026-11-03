class_name GmRoutine
extends RefCounted
## Routine compiler (block AST -> bytecode v0), validator and VM.
## The same bytecode runs in the app (Live mode) and on the device (Transferred
## mode). See protocol/PROTOCOL.md section 5.
##
## AST: {"version": 0, "name": "...", "blocks": [block, ...]} where block is one of
##   {"id", "op": "set", "ch", "value"}
##   {"id", "op": "trigger", "action", "params": [int, ...]}
##   {"id", "op": "wait", "ms"}
##   {"id", "op": "repeat", "times", "body": [...]}
##   {"id", "op": "forever", "body": [...]}
##   {"id", "op": "stop_all"}

const HEADER := [0x47, 0x4D, 0x00]  # "GM", version 0

const OP_HALT := 0x00
const OP_SET := 0x01
const OP_TRIGGER := 0x02
const OP_WAIT := 0x03
const OP_LOOP := 0x04
const OP_END_LOOP := 0x05
const OP_STOP_ALL := 0x06

const MAX_INSTRUCTIONS_PER_TICK := 64


## Returns {"ok": true, "program": PackedByteArray, "step_blocks": Array}
## or {"ok": false, "error": String}.
static func compile(ast: Dictionary) -> Dictionary:
	var out := PackedByteArray(HEADER)
	var steps := []
	var err := _emit_list(ast.get("blocks", []), out, steps)
	if err != "":
		return {"ok": false, "error": err}
	out.append(OP_HALT)
	steps.append(null)
	return {"ok": true, "program": out, "step_blocks": steps}


static func _emit_list(blocks: Array, out: PackedByteArray, steps: Array) -> String:
	for b in blocks:
		var err := _emit(b, out, steps)
		if err != "":
			return err
	return ""


static func _emit(b: Dictionary, out: PackedByteArray, steps: Array) -> String:
	var bid = b.get("id")
	match String(b.get("op", "")):
		"set":
			out.append(OP_SET)
			out.append(int(b.ch) & 0xFF)
			GmProtocol._append_s16(out, int(b.value))
			steps.append(bid)
		"trigger":
			var params: Array = b.get("params", [])
			out.append(OP_TRIGGER)
			out.append(int(b.action) & 0xFF)
			out.append(params.size())
			for p in params:
				GmProtocol._append_s16(out, int(p))
			steps.append(bid)
		"wait":
			if int(b.ms) < 0:
				return "wait: negative ms"
			out.append(OP_WAIT)
			GmProtocol._append_u32(out, int(b.ms))
			steps.append(bid)
		"repeat", "forever":
			var count := 0
			if b.op == "repeat":
				count = int(b.times)
				if count < 1 or count > 0xFFFF:
					return "repeat: times must be 1..65535"
			out.append(OP_LOOP)
			GmProtocol._append_u16(out, count)
			steps.append(bid)
			var err := _emit_list(b.get("body", []), out, steps)
			if err != "":
				return err
			out.append(OP_END_LOOP)
			steps.append(bid)
		"stop_all":
			out.append(OP_STOP_ALL)
			steps.append(bid)
		var op:
			return "unknown block op '%s'" % op
	return ""


## Validates and decodes a program. Pass empty arrays to skip id checks.
## Returns {"ok": true, "instrs": [{"op", "args"}...]} or {"ok": false, "error"}.
static func parse(program: PackedByteArray, channel_ids: Array = [], action_ids: Array = [],
		max_loop_depth: int = 4) -> Dictionary:
	if program.size() < 3 or program.slice(0, 3) != PackedByteArray(HEADER):
		return {"ok": false, "error": "bad magic/version"}
	var i := 3
	var instrs := []
	var depth := 0
	var halted := false
	var n := program.size()
	while i < n:
		var op := program[i]
		match op:
			OP_HALT:
				instrs.append({"op": op, "args": []})
				i += 1
				halted = true
				break
			OP_SET:
				if i + 4 > n:
					return _err("truncated SET at %d" % i)
				var ch := program[i + 1]
				if not channel_ids.is_empty() and not channel_ids.has(ch):
					return _err("unknown channel %d" % ch)
				instrs.append({"op": op, "args": [ch, program.decode_s16(i + 2)]})
				i += 4
			OP_TRIGGER:
				if i + 3 > n:
					return _err("truncated TRIGGER at %d" % i)
				var action := program[i + 1]
				var count := program[i + 2]
				if i + 3 + 2 * count > n:
					return _err("truncated TRIGGER at %d" % i)
				if not action_ids.is_empty() and not action_ids.has(action):
					return _err("unknown action %d" % action)
				var params := []
				for k in count:
					params.append(program.decode_s16(i + 3 + 2 * k))
				instrs.append({"op": op, "args": [action, params]})
				i += 3 + 2 * count
			OP_WAIT:
				if i + 5 > n:
					return _err("truncated WAIT at %d" % i)
				instrs.append({"op": op, "args": [program.decode_u32(i + 1)]})
				i += 5
			OP_LOOP:
				if i + 3 > n:
					return _err("truncated LOOP at %d" % i)
				depth += 1
				if depth > max_loop_depth:
					return _err("loop nesting too deep")
				instrs.append({"op": op, "args": [program.decode_u16(i + 1)]})
				i += 3
			OP_END_LOOP:
				depth -= 1
				if depth < 0:
					return _err("END_LOOP without LOOP")
				instrs.append({"op": op, "args": []})
				i += 1
			OP_STOP_ALL:
				instrs.append({"op": op, "args": []})
				i += 1
			_:
				return _err("unknown opcode 0x%02X at %d" % [op, i])
	if not halted or i != n:
		return _err("program must end with a single HALT")
	if depth != 0:
		return _err("unbalanced LOOP/END_LOOP")
	return {"ok": true, "instrs": instrs}


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


## Bytecode interpreter. Time is virtual: WAIT advances `clock_ms`, so timing
## never drifts. Call tick(now_ms) often (every frame).
class VM:
	extends RefCounted

	var instrs: Array
	var on_set: Callable      # func(ch: int, value: int)
	var on_trigger: Callable  # func(action: int, params: Array)
	var on_stop_all: Callable # func()
	var on_step: Callable     # func(step: int), may be invalid
	var pc := 0
	var clock_ms := 0.0
	var running := false
	var finished := false
	var _loops: Array = []  # of [body_start, remaining] (-1 = forever)

	func _init(p_instrs: Array, p_set: Callable, p_trigger: Callable, p_stop_all: Callable,
			p_step: Callable = Callable()) -> void:
		instrs = p_instrs
		on_set = p_set
		on_trigger = p_trigger
		on_stop_all = p_stop_all
		on_step = p_step

	func start(now_ms: float) -> void:
		pc = 0
		_loops.clear()
		clock_ms = now_ms
		running = true
		finished = false

	func stop() -> void:
		running = false

	func tick(now_ms: float) -> void:
		var executed := 0
		while running and executed < MAX_INSTRUCTIONS_PER_TICK:
			if now_ms < clock_ms:
				return
			var ins: Dictionary = instrs[pc]
			if on_step.is_valid():
				on_step.call(pc)
			executed += 1
			var args: Array = ins.args
			match int(ins.op):
				OP_HALT:
					running = false
					finished = true
					return
				OP_SET:
					on_set.call(args[0], args[1])
					pc += 1
				OP_TRIGGER:
					on_trigger.call(args[0], args[1])
					pc += 1
				OP_WAIT:
					clock_ms += args[0]
					pc += 1
				OP_LOOP:
					var count: int = args[0]
					_loops.append([pc + 1, -1 if count == 0 else count])
					pc += 1
				OP_END_LOOP:
					var loop: Array = _loops.back()
					if loop[1] > 0:
						loop[1] -= 1
					if loop[1] != 0:
						pc = loop[0]
					else:
						_loops.pop_back()
						pc += 1
				OP_STOP_ALL:
					on_stop_all.call()
					pc += 1
