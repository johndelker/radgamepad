# Radgamepad Zoom and Field of View Controls

**Status:** Draft for review  
**Date:** 2026-10-10

## Goal

Remove temporary input diagnostics from the Radgamepad menu and input module, add a user-controlled zoom rate, and let the user set independent exploration and lock-on fields of view. While Radgamepad controls the third-person camera, the selected FOV must remain in effect even when the base game receives mouse-wheel zoom input.

## Current behavior

Radgamepad writes the camera position and focal point during `d3d_beginscene` / `d3d_endscene`. Right-stick zoom changes the configured camera distance by a hard-coded `0.05` per frame. Temporary trigger pressure, last XInput event, and modifier-held diagnostics remain in the menu and input module.

The local camera structure only describes position and focal-point coordinates; it has no FOV member. The upstream XICamera internals reference identifies FOV as a possible future camera patch, not an implemented field or patch target ([XICamera camera behavior](https://github.com/Hokuten85/XICamera/blob/master/docs/CLIENT_BEHAVIOR.md#7-what-we-deliberately-dont-touch), [patch targets](https://github.com/Hokuten85/XICamera/blob/master/docs/CAMERA_PATCH_TARGETS.md)). The in-game configuration ID 145 is documented as “Camera View,” a mode toggle, not an angle value ([Ashita config reference](https://github.com/ChrisTitusTech/ashita-ffxi/blob/main/addons/config/README.md)). Therefore the FOV control must not assume that an existing camera field or config ID represents an angle.

## Design

### Menu and settings

- Remove the temporary analog pressure, last XInput event, and modifier-held diagnostics, plus their input tracking/accessor code. Keep the bound modifier label and bind/clear controls.
- Add a `Zoom Speed` slider from `0.05` to `0.50`, default `0.05` to preserve the current zoom rate. The value scales the per-frame distance delta. Use the existing 0.05 slider tick convention.
- Add independent `Exploration Field of View` and `Lock-on Field of View` sliders, displayed in degrees, spanning `30°` to `120°`. Initialize both defaults to the supported client’s stock third-person FOV so loading the addon preserves the normal view.
- Persist all new values through the existing Radgamepad configuration path and normalize loaded values to documented slider ranges.

### Camera behavior

- Scale right-stick zoom by `Zoom Speed`; retain the existing direction and modifier behavior.
- Identify and validate the stock client’s actual projection/FOV value and how mouse-wheel input changes it before writing FOV support. Do not infer an address or reinterpret camera distance as FOV.
- Apply the exploration value when the normal third-person camera is active and the lock-on value when the target-locked camera is active. Reapply the selected value each rendered camera frame so base-game mouse-wheel changes cannot override Radgamepad’s selected FOV.
- Update the active FOV immediately when switching between exploration and lock-on camera modes; the two values are independent of the camera-distance sliders.
- Prefer an addon-owned projection input/constant with validated camera-code references over repeatedly racing the game’s transient value. Guard memory writes with signatures and expected-byte checks; report unsupported signatures and leave FOV untouched rather than writing to an unverified address.
- Avoid changing first-person camera behavior. On addon unload or unsupported state, restore/relinquish only memory sites Radgamepad still owns.

## Verification

- Unit-test zoom-rate scaling, configuration defaults/ranges, and separation of exploration versus lock-on FOV selection.
- Validate the FOV signature/value against the supported client before enabling writes.
- In game, confirm each mode has an independent FOV, the mouse wheel cannot change the active Radgamepad FOV, camera distance remains separately controllable, and unload restores or releases only Radgamepad-owned changes.
- If the client’s FOV projection input cannot be identified and safely overridden, stop before enabling the slider and report the missing evidence; do not ship a nonfunctional FOV control.

## Scope and constraints

Only the Radgamepad addon is in scope. No BetterTarget input behavior or game configuration setting is changed. The FOV implementation depends on locating the actual projection/FOV data path in the current client; the design explicitly allows this to block that portion rather than relying on an unverified offset.
