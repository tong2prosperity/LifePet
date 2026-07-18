extends Node2D

const BONE_COUNT := 6
const SEGMENT_LENGTH := 48.0
const ROOT_POSITION := Vector2(480, 548)
const LEAF_COLOR := Color("20937a")
const VEIN_COLOR := Color("fbfcfc")

var flexibility := 0.68
var damping := 0.64
var wind_strength := 0.55
var gustiness := 0.35
var wind_direction := -1.0

var elapsed := 0.0
var gust_impulse := 0.0
var drag_target: Variant = null
var angles: Array[float] = []
var velocities: Array[float] = []
var bones: Array[Bone2D] = []
var skeleton: Skeleton2D
var status_label: Label


func _ready() -> void:
	for index in range(BONE_COUNT):
		angles.append(0.0)
		velocities.append(0.0)
	_build_skeleton()
	_build_controls()
	queue_redraw()


func _build_skeleton() -> void:
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	skeleton.position = ROOT_POSITION

	var parent: Node = skeleton
	for index in range(BONE_COUNT):
		var bone := Bone2D.new()
		bone.name = "Bone_%02d" % index
		bone.set_autocalculate_length_and_angle(false)
		bone.length = SEGMENT_LENGTH
		bone.position = Vector2.ZERO if index == 0 else Vector2(0, -SEGMENT_LENGTH)
		bone.rest = bone.transform
		parent.add_child(bone)
		bones.append(bone)
		parent = bone
	add_child(skeleton)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(288, 0)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Pibo · 六节草叶骨骼"
	title.add_theme_font_size_override("font_size", 21)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "实时弹簧骨骼参数（Space 触发阵风）"
	subtitle.modulate = Color(0.28, 0.42, 0.37)
	box.add_child(subtitle)

	_add_slider(box, "柔韧度", 0.0, 1.0, 0.01, flexibility, func(value: float) -> void: flexibility = value)
	_add_slider(box, "阻尼", 0.0, 1.0, 0.01, damping, func(value: float) -> void: damping = value)
	_add_slider(box, "风力", 0.0, 1.5, 0.01, wind_strength, func(value: float) -> void: wind_strength = value)
	_add_slider(box, "阵风", 0.0, 1.5, 0.01, gustiness, func(value: float) -> void: gustiness = value)
	_add_slider(box, "风向", -1.0, 1.0, 0.05, wind_direction, func(value: float) -> void: wind_direction = value)

	var gust_button := Button.new()
	gust_button.text = "触发阵风 / 回弹"
	gust_button.pressed.connect(trigger_gust)
	box.add_child(gust_button)

	status_label = Label.new()
	status_label.text = "叶根固定 · 叶尖柔软"
	status_label.modulate = Color(0.28, 0.42, 0.37)
	box.add_child(status_label)


func _add_slider(
	parent: VBoxContainer,
	title: String,
	minimum: float,
	maximum: float,
	step: float,
	initial: float,
	callback: Callable
) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(58, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(callback)
	row.add_child(slider)
	var output := Label.new()
	output.text = "%.2f" % initial
	output.custom_minimum_size = Vector2(42, 0)
	output.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(output)
	slider.value_changed.connect(func(value: float) -> void: output.text = "%.2f" % value)


func _process(delta: float) -> void:
	elapsed += delta
	var dt: float = min(max(delta, 0.0), 1.0 / 30.0)
	gust_impulse = move_toward(gust_impulse, 0.0, dt * 1.65)

	for index in range(BONE_COUNT):
		var progress := float(index + 1) / float(BONE_COUNT)
		var influence := pow(progress, 1.18)
		var phase := float(index) * 0.115
		var idle := sin(elapsed * 1.18 - phase) * 0.020
		var response := 0.62 + flexibility * 0.62
		var steady := wind_direction * wind_strength * response * (
			0.075 + sin(elapsed * 1.02 - phase) * 0.060
		)
		var gust := wind_direction * wind_strength * gustiness * response * (
			sin(elapsed * 0.31 + 1.7) * sin(elapsed * 1.91 - phase * 1.6) * 0.105
		)
		var interaction := 0.0 if drag_target == null else float(drag_target) * influence
		var target := (idle + steady + gust + gust_impulse) * influence + interaction

		var stiffness: float = max(
			10.0,
			(58.0 - flexibility * 15.0) - float(index) * (4.2 + flexibility * 1.8)
		)
		var damping_ratio := (0.92 - damping * 0.42) - float(index) * 0.018
		var damping_force := 2.0 * sqrt(stiffness) * damping_ratio
		velocities[index] += (
			(target - angles[index]) * stiffness - velocities[index] * damping_force
		) * dt
		angles[index] += velocities[index] * dt
		var maximum := PI * 0.24 * (0.45 + flexibility * 0.55)
		angles[index] = clamp(angles[index], -maximum, maximum)

	for index in range(BONE_COUNT):
		bones[index].rotation = angles[index] if index == 0 else angles[index] - angles[index - 1]

	status_label.text = "叶尖角度 %+.1f° · Space 阵风 · 拖动叶片" % rad_to_deg(angles[BONE_COUNT - 1])
	queue_redraw()


func _draw() -> void:
	var centers: Array[Vector2] = [ROOT_POSITION]
	for angle in angles:
		centers.append(centers[-1] + Vector2(sin(angle), -cos(angle)) * SEGMENT_LENGTH)

	var widths := [8.0, 15.0, 23.0, 28.0, 24.0, 14.0, 2.5]
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	for index in range(centers.size()):
		var angle := 0.0 if index == 0 else angles[index - 1]
		var normal := Vector2(cos(angle), sin(angle))
		left.append(centers[index] - normal * widths[index])
		right.append(centers[index] + normal * widths[index])
	right.reverse()
	var outline := left.duplicate()
	outline.append_array(right)
	draw_colored_polygon(PackedVector2Array(outline), LEAF_COLOR)
	draw_polyline(PackedVector2Array(centers), VEIN_COLOR, 3.0, true)

	# Bone debug overlay makes the propagation and fixed root explicit.
	for index in range(BONE_COUNT):
		draw_line(centers[index], centers[index + 1], Color(0.05, 0.24, 0.20, 0.34), 1.5)
		draw_circle(centers[index], 3.2, Color(0.05, 0.24, 0.20, 0.58))
	draw_circle(centers[-1], 3.2, Color(0.05, 0.24, 0.20, 0.58))
	draw_circle(ROOT_POSITION, 7.0, Color("ff625f"))


func trigger_gust() -> void:
	gust_impulse = wind_direction * (0.18 + gustiness * 0.14)
	for index in range(BONE_COUNT):
		velocities[index] += gust_impulse * float(index + 1) * 0.72


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			trigger_gust()
		elif event.keycode == KEY_R:
			angles.fill(0.0)
			velocities.fill(0.0)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.distance_to(_tip_position()) < 90.0:
			drag_target = 0.0
		elif not event.pressed and drag_target != null:
			var release := float(drag_target)
			drag_target = null
			for index in range(BONE_COUNT):
				velocities[index] -= release * float(index + 1) * 0.95
	if event is InputEventMouseMotion and drag_target != null:
		drag_target = clamp((event.position.x - ROOT_POSITION.x) / 260.0, -0.62, 0.62)


func _tip_position() -> Vector2:
	var point := ROOT_POSITION
	for angle in angles:
		point += Vector2(sin(angle), -cos(angle)) * SEGMENT_LENGTH
	return point
