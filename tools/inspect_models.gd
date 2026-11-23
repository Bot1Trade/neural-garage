extends SceneTree
## Gibt Größe (AABB) und Animationen der Kenney-Modelle aus.
func _init() -> void:
	for dir in ["res://assets/kenney/nature/", "res://assets/kenney/cars/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".glb"):
				continue
			var n: Node = load(dir + f).instantiate()
			var aabb := AABB()
			var first := true
			for m in n.find_children("*", "MeshInstance3D", true, false):
				var a: AABB = (m as MeshInstance3D).get_aabb()
				var xf := Transform3D.IDENTITY
				var p: Node = m
				while p != null and p != n:
					if p is Node3D:
						xf = (p as Node3D).transform * xf
					p = p.get_parent()
				a = xf * a
				aabb = a if first else aabb.merge(a)
				first = false
			var anims := []
			for ap in n.find_children("*", "AnimationPlayer", true, false):
				anims = (ap as AnimationPlayer).get_animation_list()
			print("%-28s size %s pos %s %s" % [f, aabb.size.snapped(Vector3(0.01,0.01,0.01)), aabb.position.snapped(Vector3(0.01,0.01,0.01)), anims if anims.size() < 30 else anims.size()])
			n.free()
	quit()
