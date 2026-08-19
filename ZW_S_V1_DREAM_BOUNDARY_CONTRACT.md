# ZW-S V1 DREAM BOUNDARY CONTRACT

Status: CONTRACT FROZEN — PARSER IMPLEMENTATION NOT AUTHORIZED

Version: 1.0

Repository containing this boundary and its acceptance evidence:

```text
/mnt/data-drive/godot-dream
```

Implementation repository ownership: UNRESOLVED

## 1. Purpose

This contract freezes the smallest language boundary Dream requires before room-state work may begin:

```text
ZW-S v1.0 source text
        ↓
lexical and grammar parse
        ↓
lossless deterministic runtime projection
        ↓
Godot may consume the projection
```

The boundary proves that Dream can preserve the meaning of one project-shaped ZW-S room-state document. It does not authorize room-state storage, application, gameplay consequences, or return travel.

## 2. Normative authority and donor status

The normative language authority is:

```text
/home/mytruelove/Desktop/burdens_of_a_forgotten_past/
building_the_world/markor/zw/ZW-S Specification (Soft ZW Language).txt
```

Authority identity:

```text
Version: 1.0
Status: Frozen
Date: 2025-12-01
SHA-256: 68e3dad18eccb13e1b4a70147480b03841db1ee0b0cfdd8dd7997037f2d4345e
```

The selected executable predecessor is the `core/zw/zw_parser.py` brace-parser family. A representative copy is:

```text
/mnt/data-drive/burdens_of_a_forgotten_past/EngAIn/
godotengain/engainos/core/zw/zw_parser.py
```

Donor identity:

```text
SHA-256: f7e0e7867aeae24f201456957e779db0a3be23d71d71d4b5868405b9dbca16bd
```

The donor is evidence and a possible port/hardening predecessor. It is not language authority, production authority, or an implementation dependency authorized by this contract.

EngAIn remains an immutable read-only donor. Nothing in this contract permits editing, moving, importing live from, or normalizing EngAIn.

## 3. Ownership deliberately unresolved

This contract does not decide whether a conformant parser will ultimately live in:

```text
GodotDream
Ob-Tools
another separately approved shared package
```

The logical parser boundary and behavior are frozen before repository placement. A test-harness injection seam may select a parser candidate for acceptance testing; that seam is evidence infrastructure and does not determine production ownership, packaging, transport, or deployment.

## 4. Logical parser interface

A conformant parser accepts one complete UTF-8 ZW-S v1.0 source document and produces one parse outcome.

Conceptual interface:

```text
parse(source_text) → ParseOutcome
```

Successful outcome:

```text
ok         = true
projection = complete keyed runtime projection
error      = null
```

Failed outcome:

```text
ok         = false
projection = null
error      = non-empty deterministic diagnostic
```

The concrete implementation language, class name, file path, repository, and transport are not frozen here.

A test adapter may expose this conceptual interface as:

```gdscript
func parse(source_text: String) -> Dictionary
```

with exactly these result keys:

```text
ok
projection
error
```

That adapter shape is for parser acceptance only. It is not the later Dream room-state adapter contract.

## 5. Projection authority

ZW-S v1.0 §3 defines a block as a keyed object.

Input:

```text
{npc
  {id GUARD}
  {level 5}
}
```

Required projection:

```json
{
  "npc": {
    "id": "GUARD",
    "level": 5
  }
}
```

The parser must not reinterpret a block key as metadata such as:

```json
{"_tag": "npc"}
```

The runtime projection may be embodied as a Godot `Dictionary`, Python mapping, or equivalent temporary runtime structure. That projection is derived from ZW-S. Its host-language container types do not become Dream's native semantic memory language.

## 6. Required frozen-language behavior

A conformant parser for this boundary must:

1. Accept keyed brace blocks.
2. Treat spaces, tabs, CR, and LF as insignificant between tokens.
3. remove `;` line comments before parsing, including inline comments.
4. Accept identifiers matching the frozen identifier grammar.
5. Accept double-quoted strings with frozen quote and backslash escapes.
6. Parse integers, floats including permissive `.5`, and booleans into their runtime scalar equivalents.
7. Parse lists containing scalars, blocks, or mixed values.
8. Parse nested keyed blocks without a fixed semantic depth limit.
9. Merge multiple top-level blocks into one top-level keyed projection.
10. Accept and preserve unknown fields and unknown structures.
11. Treat `%`-prefixed extension blocks as ordinary preserved blocks as required by ZW-S v1.0 P7.
12. Produce deterministic projection and outcome values for identical source text.
13. Preserve insertion order as stable but non-semantic ordering.
14. Consume the complete non-comment source document.
15. Fail closed on malformed lexical or structural input.

“Fail closed” in this contract means rejecting malformed ZW-S syntax. It does not add domain validation, required fields, field types, uniqueness, or allowed-value schemas that ZW-S v1.0 explicitly excludes.

## 7. Duplicate/repeated key boundary

ZW-S v1.0 states that uniqueness is not enforced, but it does not define a projection rule for duplicate sibling or duplicate top-level keys.

