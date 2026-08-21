# DREAM ZW ROOM-STATE ADAPTER BOUNDARY CONTRACT

Status: RED AUTHORIZED — GREEN NOT AUTHORIZED

Version: 1.0

Repository containing this boundary and its acceptance evidence:

```text
/mnt/data-drive/godot-dream
```

## 1. Purpose

This contract freezes the smallest Dream-facing boundary after the conformant ZW-S v1 parser:

```text
ZW-S semantic source/value
        ↓
ZW_S_V1 parser
        ↓
validated Dream room-state projection
```

The slice asks whether Dream needs anything more than one narrow validation/projection function over the parser outcome. It does not assume or authorize a persistent adapter object, Node, autoload, manager, coordinator, factory, service, store, or registry.

The exact semantic witness must let Dream resolve:

```text
room_id = room_a

apple_01:
    collected = true

chest_01:
    remaining_loot:
        health_potion = 1
        rope = 1
```

## 2. Upstream authority

The native language authority remains the frozen ZW-S v1.0 specification identified by the parser contract:

```text
ZW-S Specification (Soft ZW Language)
Version: 1.0
Status: Frozen
SHA-256: 68e3dad18eccb13e1b4a70147480b03841db1ee0b0cfdd8dd7997037f2d4345e
```

The accepted parser dependency for this RED is:

```text
res://core/systems/zw/zw_s_v1_parser.gd
SHA-256: f9253b6037ab3697c33692f4ad623913a4e0cfb8f32c715e9c68771951bbf798
```

The exact Dream witness fixture is:

```text
res://tests/zw_s_v1_dream_boundary/fixtures/room_state.zw
SHA-256: e4cfaeaea99cf4da1f9161b8467fca0e10b01ae0019dc98bfc322937d884d7c2
```

This boundary consumes the parser's public outcome. It must not contain another ZW-S lexer or parser and must not read the source text independently.

## 3. Authority and representation

ZW-S remains Dream's native semantic value. The parser projection and Dream room-state projection are runtime-derived views.

```text
ZW semantic value = authority
parser Dictionary = complete runtime projection
Dream room-state Dictionary = validated, detached consumer projection
```

Godot `Dictionary`, `Array`, `Variant`, script classes, Nodes, Resources, and serialized Godot files do not become canonical room state.

The room-state boundary may validate and index semantic content. It may not invent room or object values that were absent from the parser outcome.

## 4. Smallest logical interface

The complete logical operation is:

```text
project_room_state(ParseOutcome) → RoomStateOutcome
```

A test-only GDScript candidate may expose it as:

```gdscript
func project_room_state(parse_outcome: Dictionary) -> Dictionary
```

The harness may instantiate the injected script only to call this operation. That harness mechanism does not require or authorize a persistent production object. Each acceptance call uses a fresh candidate carrier, so satisfying the boundary cannot depend on state accumulated in an adapter instance.

A conforming GREEN may be a single pure function or a stateless `RefCounted` script. A persistent object architecture is unnecessary unless later evidence proves otherwise.

## 5. Input boundary

The function accepts only the parser's outcome shape.

Successful parser input:

```text
{
    ok: true,
    projection: Dictionary,
    error: null,
}
```

Rejected parser input:

```text
{
    ok: false,
    projection: null,
    error: non-empty String,
}
```

A failed parser outcome must remain failed. Its diagnostic must remain visible unchanged through the room-state outcome.

Fabricated, partial, contradictory, or wrong-typed parser outcome shapes must fail closed. In particular, the boundary must reject:

```text
ok missing or not bool
projection missing
error missing
ok=true with null/non-Dictionary projection
ok=true with non-null error
ok=false with non-null projection
ok=false with empty/non-String error
extra parser-outcome keys
```

## 6. Success outcome

A successful Dream room-state outcome has exactly these keys:

```text
ok
room_state
error
```

with:

```text
ok         = true
room_state = Dictionary
error      = null
```

The exact witness projects to:

```text
{
    ok: true,
    room_state: {
        room_id: room_a,
        objects: {
            apple_01: {
                id: apple_01,
                type: pickup,
                collected: true,
            },
            chest_01: {
                id: chest_01,
                type: chest,
                remaining_loot: {
                    health_potion: 1,
                    rope: 1,
                },
            },
        },
    },
    error: null,
}
```

`objects` changes only from the parser's authored list-of-`state` blocks into a deterministic semantic-ID index. Each indexed value remains the complete authored state Dictionary.

## 7. Failure outcome

A failed Dream room-state outcome has exactly these keys:

```text
ok
room_state
error
```

with:

```text
ok         = false
room_state = null
error      = non-empty deterministic String
```

No failed outcome may publish a partial room projection or partial object index.

For an upstream parser failure, `error` must equal the parser diagnostic exactly. Validation failures introduced by this boundary must use deterministic non-empty diagnostics.

## 8. Semantic root and room identity

A successful parser projection is accepted only when its complete top-level key set is:

```text
room_state
```

The `room_state` value must be a Dictionary.

The room must contain exactly one `room_id` field. Because a valid parser projection cannot represent duplicate sibling keys, this boundary enforces the consumer-visible condition by requiring one present, non-empty String value and refusing missing or wrong-typed material.

The boundary does not infer room identity from scene paths, resource paths, NodePaths, filenames, object IDs, instance IDs, or GDScript classes.

## 9. Semantic object resolution

The authored `room_state.objects` value must be an Array.

Every array element must be a Dictionary with exactly one wrapper key:

