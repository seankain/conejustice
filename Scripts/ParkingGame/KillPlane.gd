class_name KillPlane
extends Area3D
## The floor under the world. Anything that reaches it went off the edge of the
## lot, and gets put back.
##
## Ported from [code]KillPlane.cs[/code], which does this:
## [codeblock lang=csharp]
## player.PlayerRespawned?.Invoke(this, new());
## player.Respawn();
## [/codeblock]
## -- it raises the car's own event on the car's behalf. C# allows that within
## one assembly; GDScript does not let one object emit another's signal, and it
## is the wrong shape anyway. The killer asks the car to respawn and the car
## decides what to tell everyone else.

## Emitted after a car has been sent back, so the round can count it or the HUD
## can say something. The car's own [signal PlayerCar.respawned] fires too; this
## one carries the reason.
signal caught(car: PlayerCar)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# By group rather than by type: a parked car is the same scene as the
	# player's, and one that has been shoved off the world is the round's to
	# clean up, not this node's to teleport onto the player's marker.
	if not body.is_in_group(PlayerCar.GROUP):
		return
	var car := body as PlayerCar
	if car == null:
		return
	car.respawn()
	caught.emit(car)