This contract therefore does not invent last-write-wins, first-write-wins, list promotion, or rejection semantics for duplicate keys. Duplicate-key policy is unresolved and outside the parser RED acceptance matrix in this slice.

No implementation may silently claim a duplicate-key policy as frozen ZW-S v1.0 behavior. Any required policy must be resolved by a separately reviewed language clarification or versioned project profile.

## 8. Executable Dream witness

The authoritative witness for this boundary is:

```text
{room_state
  {room_id room_a}
  {objects [
    {state
      {id apple_01}
      {type pickup}
      {collected true}
    }
    {state
      {id chest_01}
      {type chest}
      {remaining_loot
        {health_potion 1}
        {rope 1}
      }
    }
  ]}
}
```

Its required keyed runtime projection is:

```json
{
  "room_state": {
    "room_id": "room_a",
    "objects": [
      {
        "state": {
          "id": "apple_01",
          "type": "pickup",
          "collected": true
        }
      },
      {
        "state": {
          "id": "chest_01",
          "type": "chest",
          "remaining_loot": {
            "health_potion": 1,
            "rope": 1
          }
        }
      }
    ]
  }
}
```

The semantic corruption regression is explicit:

```text
remaining_loot
├── health_potion = 1
└── rope = 1
```

must never become:

```text
health_potion
└── rope
```

The keys `remaining_loot`, `health_potion`, and `rope` must all survive in their exact structural relationship.

## 9. Complete-consumption and fail-closed boundary

A parser must not return a successful partial projection after reading only a valid prefix.

At minimum, syntax failures include:

```text
unclosed block
unclosed list
unterminated string
invalid block key
unexpected closing delimiter
valid first top-level block followed by malformed material
non-comment scalar material at file top level
```

On failure:

```text
ok         = false
projection = null
error      = non-empty
```

A partial object must not be published as a successful projection.

## 10. Determinism boundary

For identical source text and parser version:

```text
parse(source) == parse(source)
```

This applies to:

```text
success/failure status
complete projection value
scalar types
list order
key insertion order
error value for a rejected input
```

Object key ordering is stable evidence but is not semantic equality. Acceptance compares structural values rather than serialized dictionary byte order unless a later serialization contract explicitly says otherwise.

## 11. Explicitly forbidden reinterpretations

A conformant implementation must not:

- emit `_tag` in place of the authored block key;
- drop a later top-level block;
- promote nested child keys out of their authored parent;
- collapse unknown keys into one generic key or numeric field ID;
- silently return a valid prefix when the remaining document is malformed;
- validate Dream room schema as part of ZW-S parsing;
- infer NodePaths, scene-tree paths, Godot instance IDs, or GDScript classes;
- compile to ZONB as part of this boundary;
- evaluate AP or AntiPython;
- mutate gameplay, room, traveler, canon, or disk state.

## 12. Parser RED acceptance matrix

Parser-only RED must express at least these independent behaviors:

```text
R1  exact Dream room-state projection
R2  remaining_loot sibling preservation
R3  keyed-object projection and recursive absence of _tag
R4  semicolon and inline comment removal
R5  multiple top-level block merge
R6  scalar typing: int, negative int, float, permissive .5, booleans, string
R7  scalar/block/mixed lists
R8  unknown field and nested structure preservation
R9  deep nested block parsing
R10 deterministic repeated parse
R11 unclosed block rejection
R12 unclosed list rejection
R13 unterminated string rejection
R14 invalid block-key rejection
R15 unexpected closing delimiter rejection
R16 valid-prefix-plus-malformed-tail rejection
R17 top-level scalar rejection
R18 failed outcome publishes no partial projection
```

RED must fail because no conformant parser candidate has been supplied or because a supplied predecessor violates these behaviors. Test syntax errors, harness errors, fixture errors, or source-path mistakes are not valid RED evidence.

## 13. Non-goals and forbidden scope

This contract and parser RED do not authorize:

```text
parser GREEN
Dream ZW adapter
room-state store
apple/chest gameplay implementation
B → A return
ZON or ZONB compilation
existing ZONB packer use
AP or AntiPython
Event Store
disk persistence
Godot ResourceFormatLoader
Godot editor plugin registration
save files
network or provider calls
EngAIn modification or live import
```

The existing ZONB predecessor is specifically excluded because its shared `0x80` unknown-field behavior cannot preserve Dream's project-shaped keys.

## 14. Promotion staircase

The only authorized sequence after this contract is:

```text
this frozen contract
→ parser-only RED
→ stop
```

Later work requires separate authorization:

```text
minimal conformant parser GREEN
→ Dream ZW adapter
→ room-state RED
→ A → B → A memory GREEN
```

Passing parser tests proves only language parsing and projection. It does not authorize or prove room memory, gameplay consequences, transition return, persistence, ZON, AP, or canon acceptance.

## 15. Final invariant

```text
ZW-S owns authored semantic structure.
The parser preserves that structure or rejects the entire input.
Runtime containers may carry the projection but may not redefine it.
No downstream system may observe a successful partial or silently corrupted meaning.
```
