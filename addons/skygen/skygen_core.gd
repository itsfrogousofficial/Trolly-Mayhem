@tool
class_name SkyGenCore
extends RefCounted
## Pure generator: parameters in, Image out. No editor dependencies, so it also runs headless and at runtime.
##
## The output is an equirectangular panorama (width = 2 x height) for Godot's PanoramaSkyMaterial.
## Every layer samples 3D noise or directions on the sphere, so the image is seamless at the left/right edge
## and has no visible pinch at the poles beyond the usual equirectangular stretch.

## LITE build: width capped at 1024, nebula and cloud layers off, three presets. The build script flips this.
const LITE := true
const LITE_MAX_WIDTH := 1024
const FULL_MAX_WIDTH := 4096


static func default_params() -> Dictionary:
	return {
		"width": 2048,
		"seed": 1,
		"zenith_color": Color(0.16, 0.36, 0.78),
		"horizon_color": Color(0.80, 0.88, 0.97),
		"ground_color": Color(0.30, 0.30, 0.32),
		"gradient_curve": 0.6,   # <1 keeps the horizon band wide; >1 pulls the zenith colour down
		"sun_enabled": true,
		"sun_azimuth_deg": 40.0,
		"sun_elevation_deg": 35.0,
		"sun_size_deg": 2.0,
		"sun_color": Color(1.0, 0.98, 0.90),
		"sun_glow_deg": 25.0,
		"sun_glow_strength": 0.6,
		"stars_enabled": false,
		"star_count": 2500,
		"star_brightness": 1.0,
		"nebula_enabled": false,
		"nebula_color_a": Color(0.55, 0.20, 0.75),
		"nebula_color_b": Color(0.10, 0.45, 0.70),
		"nebula_scale": 1.6,
		"nebula_intensity": 0.7,
		"clouds_enabled": false,
		"cloud_coverage": 0.45,
		"cloud_softness": 0.25,
		"cloud_scale": 3.0,
		"cloud_color": Color(1.0, 1.0, 1.0),
	}


static func preset_names() -> PackedStringArray:
	var names := PackedStringArray(["Clear Day", "Golden Sunset", "Starry Night"])
	if not LITE:
		names.append_array(PackedStringArray(["Purple Nebula", "Alien Dawn", "Overcast"]))
	return names


static func preset(name: String) -> Dictionary:
	var p := default_params()
	match name:
		"Clear Day":
			pass
		"Golden Sunset":
			p.merge({"zenith_color": Color(0.20, 0.22, 0.45), "horizon_color": Color(1.0, 0.55, 0.25),
				"ground_color": Color(0.18, 0.12, 0.10), "gradient_curve": 0.9, "sun_elevation_deg": 4.0,
				"sun_size_deg": 3.0, "sun_color": Color(1.0, 0.80, 0.55), "sun_glow_deg": 40.0,
				"sun_glow_strength": 0.9, "clouds_enabled": not LITE, "cloud_coverage": 0.35,
				"cloud_color": Color(1.0, 0.75, 0.60)}, true)
		"Starry Night":
			p.merge({"zenith_color": Color(0.01, 0.02, 0.06), "horizon_color": Color(0.05, 0.08, 0.16),
				"ground_color": Color(0.02, 0.02, 0.03), "gradient_curve": 0.8, "sun_enabled": false,
				"stars_enabled": true, "star_count": 3500, "star_brightness": 1.0}, true)
		"Purple Nebula":
			p.merge({"zenith_color": Color(0.02, 0.01, 0.05), "horizon_color": Color(0.08, 0.04, 0.14),
				"ground_color": Color(0.02, 0.02, 0.03), "sun_enabled": false, "stars_enabled": true,
				"star_count": 4000, "nebula_enabled": true, "nebula_intensity": 0.85}, true)
		"Alien Dawn":
			p.merge({"zenith_color": Color(0.05, 0.25, 0.22), "horizon_color": Color(0.85, 0.45, 0.70),
				"ground_color": Color(0.12, 0.10, 0.14), "gradient_curve": 0.7, "sun_elevation_deg": 8.0,
				"sun_size_deg": 5.0, "sun_color": Color(0.75, 1.0, 0.85), "sun_glow_deg": 30.0,
				"sun_glow_strength": 0.7, "stars_enabled": true, "star_count": 1200, "star_brightness": 0.6,
				"nebula_enabled": true, "nebula_color_a": Color(0.20, 0.60, 0.50),
				"nebula_color_b": Color(0.60, 0.20, 0.45), "nebula_intensity": 0.45}, true)
		"Overcast":
			p.merge({"zenith_color": Color(0.45, 0.48, 0.52), "horizon_color": Color(0.75, 0.77, 0.80),
				"ground_color": Color(0.25, 0.25, 0.26), "gradient_curve": 0.5, "sun_enabled": true,
				"sun_elevation_deg": 50.0, "sun_size_deg": 0.0, "sun_glow_deg": 35.0, "sun_glow_strength": 0.25,
				"clouds_enabled": true, "cloud_coverage": 0.85, "cloud_softness": 0.35, "cloud_scale": 2.2,
				"cloud_color": Color(0.92, 0.93, 0.95)}, true)
	return p


