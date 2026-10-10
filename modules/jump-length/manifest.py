"""JUMP LENGTH -- when a cued pattern takes over, set per pattern and decoupled
from its length: INS (the next step), EOP (every 16 steps, the page), or
1X / 2X / 4X / 8X / 16X (every length/N steps). The new pattern starts at
its step 1, as on a stock change.

WHERE THE SETTING LIVES. No serialized pattern byte is free: the serializer
(0x4008a6fc..0x4008b276) writes the pattern field by field under a running
checksum and the validators (0x4009aa4a.., 0x4009a670..) clamp every trailer
and track byte to its range. So JUMP rides the pattern's own CHAIN BEHAVIOR
byte (+0x8e56, -1 = USE PRJ SET., 0..16 = a step count) as -2..-8: INS,
EOP, 1X, 2X, 4X, 8X, 16X. The tick handler and its pre-check treat any
negative as "use the project's" (0x400a4304, 0x400a4148) and the unit runs
before both; a stock unit's validator resets -2..-8 to -1, so a bank saved
here plays as USE PRJ SET. on stock. The two settings are one choice -- when
does the next pattern start -- so setting one replaces the other.

THE DECISION (unit jl.s). The tick handler decides at tick 0 of each step
whether a queued pattern takes over (0x400a42fa..0x400a439c) and repeats the
decision one step ahead at tick 2 to send the MIDI program change early
(0x400a413e..0x400a41e8). Two jsr detours take both decisions for a playing
pattern that carries JUMP and leave everything else stock; the switch
itself is stock code. Stock's absolute change-at test (0x400a439a) fires at
counter >= change-at and a CHAIN AFTER multiple is tested before it, which
is why this hooks the decision instead of riding change-at the way DIRECT
JUMP does.

Credit: Tim Hastie's DIRECT JUMP (modules/direct-jump, timhastie/
octatrick-modules) mapped the pattern-change queue, the tick handler, the
boundary apply and CHAIN AFTER's tables this module is built on; its
README's tables are the map. No code of his is used here.

Pokes: the pattern validator's low clamp -1 -> -8 (0x4009ab54) so a loaded
-2..-8 survives; PATTERN SETTINGS' three "== -1 means USE PRJ SET." tests
(0x40081c2c, 0x40081cb8, 0x40081db0) become "<= -1", so a JUMP pattern
draws as USE PRJ SET. instead of indexing a label table with a negative.

THE FIELD. SCALE SETUP ([FUNC] + [PAGE]) gets a sixth field (cursor
0x460d1e00 = 5) after the last stock one in both modes: the key table's
next/previous handlers (0x400cb606, 0x400cb5ec) are the unit's, which order
NORMAL 0, 1, 2, JUMP and PER TRACK 0..4, JUMP; the drawer's NORMAL clamp
(0x40047e86) keeps 5; the LEVEL encoder's field-4 test (0x4004cb50) hands 5
to the unit, which writes the byte as PATTERN SETTINGS' own setter does (the
pattern, the UI mirror 0x1001efa4, the bank dirty flag); the drawer
(0x40048610) draws the value in the scale fields' font, bottom right,
underlined like a stock field.
"""

from remix.schema import Category, Detour, Kind, Linked, Module, Poke, Proof, SymbolRef

UNIT = "jl"

MODULE = Module(
    name="jump-length",
    key="JUMP LENGTH",
    kind=Kind.CF_PATCH,
    category=Category.MACHINES, author="noamteyssier", author_url="https://github.com/noamteyssier",
    proof=Proof.CHECK, proof_note="not yet run",
    doc="Per-pattern JUMP: a cued pattern takes over at the next step (INS), "
        "the page (EOP) or every length/N steps (1X..16X), from step 1.",
    linked=(
        Linked(UNIT, "modules/jump-length/jl.s", cpu="5475"),
    ),
    detours=(
        Detour(0x400a4352, bytes.fromhex("75f9800065b2"), UNIT, "jl_main",
               "tick 0: the pattern-change decision", kind="jsr"),
        Detour(0x400a4196, bytes.fromhex("71f9800065b2" "2400" "5282"), UNIT, "jl_pre",
               "tick 2: the same decision one step ahead (program change)",
               kind="jsr", pad_to=10),
        # the SCALE SETUP field (field 5 of the cursor 0x460d1e00)
        Detour(0x40047e86, bytes.fromhex("7002" "b0b9460d1e00" "6406" "23c0460d1e00"), UNIT, "jl_clamp",
               "SCALE SETUP drawer: NORMAL clamps fields 3/4 to 2, keeps JUMP", kind="jsr", pad_to=16),
        Detour(0x4004cb50, bytes.fromhex("7204" "b280" "6600008c"), UNIT, "jl_enc",
               "SCALE SETUP LEVEL encoder: field 5 edits JUMP", kind="jmp", pad_to=8),
        Detour(0x40048610, bytes.fromhex("7001" "23c046c7c72c"), UNIT, "jl_draw",
               "SCALE SETUP drawer: draws the JUMP field", kind="jsr", pad_to=8),
    ),
    symbol_refs=(
        SymbolRef(0x400cb606, 0x40048628, UNIT, "jl_next", "SCALE SETUP key table: next field"),
        SymbolRef(0x400cb5ec, 0x4004867c, UNIT, "jl_prev", "SCALE SETUP key table: previous field"),
    ),
    pokes=(
        Poke(0x4009ab54, expect=bytes.fromhex("7eff"), write=bytes.fromhex("7ef8"),
             note="pattern validator: CHAIN BEHAVIOR low clamp -1 -> -8"),
        Poke(0x40081c2c, expect=bytes.fromhex("6756"), write=bytes.fromhex("6c56"),
             note="PATTERN SETTINGS: any negative draws USE PRJ SET. (beq -> bge)"),
        Poke(0x40081cb8, expect=bytes.fromhex("6706"), write=bytes.fromhex("6c06"),
             note="PATTERN SETTINGS: any negative is USE PRJ SET. (beq -> bge)"),
        Poke(0x40081db0, expect=bytes.fromhex("6776"), write=bytes.fromhex("6c76"),
             note="PATTERN SETTINGS: any negative is USE PRJ SET. (beq -> bge)"),
    ),
    conflicts=(
        ("DIRECT JUMP", "both decide when a cued pattern takes over; not run together"),
        ("DIRECT_JUMP_KYOTI", "both decide when a cued pattern takes over; not run together"),
    ),
)
