# Radgamepad Zoom and Field of View Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove temporary input diagnostics, add a configurable zoom speed, and add independent exploration and lock-on FOV overrides that persist against base-game mouse-wheel input.

**Architecture:** Keep the existing camera-distance and input paths. Add Zoom Speed to configuration and scale the existing distance delta. Implement FOV as a separate, signature-validated camera projection override owned by Radgamepad, with separate mode values and safe no-op behavior when the supported client signature is unavailable.

**Tech Stack:** Ashita v4 Lua/LuaJIT, FFI, ImGui, Lua test scripts, PowerShell.

**Spec:** `docs/superpowers/specs/2026-10-10-radgamepad-fov-and-zoom-controls-design.md`

## Global Constraints

- Zoom Speed range is `0.05` to `0.50`, with default `0.05` to preserve current zoom rate.
- Exploration and lock-on FOV ranges are `30 degrees` to `120 degrees`; both default to the supported client's stock third-person FOV.
- Reapply the selected FOV each rendered camera frame while Radgamepad controls third-person camera.
- Never write an unverified FOV address or patch signature; unsupported signatures leave FOV unchanged.
- Do not change first-person camera behavior or any BetterTarget behavior.

## Review Focus

- Any future FOV patch must reject missing or changed signatures without writing.
- Any future FOV patch must preserve first-person behavior.
- Any future FOV controls must switch values immediately between exploration and lock-on.
- Any future FOV override must persist against base-game mouse-wheel input.
- Any future FOV patch must release only memory sites still owned by Radgamepad.

---

### Task 1: Remove temporary input diagnostics

**Files:**
- Modify: `radgamepad.lua`
- Modify: `input.lua`
- Test: `tests/zoom_modifier_test.lua`

**Interfaces:**
- Consumes: Existing input binding and modifier state APIs.
- Produces: The modifier label and bind/clear UI remain; temporary diagnostic UI and its input accessors are removed.

- [x] **Step 1: Add a failing test for removed diagnostics**

Assert that `update_trigger_values`, `get_trigger_values`, `record_xinput_button`, and `get_last_xinput_button_event` are absent from the input API. Read `radgamepad.lua` and assert it no longer contains the menu labels `Analog trigger pressure`, `Last XInput event`, or `Zoom Modifier held`. Keep existing binding, held-state, and capture assertions.

- [x] **Step 2: Run the test to verify it fails**

Run: `lua tests\zoom_modifier_test.lua`  
Expected: FAIL because diagnostic APIs and menu labels still exist.

- [x] **Step 3: Remove diagnostic state and menu lines**

Delete `record_xinput_button`, `get_last_xinput_button_event`, diagnostic cached trigger-value fields and their UI, and the `Zoom Modifier held` UI line. Remove only diagnostic pressure updates; retain reading trigger bytes for binding and modifier behavior. Keep `Zoom Modifier: <label>`, bind prompt, and buttons.

- [x] **Step 4: Run tests and syntax checks**

Run: `lua tests\zoom_modifier_test.lua; lua tests\input_axes_test.lua; luac -p radgamepad.lua input.lua`  
Expected: Both tests pass and Lua parsing succeeds.

### Task 2: Add configurable Zoom Speed

**Files:**
- Modify: `config.lua`
- Modify: `input.lua`
- Modify: `camera.lua`
- Modify: `radgamepad.lua`
- Test: `tests/zoom_modifier_test.lua`

**Interfaces:**
- Consumes: Existing `config.ranges`, slider helper, and `input.adjust_distance` call.
- Produces: `settings.zoomSpeed` and `input.adjust_distance(distance, vertical_axis, enabled, speed, minimum, maximum)`.

- [x] **Step 1: Add failing zoom-speed tests**

Assert the default is `0.05`, range is `{0.05, 0.50}`, and equal stick input at speed `0.10` changes distance twice as much as at `0.05`, clamped to the same minimum/maximum.

- [x] **Step 2: Run the focused test to verify it fails**

Run: `lua tests\zoom_modifier_test.lua`  
Expected: FAIL because `zoomSpeed` and the speed parameter do not exist yet.

- [x] **Step 3: Add configuration and UI control**

Add `zoomSpeed = 0.05` and range `{0.05, 0.50}` in `config.lua`. Add `slider('Zoom Speed', 'zoomSpeed')` in the Modifiers section; the existing slider helper provides 0.05 increments.

- [x] **Step 4: Scale the distance delta**

Add the `speed` parameter to `input.adjust_distance` and replace the hard-coded `0.05` multiplier with it. Pass `settings.zoomSpeed` from `camera.lua`. Preserve modifier gating, vertical inversion independence, and min/max clamping.

- [x] **Step 5: Run the focused test and syntax checks**

Run: `lua tests\zoom_modifier_test.lua; luac -p config.lua input.lua camera.lua radgamepad.lua`  
Expected: Test passes and Lua parsing succeeds.

### Task 3: Investigate the true projection FOV path

**Files:**
- No files until a validated projection FOV site and stock value are found.

**Interfaces:**
- Outcome: research the client projection path without writing memory. Only after a specific site and stock FOV value are validated may the module, config controls, or memory writes be designed.

- [x] **Step 1: Determine the client's actual projection/FOV path before coding**

Inspect a supported `FFXiMain.dll` or live-client read-only data and determine the projection value(s), units, stock third-person value, and code sites that consume them. The local install contains `FFXiMain.dll`, but the published XICamera camera analysis for the available camera patch model explicitly lists FOV as a candidate, not implemented. The binary alone does not establish a safe projection target or stock FOV value. If a validated site cannot be established, stop this task before writing memory code or adding nonfunctional FOV settings; report what evidence is missing.

- [ ] **Step 2: Deferred until a validated FOV site exists**

No test is written until a safe memory interface and validated site exist.

- [ ] **Step 3: Deferred until a validated FOV site exists**

No command. Do not add nonfunctional FOV settings or speculative memory code.

- [ ] **Step 4: Deferred until a validated FOV site exists**

No FOV module is implemented until the missing site evidence is available.

- [ ] **Step 5: Deferred until a validated FOV site exists**

No FOV controls are added until the FOV path can be validated.

- [ ] **Step 6: Deferred until FOV implementation exists**

No FOV test or module exists until the patch target is validated.

- [ ] **Step 7: Deferred until FOV implementation exists**

No in-game FOV verification is possible until a safe patch target and stock projection value are established.

### Task 4: Update addon documentation

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Delivered Zoom Speed behavior and the FOV investigation result.
- Produces: User-facing documentation for the Zoom Speed slider and the current FOV limitation.

- [x] **Step 1: Document the new controls and behavior**

Update the configuration section to describe Zoom Speed and state that no FOV control is exposed until a safe projection patch point is established. Remove references to the deleted temporary diagnostic displays.

- [x] **Step 2: Review documentation against the implemented defaults and ranges**

Check that the documented Zoom Speed default/range match `config.lua` and the README accurately describes the FOV limitation.
