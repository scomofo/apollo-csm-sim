# Audio lifecycle during flight replacement

The displayed saved-flight regression produced four `Playback can only
happen when a node is inside the scene tree` errors when RESUME replaced a
flight. Main removes the old scene before building the new one; its audio
director remained connected to the global Bus until `queue_free` completed,
so restored controls/events reached already-detached audio players.

The director now disconnects from the Bus on tree exit, stops its players,
joins outstanding voice rendering and rejects one-shots while detached.
The replacement's director still receives live crew actions. This change is
separate from saved checklist reading metadata and couch presentation.

The audio suite passes 12 tests / 266 assertions, including retired-director
silence and replacement-director live input. The displayed saved-flight suite
passes nine tests / 70 assertions with zero detached-playback or script errors.
It still reports renderer/resource cleanup errors at process exit; those are
not a clean shutdown acceptance claim. The actual displayed reading-recovery
and couch-capture tools complete with no engine/script errors. Dummy audio
output and desktop rendering do not establish audible listening or physical
headset acceptance.
