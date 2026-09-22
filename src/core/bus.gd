## Signal bus: the only coupling between controls, systems, and instruments.
##
## Channels are named "system.component.quantity", the convention of
## gemini-capsule's docs/ARCHITECTURE.md §3:
## https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/docs/ARCHITECTURE.md#3-core-signal-bus-and-data-model
## Writers call set_value; readers call get_value; observers subscribe.
## All physical quantities on the bus are SI. Display conversion happens
## in the instrument, never here.
extends Node

## Emitted for every change. Prefer subscribe() for a single channel.
## Incremented whenever a command channel (ctl.*) changes value. SimClock
## uses it to keep the step after any new command at the fine step length.
var command_epoch: int = 0

signal value_changed(channel: String, value: Variant)

var _values: Dictionary = {}
var _subscribers: Dictionary = {}  # channel -> Array[Callable]


## Publish a value. Emits only if the value actually changed.
func set_value(channel: String, value: Variant) -> void:
	if _values.has(channel) and _values[channel] == value:
		return
	_values[channel] = value
	if channel.begins_with("ctl."):
		command_epoch += 1
	value_changed.emit(channel, value)
	if _subscribers.has(channel):
		# Subscribers are often bound methods on short-lived scene nodes. A node
		# can disappear without explicitly unsubscribing, especially across GUT
		# fixtures and scene rebuilds. Iterate a copy so callbacks may unsubscribe
		# safely, skip/prune dead callables, and never turn stale presentation
		# listeners into script errors on an otherwise valid bus write.
		var stale: Array[Callable] = []
		for cb: Callable in _subscribers[channel].duplicate():
			if not cb.is_valid():
				stale.append(cb)
				continue
			cb.call(value)
		for cb: Callable in stale:
			_subscribers[channel].erase(cb)
		if _subscribers[channel].is_empty():
			_subscribers.erase(channel)


## Read a value, or [param default] if the channel has never been written.
func get_value(channel: String, default: Variant = null) -> Variant:
	return _values.get(channel, default)


func has_channel(channel: String) -> bool:
	return _values.has(channel)


## Register a callable taking one argument (the new value). If the channel
## already has a value, the callable is invoked immediately with it.
func subscribe(channel: String, callback: Callable) -> void:
	if not callback.is_valid():
		return
	if not _subscribers.has(channel):
		_subscribers[channel] = []
	_subscribers[channel].append(callback)
	if _values.has(channel) and callback.is_valid():
		callback.call(_values[channel])


func unsubscribe(channel: String, callback: Callable) -> void:
	if _subscribers.has(channel):
		_subscribers[channel].erase(callback)


## Names of all channels written so far, sorted. Useful for debugging.
func channels() -> PackedStringArray:
	var keys := PackedStringArray(_values.keys())
	keys.sort()
	return keys


## Forget every value and subscription. Used by tests and by mission reload.
func reset() -> void:
	_values.clear()
	_subscribers.clear()


## Forget values only; subscribers stay bound and receive the republished
## state after a checkpoint restore.
func reset_values_only() -> void:
	_values.clear()
