## Axes the cabin presentation shares with the simulation.
##
## Body: the spacecraft axes Dynamics and the CMC use. +X points toward the
## CM apex, along the rendezvous-window line of sight; +Z is the crew's
## "down"; +Y completes the right-handed set. (space_view.gd looks out along
## +X with the crew's up on body -Z.)
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
