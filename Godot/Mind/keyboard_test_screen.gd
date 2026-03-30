extends Panel
# This is a placeholder script to fix a broken scene reference.
# The actual keyboard logic is in TactileInput.gd.

func _ready():
	# We can add simple test logic here later if needed.
	var label = Label.new()
	label.text = "KEYBOARD TEST SCREEN
(Placeholder)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.set_anchors_preset(PRESET_FULL_RECT)
	add_child(label)
	print("Keyboard Test Screen placeholder initialized.")