## Clamp parameters to what this build allows. Returns a copy.
static func sanitize(params: Dictionary) -> Dictionary:
	var p := default_params()
	p.merge(params, true)
	var max_w := LITE_MAX_WIDTH if LITE else FULL_MAX_WIDTH
	p["width"] = clampi(int(p["width"]), 256, max_w)
	if int(p["width"]) % 2 == 1:
		p["width"] = int(p["width"]) + 1
	if LITE:
		p["nebula_enabled"] = false
		p["clouds_enabled"] = false
	p["star_count"] = clampi(int(p["star_count"]), 0, 20000)
	p["cloud_coverage"] = clampf(float(p["cloud_coverage"]), 0.0, 1.0)
	p["cloud_softness"] = clampf(float(p["cloud_softness"]), 0.01, 1.0)
	return p


## Generate the panorama. Returns an RGB8 Image of width x (width / 2).
static func generate(params: Dictionary) -> Image:
	var p := sanitize(params)
	var w: int = int(p["width"])
	var h: int = w / 2
	var zen: Color = p["zenith_color"]
	var hor: Color = p["horizon_color"]
	var gnd: Color = p["ground_color"]
	var curve: float = maxf(0.05, float(p["gradient_curve"]))

	var sun_on: bool = p["sun_enabled"]
	var sun_dir := _dir_from_angles(float(p["sun_azimuth_deg"]), float(p["sun_elevation_deg"]))
	var sun_r := deg_to_rad(maxf(0.0, float(p["sun_size_deg"])) * 0.5)
	var glow_r := deg_to_rad(maxf(0.1, float(p["sun_glow_deg"])))
	var glow_s: float = float(p["sun_glow_strength"])
	var sun_c: Color = p["sun_color"]

	var neb_on: bool = p["nebula_enabled"]
	var cld_on: bool = p["clouds_enabled"]
	var noise_n: FastNoiseLite
	var noise_c: FastNoiseLite
	if neb_on:
		noise_n = FastNoiseLite.new()
		noise_n.seed = int(p["seed"]) * 7 + 1
		noise_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise_n.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise_n.fractal_octaves = 5
		noise_n.fractal_lacunarity = 2.2
		noise_n.fractal_gain = 0.55
		noise_n.frequency = 0.12
	if cld_on:
		noise_c = FastNoiseLite.new()
		noise_c.seed = int(p["seed"]) * 13 + 5
		noise_c.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise_c.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise_c.fractal_octaves = 5
		noise_c.fractal_lacunarity = 2.0
		noise_c.fractal_gain = 0.5
		noise_c.frequency = 0.14
	var neb_a: Color = p["nebula_color_a"]
	var neb_b: Color = p["nebula_color_b"]
	var neb_scale: float = float(p["nebula_scale"])
	var neb_int: float = float(p["nebula_intensity"])
	var cov: float = float(p["cloud_coverage"])
	var soft: float = float(p["cloud_softness"])
	var cscale: float = float(p["cloud_scale"])
	var ccol: Color = p["cloud_color"]

	var data := PackedByteArray()
	data.resize(w * h * 3)
	var idx := 0
	for y in h:
		var v := (float(y) + 0.5) / float(h)          # 0 top .. 1 bottom
		var lat := (0.5 - v) * PI                      # +PI/2 zenith .. -PI/2 nadir
		var e := sin(lat)                              # -1 .. 1 (0 at the horizon)
		var cos_lat := cos(lat)
		var sin_lat := sin(lat)
		# Base gradient for this row (depends on latitude only).
		var base: Color
		if e >= 0.0:
			base = hor.lerp(zen, pow(e, curve))
		else:
			base = hor.lerp(gnd, pow(-e, 1.5))
		for x in w:
			var u := (float(x) + 0.5) / float(w)
			var lon := u * TAU
			var dx := cos_lat * sin(lon)
			var dy := sin_lat
			var dz := cos_lat * cos(lon)
			var r := base.r
			var g := base.g
			var b := base.b
			if neb_on:
				var ns := neb_scale * 10.0
				var n := noise_n.get_noise_3d(dx * ns, dy * ns, dz * ns)
				# large-scale mask so the nebula sits in patches instead of covering the whole sky
				var mask := clampf(noise_n.get_noise_3d(dx * 2.5 + 77.0, dy * 2.5, dz * 2.5) * 1.6 + 0.55, 0.0, 1.0)
				var m := clampf((n + 0.45) * 1.1, 0.0, 1.0)
				m = m * m * mask * neb_int
				var mix2 := clampf(noise_n.get_noise_3d(dz * 4.0 + 31.0, dx * 4.0, dy * 4.0) * 0.5 + 0.5, 0.0, 1.0)
				var nc := neb_a.lerp(neb_b, mix2)
				r += nc.r * m
				g += nc.g * m
				b += nc.b * m
			if cld_on and e > -0.02:
				var cs := cscale * 10.0
				var cn := noise_c.get_noise_3d(dx * cs, dy * cs * 0.6, dz * cs) * 0.5 + 0.5
				var t := (cn - (1.0 - cov)) / soft
				var a := clampf(t, 0.0, 1.0)
				a *= clampf(e * 8.0, 0.0, 1.0)      # fade out at the horizon
				if a > 0.0:
					var shade := 0.72 + 0.28 * clampf((cn - (1.0 - cov)) / maxf(soft, 0.05), 0.0, 1.0)
					r = lerpf(r, ccol.r * shade, a)
					g = lerpf(g, ccol.g * shade, a)
					b = lerpf(b, ccol.b * shade, a)
			if sun_on:
				var d := acos(clampf(dx * sun_dir.x + dy * sun_dir.y + dz * sun_dir.z, -1.0, 1.0))
				if d < sun_r:
					var boost := 1.0 + glow_s
					r = sun_c.r * boost
					g = sun_c.g * boost
					b = sun_c.b * boost
				else:
					var gl := exp(-(d - sun_r) / glow_r * 3.0) * glow_s
					if gl > 0.001:
						r += sun_c.r * gl
						g += sun_c.g * gl
						b += sun_c.b * gl
			data[idx] = int(clampf(r, 0.0, 1.0) * 255.0)
			data[idx + 1] = int(clampf(g, 0.0, 1.0) * 255.0)
			data[idx + 2] = int(clampf(b, 0.0, 1.0) * 255.0)
			idx += 3
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)
	if bool(p["stars_enabled"]) and int(p["star_count"]) > 0:
		_splat_stars(img, int(p["seed"]), int(p["star_count"]), float(p["star_brightness"]))
	return img


