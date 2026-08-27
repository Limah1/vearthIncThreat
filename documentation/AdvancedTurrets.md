# Advanced Barrier Turrets

All turret actors are 3D and share fixed Basic Ally Ship mount placement, action-cone editing, right-click cancellation, and the `R` reset workflow. Their combat loops remain separate. Each ship has two mount spots.

## Laser Turret

- Unlock cost: `$50`; inventory after unlock: `1`.
- Locks the angle of the nearest hostile inside its cone.
- Fires a non-emissive, piercing beam for `3` seconds.
- Base damage: `5 DPS`, applied in `0.2`-second ticks to every hostile intersecting the beam.
- Cooldown begins after the beam ends: `10` seconds.
- Laser Damage: one `$50` rank, increasing damage from `5` to `10 DPS`.
- Laser Cooldown Reduction: three ranks costing `$100`, `$200`, and `$300`; each rank removes `1` second.

## Turret Miner

- Unlock cost: `$50`; inventory after unlock: `2`.
- Launches one mine every `3` seconds toward a random position inside its configured cone.
- Mines have no collision. After landing, they remain stationary for `1.5` seconds, explode once, and recycle.
- Base explosion damage: `5`; base radius: `10`.
- Mine Damage: one `$50` rank, increasing damage from `5` to `10`.
- Mine Radius: one `$50` rank, increasing radius from `10` to `20`.

The laser uses the active-entity spatial grid only five times per second while firing. Mines query that grid only when exploding. Mine visuals are preallocated per Turret Miner, so periodic firing does not instantiate gameplay nodes.

## Skill-tree positions

The existing manual layout is preserved. Laser Turret occupies the top branch beginning at cell `(5, 0)`. Turret Miner occupies the lower branch beginning at `(5, 6)`. Their upgrades explicitly reference their unlock nodes as prerequisites; no automatic layout is used.
