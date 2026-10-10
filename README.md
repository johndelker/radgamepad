# Rad Gamepad

Standalone Ashita camera addon extracted from SlowCircuit's moderncam. Includes right-stick rotation, exploration and lock-on distance/offsets, sensitivity, inversion, zone reset and the original collision correction.

Copy this entire folder into `PhoenixXI/addons/radgamepad`. Unload moderncam before using this replacement:

```text
/addon unload moderncam
/addon load radgamepad
/radgamepad
```

`/radgamepad` opens or closes the configuration window. Settings save in `radgamepad.ini` through Ashita's configuration manager. Original camera defaults are preserved: distance 6, exploration offsets 1/1, lock-on offsets 0/0, sensitivity 1 and inversion disabled.

Target selection and bumper bindings belong to bettertarget, which is optional. This addon does not hide any HUD elements.

The Zoom Modifier defaults to the XInput left trigger. Use Bind to capture another XInput/DirectInput button or trigger. XInput LT/RT button events (IDs 16/17) and analog trigger state are supported. Radgamepad observes modifier input without blocking it, so other addons and the game can also use the button. Hold it and move the right stick up to zoom in or down to zoom out; this direction ignores the vertical inversion setting. Zoom changes the distance for the current camera mode and saves that distance when the modifier is released.
Zoom Speed scales how quickly the camera distance changes, from 0.05 to 0.50 per frame; the default 0.05 preserves the previous rate. The current client camera analysis does not identify a safe projection FOV patch point, so Radgamepad does not expose FOV controls yet.

Requires Ashita's LuaJIT, common, imgui, and an XInput controller enabled in Ashita. Camera rotation reads the right stick through Ashita input. Validate right-stick input, zoom binding and direction, wall collisions, lock-on offsets, first-person switching and zoning in FFXI; tests cover axis math, not game memory signatures or live collision behavior.
