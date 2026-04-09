extends Node
## Autoload singleton: resolve LumaxCore and common children after the main scene is in the tree.
## Usage: Lumax.synapse(), Lumax.core(), etc. Returns null if not loaded yet or missing.

func core() -> Node:
	var t := get_tree()
	if t == null:
		return null
	return t.root.find_child("LumaxCore", true, false)

func synapse() -> Node:
	var c := core()
	if c == null:
		return null
	return c.get_node_or_null("Soul")

func body() -> Node3D:
	var c := core()
	if c == null:
		return null
	return c.get_node_or_null("Body") as Node3D

func jen_avatar() -> Node3D:
	var b := body()
	if b == null:
		return null
	return b.get_node_or_null("Avatar") as Node3D
