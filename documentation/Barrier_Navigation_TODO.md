# TODO: Barrier Bypass and Attack-Position Navigation

Status: Partial — barrier actor/collision exists; ship bypass remains

## Goal

Enemy ships must route around a barrier, reach the same attack area used by the current gameplay, stop in a valid firing position, and continue shooting the planet. Pathing must remain cheap with hundreds of active entities.

## Current behavior

`EnemySpaceshipInstance` currently flies toward the planet center, switches to an orbit when it reaches its configured `orbit_radius`, and fires toward the center. `Barrier` now exists as a gameplay rectangle and blocks asteroid, garbage, and enemy-projectile impacts. Ships still need route state and attack-slot bypass logic.

## Recommended design

Use a deterministic XZ-plane state machine driven by `GameManager`:

1. `APPROACH`: travel from spawn position to a tangent point beside the barrier.
2. `BYPASS`: follow the barrier edge along a clockwise or counter-clockwise arc.
3. `ATTACK`: travel to a reserved attack point, stop there, and fire.

For a circular barrier, generate the route once on activation or when barrier data changes:

```text
clear_radius = barrier_radius + ship_radius + clearance_margin
```

Calculate tangent entry/exit points and the shorter arc. Choose side by shortest route, or alternate sides to distribute traffic. Do not recalculate path or run raycasts every physics tick.

## Attack slots

Create a fixed set of attack slots around the planet. Reserve one slot when a ship enters the route and release it on death/recycle. If design requires one exact firing point, use a queue and stagger ships behind it. Slot reservation prevents stacking and removes the need for local avoidance.

## Performance requirements

- Keep movement in `GameManager`'s centralized movement dispatcher.
- Store route phase, side, target slot, and route angle per ship.
- Use direct vector/angle math and squared-distance checks.
- Replan only on activation, barrier changes, or target-slot changes.
- Avoid one `NavigationAgent3D`, A* query, physics slide, or raycast loop per ship.
- Keep barrier collision rules separate from projectile line-of-fire rules.

## Alternatives

| Technique | Use when | Cost / risk |
| --- | --- | --- |
| Tangent + arc | Static circular barrier | Lowest cost; recommended |
| Pre-authored waypoints | Fixed level and fixed routes | Lowest cost; less flexible |
| Shared flow field | Dynamic or multiple obstacles | Rebuild field on event or at low rate |
| NavigationAgent3D / per-ship A* | Arbitrary navigation spaces | Flexible, but expensive at high counts |
| Physics sliding / raycast steering | Rare dynamic blockers | More CPU, jitter, no guaranteed attack point |

## Implementation checklist

- [x] Add barrier configuration, active state, 10 HP, and rectangle collision.
- [ ] Add ship route state and tangent/arc route generation.
- [ ] Add clockwise/counter-clockwise side selection.
- [ ] Add attack-slot reservation and release on recycle/death.
- [x] Define current blocking set: asteroids, garbage, and enemy projectiles; ships remain TODO until bypass is implemented.
- [ ] Add debug route/slot visualization.
- [ ] Measure FPS and movement time with 200, 500, and 1,000 ships.

## Acceptance criteria

- Every active ship reaches an attack slot without entering barrier clearance radius.
- Ship stops at its assigned attack point and can fire reliably.
- No per-ship path query or raycast runs every frame.
- Route remains stable when many ships enter from the same side.
- Movement cost stays compatible with the centralized manager loop.
