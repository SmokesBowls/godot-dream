# dream_persistence_adapter.gd
# Godot version: 4.6
#
# PURPOSE
# -------
# This file is the ONLY place that should ever touch Godot's file I/O,
# timing, threading, or serialization APIs directly.
#
# DreamEventStore (the logic layer) never calls FileAccess, DirAccess,
# Time, Thread, var_to_bytes, etc. itself. It calls this adapter instead.
#
# Why this exists:
#   Godot 3 -> 4 broke File/Directory/OS/Thread/signal APIs wholesale.
#   That rewrite cost a full pass through logic code that hadn't
#   conceptually changed at all -- only the engine's vocabulary for
#   "write a file" or "get a timestamp" changed.
#
#   If Godot 5 (or 4.x -> 4.y) changes these APIs again, this adapter
#   is the only file that needs to change. DreamEventStore's checkpoint
#   priority logic, replay logic, and integrity hashing do not move.
#
# CONTRACT
# --------
# Every method here is the stable interface. If you port to a new
# engine version, re-implement the bodies of these methods against
# the new API -- do not change method names or return shapes unless
# you are deliberately versioning the contract (see CONTRACT_VERSION).

extends Node
class_name DreamPersistenceAdapter

const CONTRACT_VERSION := "1.0"

# ---------------------------------------------------------------------
# TIME
# ---------------------------------------------------------------------

## Monotonic milliseconds since engine start. Used for event timestamps,
## checkpoint aging, and throttling -- never wall-clock time.
func now_ms() -> int:
	return Time.get_ticks_msec()

# ---------------------------------------------------------------------
# SERIALIZATION
# ---------------------------------------------------------------------

## Serialize a Variant (typically a Dictionary) to bytes for disk storage.
func serialize(value) -> PackedByteArray:
	return var_to_bytes(value)

## Deserialize bytes back into a Variant.
func deserialize(bytes: PackedByteArray):
	return bytes_to_var(bytes)

## Stable hash string used for integrity hashes. Pipe-joined component
## strings go in; a sha256 hex digest comes out.
func hash_text(s: String) -> String:
	return s.sha256_text()

# ---------------------------------------------------------------------
# FILESYSTEM
# ---------------------------------------------------------------------

## Ensure a directory exists (recursive), given a res://-or-user:// path.
func ensure_dir(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("DreamPersistenceAdapter: failed to create dir %s (err %d)" % [path, err])
		return false
	return true

## Write bytes to a file, length-prefixed, matching the legacy
## "store_var(size); store_buffer(bytes)" framing so old checkpoint
## files remain a known, documented format if you ever need to
## hand-parse one.
func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DreamPersistenceAdapter: failed to open for write %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_32(bytes.size())
	file.store_buffer(bytes)
	file.close()
	return true

## Read bytes previously written with write_bytes(). Returns an empty
## PackedByteArray on failure -- callers should treat empty as failure
## only if they also check file_exists() first, since a legitimately
## empty payload is technically possible.
func read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DreamPersistenceAdapter: failed to open for read %s (err %d)" % [path, FileAccess.get_open_error()])
		return PackedByteArray()
	var size := file.get_32()
	var bytes := file.get_buffer(size)
	file.close()
	return bytes

func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func delete_file(path: String) -> bool:
	if not file_exists(path):
		return true
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_warning("DreamPersistenceAdapter: failed to delete %s (err %d)" % [path, err])
		return false
	return true

## List filenames (not full paths) directly inside a directory.
## Does not recurse. Returns [] if the directory can't be opened.
func list_dir(path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	return out

# ---------------------------------------------------------------------
# THREADING
# ---------------------------------------------------------------------
#
# Godot 4's Thread.start() takes a Callable directly, no instance/method
# string pair like Godot 3 did. We still wrap it here so the logic layer
# never references Thread directly, and so a future engine that changes
# threading primitives again only requires edits in this one place.

func make_thread() -> Thread:
	return Thread.new()

func start_thread(thread: Thread, callable: Callable) -> int:
	return thread.start(callable)

func make_mutex() -> Mutex:
	return Mutex.new()

## Brief, non-blocking-engine pause for a polling background loop.
func sleep_ms(ms: int) -> void:
	OS.delay_msec(ms)
