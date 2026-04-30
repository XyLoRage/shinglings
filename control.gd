extends Control

# --- Exported variables so you can drag and drop in the inspector ---
@export var bill_scene: PackedScene # Drag your bill.tscn here in the inspector
@export var exchange_rate: float = 61.5 # Current approximate rate
@export var paper_sfx: AudioStream
@export var lose_sfx:AudioStream
@export var win_sfx:AudioStream
@export var sample_bill:TextureRect
@export var fire_particles: PackedScene
# --- Node references ---
@onready var input_usd = $VBoxContainer/InputUSD
@onready var result_php = $VBoxContainer/ResultPHP
#@onready var equivalents_label = $VBoxContainer/Equivalents
@onready var spawn_area = $VBoxContainer/BillSpawnArea

func _ready():
	pass

func update_equivalents(php: float):
	pass # Logic hidden per your script

func play_sfx(sfx:AudioStream):
	var player = AudioStreamPlayer.new()
	add_child(player)
	player.stream = sfx
	player.play()
	player.finished.connect(player.queue_free)



func update_bills(php: float):
	var num_1k_bills = floor(php / 1000)
	var target_count = min(num_1k_bills, 200) 
	
	var current_bills = spawn_area.get_children()
	var current_count = current_bills.size()
	
	if target_count == current_count:
		return # No changes needed

	var num_stacks = 1
	if target_count > 20:
		num_stacks = 4
	elif target_count > 10:
		num_stacks = 2

	var area_width = spawn_area.size.x
	if area_width == 0:
		area_width = get_viewport_rect().size.x

	var drop_height = -500 # Way above the screen for both spawning and flying away
	var bottom_target = spawn_area.size.y - 100 
	var stack_offset = 5 
	var row_gap = 80 
	
	# Get bill width to use in your math. Instantiate a temporary one if empty.
	var bill_size_x = sample_bill.size.x
	# Loop over whichever number is larger (the old count or the new count)
	var max_iterations = max(target_count, current_count)
	if(target_count<current_count):
		play_sfx(lose_sfx)
	elif target_count>current_count:
		play_sfx(win_sfx)
	
	for i in range(max_iterations):
		# --- Calculate Target Grid Math (Your custom layout logic) ---
		var current_stack = i % num_stacks
		var bills_in_this_stack = i / num_stacks
		var target_x = 0.0
		var target_y_base = bottom_target
		
		if num_stacks == 4:
			var segment_width = area_width / 2.0
			var col = 0 
			if current_stack == 1 or current_stack == 2:
				col = 1
			var row = 1 
			if current_stack == 2 or current_stack == 3:
				row = 0 
			var center_x = (segment_width / 2.0) + (col * bill_size_x / 1.2)
			target_x = center_x - (bill_size_x / 2.0)
			if row == 0:
				target_y_base = bottom_target - row_gap
				target_x += bill_size_x / 4.5
		elif num_stacks == 2:
			var segment_width = area_width / 2.0
			var center_x = (segment_width / 2.0) + (current_stack * bill_size_x / 1.2)
			target_x = center_x - (bill_size_x / 2.0)
		else:
			target_x = (area_width / 2.0) - (bill_size_x / 2.0)

		var target_y = target_y_base - (bills_in_this_stack * stack_offset)
		var target_pos = Vector2(target_x, target_y)

		# --- Apply Smart Logic based on Index ---
		if i < target_count and i < current_count:
			# 1. Existing bill that we still need. Move to new position (re-organizing stacks)
			var bill = current_bills[i]
			var tween = get_tree().create_tween()
			tween.tween_property(bill, "position", target_pos, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			
		elif i >= current_count:
			# 2. Add NEW bill dropping from above
			var bill = bill_scene.instantiate()
			spawn_area.add_child(bill)
			bill.position = Vector2(target_x, drop_height)
			
			if current_stack == 0:
				play_sfx(paper_sfx)
				
			var tween = get_tree().create_tween()
			tween.tween_property(bill, "position", target_pos, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			# Cascade delay
			await get_tree().create_timer(0.05 / num_stacks).timeout
			
		elif i >= target_count:
			# 3. Excess bill! Animate BURNING away in sync
			var excess_index = int(current_count - 1 - (i - target_count))
			var bill = current_bills[excess_index]
			
			bill.pivot_offset = bill.size / 2.0
			
			# --- SPAWN FIRE PARTICLES ---
			if fire_particles != null:
				var fire = fire_particles.instantiate()
				spawn_area.add_child(fire)
				# Center the fire directly on top of the bill
				fire.position = bill.position + (bill.size / 2.0) 
				# Ensure it's emitting
				fire.emitting = true
				# Auto-delete the particle node when the fire finishes!
				fire.finished.connect(fire.queue_free)
			
			# --- THE SYNCED BURN TWEEN ---
			var tween = get_tree().create_tween()
			tween.set_parallel(true)
			
			# Turn to ash (Orange/Black to Transparent)
			var ash_color = Color(0.8, 0.3, 0.1, 0.0) 
			tween.tween_property(bill, "modulate", ash_color, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			
			# Shrink down without floating
			tween.tween_property(bill, "scale", Vector2(0.2, 0.2), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			
			tween.chain().tween_callback(bill.queue_free)
			
			# Notice there is NO await timer here! This makes all excess bills burn exactly at the same time.

func _on_input_usd_text_submitted(new_text: String) -> void:
	# Removed the manual queue_free() loop here! The update function handles it beautifully now.
	
	if new_text.is_empty() or not new_text.is_valid_float():
		result_php.text = "PHP: 0.00"
		# Pass 0 to animate every single bill flying away
		update_bills(0.0) 
		return
		
	var usd_amount = new_text.to_float()
	var php_amount = usd_amount * exchange_rate
	
	result_php.text = "PHP: " + str(snapped(php_amount, 0.01))
	update_equivalents(php_amount)
	update_bills(php_amount)
