# Skill Tree Designer

The project includes a manual Skill Tree Designer editor plugin. It stores the
runtime graph and node positions in:

`res://src/resources/skill_trees/MainSkillTreeConfig.tres`

## Open the designer

Open the **Skill Tree** main-screen tab in the Godot editor. Restart the editor
once if the tab does not appear immediately after pulling or enabling the plugin.

## Place an upgrade

1. Click an empty grid slot.
2. Search by upgrade name, ID, or category.
3. Select an unplaced upgrade and press **Place**.
4. Press **Save** when the layout is ready.

The clicked slot determines `grid_position`; coordinates are never typed
manually. The picker scans `res://src/resources/upgrades` recursively.

## Connect upgrades

1. Select the parent node.
2. Press **Connect Parent → Child**.
3. Click the child node.

Repeating the same action removes that connection. Select the child and choose
**ANY purchased** or **ALL purchased** to control multiple-prerequisite logic.

## Edit the layout

- **Move to Empty Slot** moves the selected upgrade without changing its links.
- **Remove From Tree** removes the node and its connections, but never deletes
  the `UpgradeData` asset.
- **Apply Grid** changes the manual grid dimensions. It refuses to shrink past
  an occupied cell.
- **Validate** checks duplicate placements, occupied cells, missing parents,
  out-of-bounds positions, duplicate IDs, and prerequisite cycles.

There is intentionally no automatic layout. Every position is selected by the
designer using a grid slot.

## Runtime

`SkillTree` generates its `UpgradeSlotUI` controls from `SkillTreeConfig`.
`UpgradeManager` reads prerequisites from the same config, so layout,
connections, and unlock behavior share one source of truth.
