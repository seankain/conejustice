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
	var car := body as PlayerCar
	if car == null:
		# Anything else that falls this far -- a cone, a knocked-over bollard --
		# is not worth keeping. The round's own cleanup owns parked cars, so
		# nothing is freed from here.
		return
	car.respawn()
	caught.emit(car)
