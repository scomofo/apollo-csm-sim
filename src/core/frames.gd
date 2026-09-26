## Axes the cabin presentation shares with the simulation.
##
## Body: the spacecraft axes Dynamics and the CMC use. +X points toward the
## CM apex, along the rendezvous-window line of sight; +Z is the crew's
## "down"; +Y completes the right-handed set. (space_view.gd looks out along
## +X with the crew's up on body -Z.) The LM's body axes, which Dynamics and
## the LGC use for it, are its own: +X up along its thrust axis, +Y right
## and +Z forward, out of its windows.
## Godot: engine axes, -Z forward, +Y up, +X right.
##
## The mapping is the same as gemini-capsule's Frames
## (https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/core/frames.gd),
## so the instrument prefabs taken from it need no change.
class_name Frames
extends RefCounted

## Rotation taking body axes to Godot cabin axes: body +X (forward) to
## Godot -Z, body +Y (right) to Godot +X, body +Z (crew down) to Godot -Y.
const BODY_TO_GODOT: Basis = Basis(
	Vector3(0, 0, -1),  # body X expressed in Godot
	Vector3(1, 0, 0),   # body Y
	Vector3(0, -1, 0)   # body Z
)
## The LM's body axes in Godot's: its +X (up, the crew's head) is +Y, its
## +Y (right) is +X and its +Z (forward, out of its windows) is -Z. Eagle's
## cabin, like the CM's, looks along -Z with the crew's up on +Y.
const LM_BODY_TO_GODOT: Basis = Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
## The LM's body axes in LVLH axes (X along the track, Y, Z down) when it
## flies level: its windows (+Z) forward along the track and its +X, the
## crew's up, away from the body below. The CSM flies level at LVLH itself.
const LM_LEVEL: Basis = Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))


## How [param vehicle] ("csm" or "lm") is turned from flying level, for an
## attitude [param q] relative to its reference (its computer's
## guid.indicator.attitude for the FDAI ball: the CSM's stable member, or
## LVLH for the LM; guid.indicator.lvlh for the horizon ring), as a
## rotation in Godot axes: the turn the ball and the ring take back out.
static func level_turn(q: Quaternion, vehicle: String) -> Basis:
	var b := LM_BODY_TO_GODOT if vehicle == "lm" else BODY_TO_GODOT
	var level := LM_LEVEL if vehicle == "lm" else Basis.IDENTITY
	return b * (level.inverse() * Basis(q)) * b.inverse()
