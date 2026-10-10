"""stock effects with JUMP LENGTH: a per-pattern INS / EOP / 1X..16X pattern change."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="jump-length",
    family="mods", proof=Proof.CHECK, proof_note="",
    doc="stock effects with JUMP LENGTH: a per-pattern INS / EOP / 1X..16X pattern change.",
    modules=("JUMP LENGTH",
             "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
