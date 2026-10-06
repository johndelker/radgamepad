# Rad Gamepad

Standalone Ashita camera addon extracted from SlowCircuit's moderncam. Includes right-stick rotation, exploration and lock-on distance/offsets, sensitivity, inversion, zone reset and the original collision correction.

Copy this entire folder, including SDL2.dll, into `PhoenixXI/addons/radgamepad`. Unload moderncam before using this replacement:

```text
/addon unload moderncam
/addon load radgamepad
/radgamepad
```

`/radgamepad` opens or closes the configuration window. Settings save in `radgamepad.ini` through Ashita's configuration manager. Original camera defaults are preserved: distance 6, exploration offsets 1/1, lock-on offsets 0/0, sensitivity 1 and inversion disabled.

Target selection and bumper bindings belong to bettertarget, which is optional. This addon does not hide any HUD elements.

Requires Ashita's LuaJIT, common, imgui, and an SDL-compatible controller. The supplied SDL2.dll is copied unchanged from moderncam. Validate right-stick input, wall collisions, lock-on offsets, first-person switching, zoning and controller hotplug in FFXI; mocked tests cannot prove game memory signatures or live collision behavior.