static func _dir_from_angles(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()


## Stars are placed as random directions on the sphere, then projected, so density is even across the sky
## instead of bunching at the poles. Brighter stars get a small cross so they read at 2:1 panorama scale.
static func _splat_stars(img: Image, seed: int, count: int, brightness: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 1000003 + 17
	var w := img.get_width()
	var h := img.get_height()
	for i in count:
		var z := rng.randf_range(-1.0, 1.0)
		var t := rng.randf_range(0.0, TAU)
		var rr := sqrt(maxf(0.0, 1.0 - z * z))
		var dir := Vector3(rr * sin(t), z, rr * cos(t))
		if dir.y < -0.05:
			continue
		var lon := atan2(dir.x, dir.z)
		if lon < 0.0:
			lon += TAU
		var lat := asin(clampf(dir.y, -1.0, 1.0))
		var px := int(lon / TAU * w) % w
		var py := clampi(int((0.5 - lat / PI) * h), 0, h - 1)
		var mag := rng.randf()
		mag = mag * mag * mag
		var bri := clampf((0.45 + 0.55 * mag) * brightness, 0.0, 1.0)
		var tint := rng.randf()
		var c := Color(1.0, 1.0, 1.0)
		if tint < 0.15:
			c = Color(0.75, 0.85, 1.0)
		elif tint > 0.9:
			c = Color(1.0, 0.85, 0.70)
		_add_pixel(img, px, py, c, bri)
		if mag > 0.6 and w >= 1024:
			var side := bri * 0.45
			_add_pixel(img, (px + 1) % w, py, c, side)
			_add_pixel(img, (px - 1 + w) % w, py, c, side)
			if py > 0:
				_add_pixel(img, px, py - 1, c, side)
			if py < h - 1:
				_add_pixel(img, px, py + 1, c, side)


static func _add_pixel(img: Image, x: int, y: int, c: Color, amount: float) -> void:
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(minf(1.0, o.r + c.r * amount), minf(1.0, o.g + c.g * amount), minf(1.0, o.b + c.b * amount)))


## Save the image as PNG and a PanoramaSkyMaterial next to it. Returns the material path or "" on error.
static func save_png_and_material(img: Image, png_path: String, make_material: bool = true) -> String:
	var err := img.save_png(png_path)
	if err != OK:
		push_error("SkyGen: could not save %s (error %d)" % [png_path, err])
		return ""
	if not make_material:
		return png_path
	var tex := ImageTexture.create_from_image(img)
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = tex
	var mat_path := png_path.get_basename() + "_sky.tres"
	# Inside the editor the PNG becomes an imported resource; the material should reference that, so
	# the dock re-points it after the filesystem scan. Headless/runtime keeps the embedded texture.
	err = ResourceSaver.save(mat, mat_path)
	if err != OK:
		push_error("SkyGen: could not save %s (error %d)" % [mat_path, err])
		return ""
	return mat_path
