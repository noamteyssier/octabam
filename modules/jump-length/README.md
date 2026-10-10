# JUMP LENGTH

When a cued pattern takes over, set per pattern and decoupled from its
length:

| JUMP | the cued pattern takes over at |
|---|---|
| INS | the next step |
| EOP | every 16 steps (the page), or the pattern end if that comes first |
| 1X | the pattern end |
| 2X / 4X / 8X / 16X | every length/N steps: where floor(c·N/L) steps up, so 64 steps at 2X switch at 32 and 64, 24 steps at 8X at 3, 6, 9 ... |

The new pattern starts at its step 1, as on a stock change. In PER TRACK
mode L is MASTER LENGTH; with INF the multiples fall back to EOP. A pattern
without JUMP plays exactly as stock (CHAIN AFTER / CHAIN BEHAVIOR).

## Setting it

[FUNC] + [PAGE] (SCALE SETUP): JUMP is the last field, bottom right, after
SCALE in NORMAL and after MASTER SCALE in PER TRACK. [LEFT] / [RIGHT] move
to it (it wraps to and from the first field), the LEVEL encoder steps
`---`, INS, EOP, 1x, 2x, 4x, 8x, 16x. `---` is "no JUMP": the pattern
follows CHAIN BEHAVIOR / CHAIN AFTER as on stock.

`Kind.CF_PATCH`: one ROM unit (`jl.s`), five detours (two in the sequencer,
three on the SCALE SETUP page), two key-table repoints, four pokes. No DSP code. The mechanism and the addresses are in `manifest.py`'s
docstring and `RECON.md`.

Credit: Tim Hastie's [DIRECT JUMP](../direct-jump/) mapped the sequencer's
pattern-change queue and tick handler this is built on. No code of his is
used; the two modules declare a conflict, as do this and DIRECT_JUMP_KYOTI.

## Where the setting lives

In the pattern's CHAIN BEHAVIOR byte (`+0x8e56`), as -2..-8 below stock's -1
(USE PRJ SET.): no serialized pattern byte is free (`RECON.md`). So:

- JUMP travels with the pattern (copy, paste, save, load).
- Setting CHAIN BEHAVIOR in PATTERN SETTINGS replaces JUMP, and the reverse:
  both answer "when does the next pattern start".
- A JUMP pattern draws in PATTERN SETTINGS as USE PRJ SET.
- On stock firmware the bank's validator resets -2..-8 to -1, so a JUMP
  pattern plays as USE PRJ SET. there.

## Measured (port, 10 Oct 2026)

`ot_emu --sequencer --internal-clock` on a blank project (16-step patterns,
120 BPM), the JUMP byte of A01 poked after the load (there is no UI row
yet), A02 queued by poking `0x800065c0` 100 frames after PLAY (during step
1) unless noted; `--watch-mem` on the step counter `0x800065b2` and the
playing pattern `0x800065be`, `--watch-pc 0x4009e884` on the MIDI program
change:

| A01 | JUMP | switched to A02 at counter | program change |
|---|---|---|---|
| 16 steps, stock image, byte poked -5 | -- | 16 (stock reads it as USE PRJ SET.) | stock pre-check, boundary 16 |
| 16 steps | 2X | 8 | stock pre-check, boundary 8 |
| 16 steps | INS | 2 (the next step) | `jl_owed` at the switch (selection after tick 2), bank 0 / pattern 1 |
| 16 steps | 16X | 2 | -- |
| 16 steps | EOP | 16 | -- |
| 64 steps | EOP | 16 | -- |
| 64 steps | 4X | 16 | -- |
| 24 steps | 8X | 3 | -- |
| 24 steps | 1X | 24 | stock pre-check, boundary 24 |
| 24 steps, A02 queued at frame 1100 | EOP | 16 | -- |

Every switch restarted the counter at 0 on A02.

The SCALE SETUP field (port, same project, `--live-script`, the screen
read back with `tools/emu/lcd_view.py`):

- NORMAL: [RIGHT] x 3 from the first field lands on JUMP (`0x460d1e00` =
  5); [LEFT] x 2 goes 0 -> JUMP -> 2. PER TRACK: [RIGHT] x 5 lands on it.
- Three clockwise LEVEL steps on JUMP wrote `0xfc` (1x) into A01's byte and
  drew `1x`; the field draws dotted when not selected and solid when it
  is, like the stock fields, in both modes.

## Not yet

- A pattern set through the page and then played in one run (the byte the
  page writes is the byte the sequencer runs above were poked with).
- PER TRACK mode, MASTER LENGTH INF, the arranger and chains are reasoned
  from the disassembly, not run.
- The validator and PATTERN SETTINGS pokes are not exercised by a run (no
  save/reload, no PATTERN SETTINGS screen).
- Nothing on hardware.
