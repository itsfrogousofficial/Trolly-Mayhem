# SkyGen: Procedural Skybox Generator for Godot 4 LITE (free)

Generate seamless equirectangular skybox textures from an editor dock: gradient sky, sun disc and glow,
stars. Save as PNG plus a ready PanoramaSkyMaterial, or call the generator from a script at runtime.

## Install
1. Copy the `addons/skygen` folder into your project's `addons/` folder.
2. Project > Project Settings > Plugins > enable "SkyGen: Procedural Skybox Generator".
3. The SkyGen dock appears in the right dock panel (next to Inspector).

## Use
- Pick a preset, press Preview, adjust sliders and colours, press Preview again.
- Set "Save as" (default `res://skies/skygen_sky.png`) and press Generate and save.
  A `<name>_sky.tres` PanoramaSkyMaterial is written next to the PNG; drag it into a WorldEnvironment's
  Environment > Sky > Sky Material.
- Same seed and settings always give the same image. "Random seed" rolls a new one.

## From code (runtime or tool scripts)
```gdscript
var p := SkyGenCore.preset("Starry Night")
p["seed"] = 42
p["width"] = 2048
var img := SkyGenCore.generate(p)          # Image, width x width/2
SkyGenCore.save_png_and_material(img, "user://sky.png")
```

## Limits
LITE: output width up to 1024, three presets (Clear Day, Golden Sunset, Starry Night), no nebula or cloud layers.
Generation is CPU-side GDScript: about 1 s per 1024x512 for a plain sky, longer with nebula and clouds
(a 4096x2048 sky with all layers can take a minute). Width must be even; height is always width / 2.

## Compatibility
Godot 4.2 to 4.5 (tested headless on 4.5). No GDExtension, no shaders: works on every renderer.

## Disclosure
Written with AI assistance (Claude), designed and verified by TheKnightShift. Every output is procedural;
no photographs or third-party textures are used.

More from the same publisher on itch.io: the full SkyGen (nebula and cloud layers, 2K/4K output, six presets) at https://the-knightshift.itch.io/skygen and six free ready-made skies, the Skybox Sampler, at https://the-knightshift.itch.io/skybox-sampler
