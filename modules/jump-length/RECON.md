# JUMP LENGTH -- static recon (10 Oct 2026)

Stock 1.40C main OS, `out/raw/section_3_MAIN_OS.bin` (zip sha256
`370c55a3...`, section 1,112,560 bytes), disassembled with
`m68k-linux-gnu-objdump -D -b binary -m m68k:cfv4e --adjust-vma=0x40000400`.
Everything below is READ from the disassembly; nothing is measured under the
port yet.

## The decision the module replaces (tick handler `0x400a3fdc`)

At tick 0 of a step, `0x400a42fa..0x400a439c`:

| reg | holds |
|---|---|
| `a4` | the playing pattern's record (`0x400e21e0 + bank*0x9b340 + pat*0x8ed8`, set before `0x400a3fa6`) |
| `d7` | its length, word: PER TRACK (`+0x8e55 != 0`) -> MASTER LENGTH `+0x8e50` (-1 = INF); NORMAL -> LENGTH `+0x8e53` (`0x400a3fa6..0x400a3fc4`) |
| `d4` | `0x400d80dc[idx]`, idx = pattern `+0x8e56` if >= 0, else project `0x8000004e` |
| `d3` | 1 when an absolute change-at `0x8000662c` is set |
| `d6` | 1 when a change is queued (`0x800065bf/c0` differ from playing `bd/be`) |
| `d2` | the step counter `0x800065b2` (`mvzw` at `0x400a4352`, 6 bytes) |

Exits: `0x400a43a0` = switch (or restart at the pattern end); `0x400a4388` =
the length test (counter >= d7 -> `0x400a43a0`, INF or not yet ->
`0x400a4b9e`); `0x400a4b9e` = no switch. The change-at test at `0x400a439a`
is `cmpa.l d2,a0; bgt` -- it fires when counter >= change-at, not only
when equal -- and a CHAIN AFTER multiple (`0x400a4360`) is tested before
it. So the module hooks the decision itself instead of riding change-at.

The tick-2 pre-check `0x400a413e..0x400a41e8` is the same decision for
counter + 1 (`d1` = queued, `d2` = counter + 1, exits `0x400a41e8` = send the
program change, `0x400a41d0` = length test, `0x400a4b9e` = no). Hook at
`0x400a4196` (`mvzw 0x800065b2,%d0; move.l %d0,%d2; addq.l #1,%d2`, 10 bytes).

Main hook at `0x400a4352` (`mvzw 0x800065b2,%d2`, 6 bytes). After it `d0`
and `d1` are dead on every exit (`0x400a43a0` reloads d0; `0x400a4388`
reloads d0/d1); `d2..d7`, `a0`, `a4` must be preserved.

Boundary test for mode N (1, 2, 4, 8, 16) at counter c, length L:
`(c * N) mod L < N` -- true exactly where floor(c*N/L) steps up, so
L = 64, 2X -> 32, 64; L = 24, 16X -> 2, 3, 5, 6, ...; c = L is always one.
EOP: `c mod 16 == 0 || c >= L`. INS: always. INF (`d7 == -1`): the
multiples fall back to EOP.

## Where the setting lives: negative CHAIN BEHAVIOR

No pattern byte is both serialized and unvalidated. The serializer
(`0x4008a6fc..0x4008b276`, field by field, running checksum `0x460fab5c`)
ends the pattern at `+0x8e58` (tempo, long, 720..7200). The pattern
validator (`0x4009aa4a..0x4009abca`) clamps every trailer byte: `+0x8e53`
2..64, `+0x8e54` 0..6, `+0x8e55` 0..1, `+0x8e56` -1..16, `+0x8e57` 0..3, the
tempo 720..7200; the track validator (`0x4009a670..`) clamps `+0x50..+0x58`.

`+0x8e56` (per-pattern CHAIN BEHAVIOR, -1 = USE PRJ SET.) can carry JUMP as
-2..-8 (INS, EOP, 1X, 2X, 4X, 8X, 16X):

| reader | treats -2..-8 as | change |
|---|---|---|
| tick handler `0x400a4304`, pre-check `0x400a4148` | any negative -> project | none (the cave runs first) |
| validator `0x4009ab54` (`moveq #-1,d7`) | resets < -1 to -1 | `7eff` -> `7ef8` |
| PATTERN SETTINGS `0x40081c2c`, `0x40081cb8`, `0x40081db0` | `cmp` with -1 then `beq` -> NOT "use project", label table indexed negative | `67` -> `6c` (`bge`: x <= -1) |
| PATTERN SETTINGS setter `0x40081d08..` | clamps whatever it reads | none; turning CHAIN BEHAVIOR overwrites JUMP (port: confirm) |
| bank loader `0x4008de1c` | writes -1 for an old file | none |
| `0x4009bf40`, `0x4009c0a4` | use `+0x8e57` only | none |

A stock unit loading such a bank clamps -2..-8 to -1 = USE PRJ SET. (its own
validator). Copying a pattern copies the byte.

## The scale page (SCALE SETUP)

Window `0x460d1dfc` (96 x 51, created `0x40059f40..`, key table
`0x400c0cd8`), drawer `0x40047d08` ("PATTERN SCALE" `0x40047dc6`, "SCALE,
TRACK %d" / "SCALE, MIDI %d", "MASTER:" `0x400482ce`). Field cursor
`0x460d1e00`: next `0x40048628` wraps 0..4 and clamps to 2 in NORMAL; prev
`0x4004867c`. Field dispatch in the edit handlers `0x4004c940`,
`0x4004cca2`, `0x4004cf36`. The field order and the screen room for a JUMP
field are NOT known yet: render it under the port.