```text
state
```

The `state` value must be a Dictionary containing one present, non-empty String `id`.

The Dream projection indexes complete state Dictionaries by that semantic `id`:

```text
room_state.objects[semantic_id] = complete authored state Dictionary
```

Object order in the source list determines deterministic insertion order in the runtime index. Ordering is stable evidence, not object identity.

No NodePath, scene-tree position, array index, instance ID, type name, or resource path may substitute for semantic `id`.

## 10. Duplicate semantic object IDs

Two state objects with the same semantic `id` are invalid for this Dream projection even though both are valid ZW-S list elements.

The boundary must reject the complete room-state outcome before publishing any object index.

It must not choose first-write-wins, last-write-wins, list promotion, suffixing, merging, or silent overwrite.

This is a Dream room-state consumer rule. It does not redefine ZW-S duplicate sibling-key semantics.

## 11. Unknown-field preservation

The boundary must preserve:

- every unknown room-state field other than the transformed `objects` container;
- every unknown state-object field;
- every unknown nested structure, list, scalar, and `%` extension already preserved by the parser.

The boundary may validate only the fields required to establish the root, room identity, object container, and semantic object identities.

It must not normalize, whitelist, drop, rename, reinterpret, or compile unknown values.

## 12. Exact remaining_loot invariant

The exact chest witness must remain:

```text
remaining_loot
├── health_potion = 1
└── rope = 1
```

It must never become:

```text
health_potion
└── rope
```

The boundary must not drop `remaining_loot`, promote either child, nest one sibling beneath the other, convert keys to metadata, or coerce the numeric values.

## 13. Derivation and anti-hardcoding

The Dream projection must be derived from the supplied successful parser outcome.

Acceptance uses more than the exact room witness. A second valid ZW source with different room ID, object ID, and unknown fields must produce those different values. A hard-coded `room_a`, `apple_01`, or `chest_01` projection fails.

The boundary receives no source text and therefore has no reason to parse ZW-S again.

## 14. Mutation isolation

The Dream room-state outcome must be detached recursively from the parser outcome.

After successful projection, mutating any returned room, object, list, or nested Dictionary value must not change:

- the original parser outcome;
- the parser projection inside that outcome;
- a fresh parse of the same ZW source.

This is runtime mutation isolation. It does not make either Dictionary canonical state or authorize a room store.

## 15. Determinism

For the same parser outcome and boundary version:

```text
project_room_state(value) == project_room_state(value)
```

This includes:

- success/failure status;
- complete room-state value;
- scalar types;
- object-index insertion order;
- deterministic validation diagnostic;
- exact propagation of an upstream parser diagnostic.

## 16. RED acceptance matrix

The executable RED must express at least these independent requirements:

```text
A1  exact Dream witness projection
A2  semantic room_id resolution
A3  apple_01 resolution by semantic id
A4  chest_01 resolution by semantic id
A5  exact remaining_loot sibling preservation
A6  malformed ZW parser failure remains fail-closed and visible
A7  only exact valid parser outcome shapes are accepted
A8  expected room_state root is required
A9  one valid room_id is required
A10 state objects require semantic id
A11 duplicate semantic object IDs reject without partial projection
A12 unknown room/state/nested fields are preserved
A13 projection derives different values rather than hard-coding the witness
A14 returned projection cannot mutate the parser outcome
A15 repeated valid and rejected outcomes are deterministic
```

Passing controls must independently prove:

```text
contract bytes match their frozen SHA-256
existing parser bytes match the accepted parser SHA-256
exact witness fixture bytes match their accepted SHA-256
the accepted parser parses every positive/consumer-invalid source as expected
malformed ZW fails in the parser before the room-state boundary
```

## 17. Explicitly forbidden in this slice

This RED does not authorize:

```text
adapter GREEN
persistent adapter object
Node or autoload registration
room-state store
memory-only room store
disk persistence
save/load
Event Store
ZONB
AP or AntiPython
ResourceFormatLoader
network/provider calls
apple or chest gameplay behavior
inventory mutation
B → A return travel
state application to scenes
Godot Resource canon
another parser
```

No room, traveler, gameplay, disk, or canonical semantic state may be mutated by this RED.

## 18. Test-only injection seam

The RED runner may select a candidate script only through:

```text
DREAM_ZW_ROOM_STATE_BOUNDARY_TEST_SCRIPT=res://...
```

The selected script must expose:

```gdscript
func project_room_state(parse_outcome: Dictionary) -> Dictionary
```

This seam is evidence infrastructure only. It does not freeze a production class name, file path, Node lifetime, service architecture, or repository ownership beyond this test repository.

With the environment variable unset, all controls must pass and every adapter requirement must fail for the explicit unavailable-subject reason or missing projection. Harness parse/load failures are not accepted as intentional RED.

## 19. Stop condition

This ticket stops when:

```text
contract/test artifacts exist
controls pass
A1–A15 fail because no room-state boundary is injected
process exits nonzero
parser authority remains 20 PASS / 0 FAIL
world lifecycle remains 57 PASS / 0 FAIL / 11 BLOCKED
no production boundary or state storage exists
```

The next separately authorized step may determine whether the minimal pure function is sufficient for GREEN. This RED does not authorize that implementation.

## 20. Final invariant

```text
ZW owns the semantic value.
The parser owns complete language projection or rejection.
The Dream boundary validates and indexes only what Dream needs.
The Dream boundary preserves unknown meaning and cannot rewrite its source projection.
No state is stored or applied yet.
```
