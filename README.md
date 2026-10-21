# ModernCam

Standalone Ashita camera addon extracted from SlowCircuit's moderncam. Includes controller, keyboard, and mouse camera rotation; exploration and lock-on distance/offsets; sensitivity; inversion; and zone reset.

Copy this entire folder into `PhoenixXI/addons/moderncam`. Unload any older camera addon before using it:

```text
/addon unload radgamepad
/addon load moderncam
/moderncam
```

`/moderncam` and `/mc` open or close the configuration window. Use `/mc log <label>` to append a labeled camera-distance difference to `config/addons/moderncam_camera_distance.log`; each line records both distances and their signed difference (ModernCam - vanilla). Use `/mc watch <label>` to append a sample each frame under that label; run `/mc watch` again to stop. Settings save in `moderncam.ini`. Existing `radgamepad.ini` settings migrate automatically the first time ModernCam loads. Original camera defaults are preserved: distance 6, exploration offsets 1/1, lock-on offsets 0/0 and sensitivity 1. On first setup, inversion defaults are imported from FFXI Third-Person Camera X/Y config values 139/140; saved settings take precedence on later loads.

Target selection and bumper bindings belong to bettertarget, which is optional. This addon does not hide any HUD elements.

The Zoom Modifier defaults to the XInput left trigger. Use Bind to capture another XInput/DirectInput button or trigger. XInput LT/RT button events (IDs 16/17) and analog trigger state are supported. ModernCam observes modifier input without blocking it, so other addons and the game can also use the button. Hold it and move the right stick up to zoom in or down to zoom out; this direction ignores the vertical inversion setting. Zoom changes the distance for the current camera mode and saves that distance when the modifier is released.
Zoom Speed scales how quickly the camera distance changes, from 0.05 to 0.50 per frame; the default 0.05 preserves the previous rate. The current client camera analysis does not identify a safe projection FOV patch point, so ModernCam does not expose FOV controls yet.

Requires Ashita's LuaJIT, common, and imgui. Camera rotation reads the right stick and keyboard/mouse events through Ashita input. Arrow keys are the default keyboard camera bindings, each direction can be rebound in the config, and moving the cursor to a game-window edge pans the camera. ModernCam captures those camera controls while enabled. Validate controller and keyboard/mouse rotation, zoom binding and direction, wall collisions, lock-on offsets, first-person switching and zoning in FFXI; automated tests do not cover live game input or camera memory signatures.
