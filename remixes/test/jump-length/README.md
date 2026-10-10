# `jump-length` -- JUMP LENGTH

One ColdFire module and the stock effects.

## What is in it

- **JUMP LENGTH** -- [`modules/jump-length/manifest.py`](../../../modules/jump-length/manifest.py).
- the 14 stock FX2 effects, listed so the chooser is stock's.

## Status

In development: not yet run under the port, never flashed.

## Build

```bash
make image REMIX=jump-length BUILD=1
```

[BUILDING.md](../../../docs/guide/BUILDING.md) is the walk-through from a fresh machine to a flashed unit. `make check REMIX=jump-length` runs every gate first.
