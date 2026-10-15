# CITY UPLINK hologram

Replaces the translucent sphere with a rotating cyan vector Earth: latitude/longitude tubes, pulsing equator, intersection beacons, 2,970 continent points, ten communication hubs with radial needles, and elevated network arcs. Coastlines are simplified geographic polygons embedded in `planetary_uplink.gd`; no external textures or downloads are needed.

A longitude scanner brightens data and leaves an exponential phosphor trail. Three energy rings travel upward across the sphere. Three independently rotating, tilted orbital rings carry circuit ticks. A faint projector cone anchors the hologram to the original pedestal. Rear-facing geometry is dimmed for depth. Geometry is built once in batched meshes; animation updates transforms and shader uniforms.

Verification: native Godot 4.7.2 Forward+ / Metal render completed without script or shader errors. `uplink_review.gd` checks continent density, three gyros and pulses, upward pulse motion, opposing gyro rotation, planet rotation, and finite pulse radii. Close, pedestrian-height, and existing plaza overview captures were inspected. The ten-second 1440×900 H.264 preview contains 240 frames at 24 fps and passed full video decoding. This review runs without the simulation backend or save writes.

Run stills/checks:

```sh
godot --path godot --script res://scripts/uplink_review.gd -- --no-simulation
```

Record source video:

```sh
godot --path godot --script res://scripts/uplink_review.gd --write-movie /tmp/brother-eye-uplink.avi --fixed-fps 24 --disable-vsync -- --no-simulation --uplink-movie
```

The first second is a warmup; `city-uplink.mp4` contains the following ten seconds of animation.
