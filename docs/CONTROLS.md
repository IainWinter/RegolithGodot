# Controls

Generated from `game/scripts/core/Controls.gd` by `game/scripts/core/GenerateControlsDoc.gd`, do not edit by hand.
Keys marked with * are bound by position (the same place on any keyboard layout). Actions marked builtin are Godot's own ui_* actions.

## Gameplay

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `move_left` | A*, Left* |  |  | Move left |
| `move_right` | D*, Right* |  |  | Move right |
| `move_up` | W*, Up* |  |  | Move up |
| `move_down` | S*, Down* |  |  | Move down |
| `dash` | Space*, Shift* |  |  | Dash in the move direction |
| `shoot` |  | Left mouse |  | Fire the current weapon |
| `special` |  | Right mouse |  | Hold the shield up |
| `swap_special` | E* |  |  | Swap the special (bound, nothing reads it yet) |

## Weapons

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `weapon_1` | 1* |  |  | Select weapon slot 1 |
| `weapon_2` | 2* |  |  | Select weapon slot 2 |
| `weapon_3` | 3* |  |  | Select weapon slot 3 |
| `weapon_4` | 4* |  |  | Select weapon slot 4 |
| `weapon_5` | 5* |  |  | Select weapon slot 5 |
| `weapon_6` | 6* |  |  | Select weapon slot 6 |
| `next_weapon` | Q* | Wheel down |  | Cycle to the next weapon |

## Menus

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `pause` | Escape* |  | Pad Start | Pause and resume the game |
| `ui_up` (builtin) | Up |  | Pad D-pad up | Menu cursor up (wraps), also the left stick |
| `ui_down` (builtin) | Down |  | Pad D-pad down | Menu cursor down (wraps), also the left stick |
| `ui_focus_next` (builtin) | Tab |  |  | Menu cursor to the next button |
| `ui_focus_prev` (builtin) | Shift+Tab |  |  | Menu cursor to the previous button |
| `ui_accept` (builtin) | Enter, Keypad Enter, Space |  |  | Press the button under the menu cursor |

## Debug

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `editor_toggle` | F2 |  |  | Open or close the sprite editor on the sprite under the cursor (the player when none) |
| `debug_panel` | F3 |  |  | Open or close the debug panel (stats, pause and step, AI, controls) |
| `spawn_panel` | \`* |  |  | Open or close the spawn panel |
| `debug_dig` |  | Left mouse |  | Cut a hole in the sprites under the cursor |
| `debug_burn` |  | Right mouse |  | Set the cells under the cursor burning |

## Spawn panel

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `spawn_grab` |  | Left mouse |  | Press a card to spawn or drag it out, drag a dynamic sprite in the world |
| `spawn_rotate_left` | Q | Wheel up |  | Turn the dragged spawn left |
| `spawn_rotate_right` | E | Wheel down |  | Turn the dragged spawn right |
| `spawn_drag_cancel` | Escape |  |  | Drop the drag without spawning |
| `spawn_panel_close` | Escape |  |  | Close the spawn panel |

## Editor canvas

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `canvas_primary` |  | Left mouse |  | Use the tool, select or drag a sprite |
| `canvas_secondary` |  | Right mouse |  | Use the tool with the second color, cancel a joint or selection |
| `canvas_pan` |  | Middle mouse |  | Drag to pan the view, click to pick a color (sprite editor) |
| `canvas_zoom_in` |  | Wheel up |  | Zoom in at the cursor |
| `canvas_zoom_out` |  | Wheel down |  | Zoom out at the cursor |

## Sprite editor

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `sprite_undo` | Ctrl+Z |  |  | Undo |
| `sprite_redo` | Ctrl+Y, Ctrl+Shift+Z |  |  | Redo |
| `sprite_select_all` | Ctrl+A |  |  | Select everything |
| `sprite_copy` | Ctrl+C |  |  | Copy the selection |
| `sprite_cut` | Ctrl+X |  |  | Cut the selection |
| `sprite_paste` | Ctrl+V |  |  | Paste |
| `sprite_duplicate` | Ctrl+D |  |  | Duplicate the selection |
| `sprite_fit` | F, Ctrl+0 |  |  | Fit the sprite to the view |
| `sprite_pencil` | B |  |  | Pencil tool |
| `sprite_eraser` | E |  |  | Eraser tool |
| `sprite_fill` | G |  |  | Fill tool |
| `sprite_picker` | I |  |  | Color picker tool |
| `sprite_select` | M |  |  | Select tool |
| `sprite_move` | V |  |  | Move tool |
| `sprite_rect` | R |  |  | Rectangle tool |
| `sprite_line` | L |  |  | Line tool |
| `sprite_select_add` | Shift |  |  | Hold while starting a selection to add to the current one |
| `sprite_deselect` | Escape |  |  | Drop the floating paste, else clear the selection |
| `sprite_delete` | Delete, Backspace |  |  | Drop the floating paste, else clear the selected cells |
| `sprite_commit` | Enter, Keypad Enter |  |  | Place the floating paste |
| `sprite_zoom_in` | =, +, Keypad + |  |  | Zoom in |
| `sprite_zoom_out` | -, Keypad - |  |  | Zoom out |
| `sprite_brush_smaller` | [ |  |  | Smaller brush |
| `sprite_brush_bigger` | ] |  |  | Bigger brush |
| `sprite_nudge_left` | Left |  |  | Nudge the selection or paste left |
| `sprite_nudge_right` | Right |  |  | Nudge the selection or paste right |
| `sprite_nudge_up` | Up |  |  | Nudge the selection or paste up |
| `sprite_nudge_down` | Down |  |  | Nudge the selection or paste down |

## Multisprite editor

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `multi_move_mode` | V |  |  | Move mode |
| `multi_joint_mode` | J |  |  | Joint mode |
| `multi_rotate_left` | Q |  |  | Turn the selected sprite left |
| `multi_rotate_right` | E |  |  | Turn the selected sprite right |
| `multi_set_head` | H |  |  | Make the selected sprite the head (again to clear) |
| `multi_fit` | F |  |  | Fit the document to the view |
| `multi_delete` | Delete, Backspace |  |  | Remove the selected sprite |
| `multi_deselect` | Escape |  |  | Clear the selection and the pending joint |

## Editor plugins

| Action | Keys | Mouse | Pad | Description |
| --- | --- | --- | --- | --- |
| `pipes_paint` |  | Left mouse |  | Pipes toolbar: paint with the brush |
| `pipes_erase` |  | Right mouse |  | Pipes toolbar: erase (gauge brush: reset the gauge) |
| `pipes_edge` | Shift |  |  | Pipes toolbar, Pipe brush: hold to link or unlink the nearest edge instead of painting the cell |
| `scenario_drag` |  | Left mouse |  | Scenario: drag a zone or placement handle |
| `debug_dock_swatch` |  | Left mouse |  | Debug Draw dock: open the color picker of a swatch |
