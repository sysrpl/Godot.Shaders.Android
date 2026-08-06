// title: flythrough

shader_type canvas_item;

const float FAR = 50.0;

uniform sampler2D iChannel0 : source_color;
uniform samplerCube iChannel1 : source_color;

// Tri-Planar blending function. Based on an old Nvidia writeup:
// GPU Gems 3 - Ryan Geiss: https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch01.html
vec3 tex3D(sampler2D t, in vec3 p, in vec3 n)
{
	n = max(abs(n), 0.001);
	n /= dot(n, vec3(1.0));
	vec3 tx = texture(t, p.yz).xyz;
	vec3 ty = texture(t, p.zx).xyz;
	vec3 tz = texture(t, p.xy).xyz;

	// Textures are stored in sRGB (I think), so you have to convert them to linear space
	// (squaring is a rough approximation) prior to working with them... or something like that.
	// Once the final color value is gamma corrected, you should see correct looking colors.
	return (tx * tx * n.x + ty * ty * n.y + tz * tz * n.z);
}

// The camera path: There are a few spline setups on Shadertoy, but this one is a slight variation of
// Otavio Good's spline setup in his "Alien Beacon" shader: https://www.shadertoy.com/view/ld2SzK
//
// Spline point markers ("cp" for camera point). The camera visits each point in succession, then loops
// back to the first point, when complete, in order to repeat the process. In case it isn't obvious, each
// point represents an open space juncture in the object that links to the previous and next point.
// Of course, running a camera in a straight line between points wouldn't produce a smooth camera effect,
// so we apply the Catmull-Rom equation to the line segment.
void setCamPath(out vec3 cp[16])
{
	// The larger fractal object has nodes in a 4x4x4 grid.
	// The smaller one in a 2x2x2 grid. The following points
	// map a path to various open areas throughout the object.
	const float sl = 2.0 * 0.96;
	const float bl = 4.0 * 0.96;

	cp[0] = vec3(0.0, 0.0, 0.0);
	cp[1] = vec3(0.0, 0.0, bl);
	cp[2] = vec3(sl, 0.0, bl);
	cp[3] = vec3(sl, 0.0, sl);
	cp[4] = vec3(sl, sl, sl);
	cp[5] = vec3(-sl, sl, sl);
	cp[6] = vec3(-sl, 0.0, sl);
	cp[7] = vec3(-sl, 0.0, 0.0);

	cp[8] = vec3(0.0, 0.0, 0.0);
	cp[9] = vec3(0.0, 0.0, -bl);
	cp[10] = vec3(0.0, bl, -bl);
	cp[11] = vec3(-sl, bl, -bl);
	cp[12] = vec3(-sl, 0.0, -bl);
	cp[13] = vec3(-sl, 0.0, 0.0);
	cp[14] = vec3(-sl, -sl, 0.0);
	cp[15] = vec3(0.0, -sl, 0.0);
}

// Standard Catmull-Rom equation. The equation takes in the line segment end points (p1 and p2), the
// points on either side (p0 and p3), the current fractional distance (t) along the segment, then
// returns the the smooth (cubic interpolated) position. The end result is a smooth transition
// between points... Look up a diagram on the internet. That should make it clearer.
vec3 Catmull(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t)
{
	return (((-p0 + p1 * 3.0 - p2 * 3.0 + p3) * t * t * t + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t * t + (-p0 + p2) * t + p1 * 2.0) * 0.5);
}

// Camera path. Determine the segment number (segNum), and how far - timewise - we are along it (segTime).
// Feed the segment, the appropriate adjoining segments, and the segment time into the Catmull-Rom
// equation to produce a camera position. The process is pretty simple, once you get the hang of it.
vec3 camPath(float t)
{
	vec3 cp[16];
	setCamPath(cp);

	const int aNum = 16;

	t = fract(t / float(aNum)) * float(aNum); // Repeat every 16 time units.

	// Segment number. Range: [0, 15], in this case.
	float segNum = floor(t);
	// Segment portion. Analogous to how far we are alone the individual line segment. Range: [0, 1].
	float segTime = t - segNum;

	if (segNum == 0.0)
	{
		return Catmull(cp[aNum - 1], cp[0], cp[1], cp[2], segTime);
	}

	for (int i = 1; i < aNum - 2; i++)
	{
		if (segNum == float(i))
		{
			return Catmull(cp[i - 1], cp[i], cp[i + 1], cp[i + 2], segTime);
		}
	}

	if (segNum == float(aNum - 2))
	{
		return Catmull(cp[aNum - 3], cp[aNum - 2], cp[aNum - 1], cp[0], segTime);
	}
	if (segNum == float(aNum - 1))
	{
		return Catmull(cp[aNum - 2], cp[aNum - 1], cp[0], cp[1], segTime);
	}

	return vec3(0.0);
}

// Smooth minimum function. There are countless articles, but IQ explains it best here:
// https://iquilezles.org/articles/smin
float sminP(float a, float b, float s)
{
	float h = clamp(0.5 + 0.5 * (b - a) / s, 0.0, 1.0);
	return mix(b, a, h) - s * h * (1.0 - h);
}

// Creating the scene geometry.
//
// There are two intertwined fractal objects. One is a gold and timber lattice, spread out in a 4x4x4
// grid. The second is some metallic tubing spread out over a 2x2x2 grid. Each are created by combining
// repeat objects with various operations. All of it is pretty standard.
//
// objID identifies individual scene objects: Wood = 1., Metal = 2., Gold = 3.
float map(in vec3 q, out float objID)
{
	// The grey section.
	// Layer one.
	vec3 p = abs(fract(q / 4.0) * 4.0 - 2.0);
	float tube = min(max(p.x, p.y), min(max(p.y, p.z), max(p.x, p.z))) - 4.0 / 3.0 - 0.015;

	// Layer two.
	p = abs(fract(q / 2.0) * 2.0 - 1.0);
	tube = max(tube, sminP(max(p.x, p.y), sminP(max(p.y, p.z), max(p.x, p.z), 0.05), 0.05) - 2.0 / 3.0);

	// The gold and timber paneling.
	//
	// A bit of paneling, using a combination of repeat objects. We're doing it here in layer two, just
	// to save an extra "fract" call.
	float panel = sminP(max(p.x, p.y), sminP(max(p.y, p.z), max(p.x, p.z), 0.125), 0.125) - 0.5;

	// Gold strip. Identifying the gold strip region, then edging it out a little.
	float strip = step(p.x, 0.75) * step(p.y, 0.75) * step(p.z, 0.75);
	panel -= (strip) * 0.025;

	// Repeat field entity two, which is just an abstract object repeated every half unit.
	p = abs(fract(q * 2.0) * 0.5 - 0.25);
	float pan2 = min(p.x, min(p.y, p.z)) - 0.05;

	// Combining the two entities above.
	panel = max(abs(panel), abs(pan2)) - 0.0425;

	// Layer three. 3D space is divided by three.
	p = abs(fract(q * 1.5) / 1.5 - 1.0 / 3.0);
	tube = max(tube, min(max(p.x, p.y), min(max(p.y, p.z), max(p.x, p.z))) - 2.0 / 9.0 + 0.025);

	// Layer three. 3D space is divided by two, instead of three, to give some variance.
	p = abs(fract(q * 3.0) / 3.0 - 1.0 / 6.0);
	tube = max(tube, min(max(p.x, p.y), min(max(p.y, p.z), max(p.x, p.z))) - 1.0 / 9.0 - 0.035);

	// Object ID: Equivalent to: if(tube<panel)objID=2; else objID = 1.; //etc.
	objID = 1.0 + step(tube, panel) + step(panel, tube) * (strip) * 2.0;

	return min(panel, tube);
}

// Overload for callers (normal/AO) that don't need the material ID.
float map(in vec3 q)
{
	float objID;
	return map(q, objID);
}

float trace(in vec3 ro, in vec3 rd, out float hitObjID)
{
	float t = 0.0;
	float h;
	float id = 0.0;
	for (int i = 0; i < 92; i++)
	{
		h = map(ro + rd * t, id);
		// Note the "t*b + a" addition. Basically, we're putting less emphasis on accuracy, as
		// "t" increases. It's a cheap trick that works in most situations... Not all, though.
		if (abs(h) < 0.001 * (t * 0.25 + 1.0) || t > FAR)
		{
			break;
		}
		t += h * 0.8;
	}

	hitObjID = id;
	return t;
}

// The reflections are pretty subtle, so not much effort is being put into them. Only 16 iterations.
float refTrace(vec3 ro, vec3 rd, out float hitObjID)
{
	float t = 0.0;
	float id = 0.0;
	for (int i = 0; i < 16; i++)
	{
		float d = map(ro + rd * t, id);
		if (d < 0.0025 * (t * 0.25 + 1.0) || t > FAR)
		{
			break;
		}
		t += d;
	}
	hitObjID = id;
	return t;
}

// Standard normal function. It's not as fast as a tetrahedral calculation, but more symmetrical. Due to
// the intricacies of this particular scene, it's kind of needed to reduce jagged effects.
vec3 calcNormal(in vec3 p)
{
	const vec2 e = vec2(0.005, 0.0);
	return normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx)));
}

// I keep a collection of occlusion routines. This one is likely based on IQ's original.
float calcAO(in vec3 pos, in vec3 nor)
{
	float sca = 2.0;
	float occ = 0.0;
	for (int i = 0; i < 5; i++)
	{
		float hr = 0.01 + float(i) * 0.5 / 4.0;
		float dd = map(nor * hr + pos);
		occ += (hr - dd) * sca;
		sca *= 0.7;
	}
	return clamp(1.0 - occ, 0.0, 1.0);
}

// Texture bump mapping. Four tri-planar lookups, or 12 texture lookups in total.
vec3 texBump(sampler2D tx, in vec3 p, in vec3 n, float bf)
{
	const vec2 e = vec2(0.001, 0.0);

	// Three gradient vectors rolled into a matrix, constructed with offset greyscale texture values.
	mat3 m = mat3(tex3D(tx, p - e.xyy, n), tex3D(tx, p - e.yxy, n), tex3D(tx, p - e.yyx, n));

	vec3 g = vec3(0.299, 0.587, 0.114) * m; // Converting to greyscale.
	g = (g - dot(tex3D(tx, p, n), vec3(0.299, 0.587, 0.114))) / e.x;
	g -= n * dot(n, g);

	return normalize(n + g * bf); // Bumped normal. "bf" - bump factor.
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = UV * resolution;

	// Screen coordinates.
	vec2 u = (fragCoord - resolution * 0.5) / resolution.y;

	float speed = TIME * 0.35 + 8.0;

	// Camera Setup.
	vec3 ro = camPath(speed); // Camera position, doubling as the ray origin.
	vec3 lk = camPath(speed + 0.5); // "Look At" position.
	vec3 lp = camPath(speed + 0.5) + vec3(0.0, 0.25, 0.0); // Light position, somewhere near the moving camera.

	// Using the above to produce the unit ray-direction vector.
	float fov = 1.57;
	vec3 fwd = normalize(lk - ro);
	vec3 rgt = normalize(vec3(fwd.z, 0.0, -fwd.x));
	vec3 up = (cross(fwd, rgt));

	// Unit direction ray.
	vec3 rd = normalize(fwd + fov * (u.x * rgt + u.y * up));

	// Raymarch the scene.
	float hitObjID;
	float t = trace(ro, rd, hitObjID);

	// Initialize the scene color.
	vec3 col = vec3(0.0);

	// Scene hit, so color the pixel.
	if (t < FAR)
	{
		float ts = 1.0; // Texture scale.

		// Needs to be saved just after the raymarching call, since other map() calls (normal, AO, bump)
		// would otherwise clobber it with the ID at a different sample point.
		float saveObjID = hitObjID;

		vec3 pos = ro + rd * t; // Scene postion.
		vec3 nor = calcNormal(pos); // Normal.
		vec3 sNor = nor;

		// Apply some subtle texture bump mapping to the panels and the metal tubing.
		nor = texBump(iChannel0, pos * ts, nor, 0.0015);

		// Reflected ray. Note that the normal is only half bumped. It's fake, but it helps
		// taking some of the warping effect off of the reflections.
		vec3 ref = reflect(rd, normalize(sNor * 0.5 + nor * 0.5));

		col = tex3D(iChannel0, pos * ts, nor); // Texture pixel at the scene postion.

		vec3 li = lp - pos; // Point light.
		float lDist = max(length(li), 0.001); // Surface to light distance.
		float atten = 1.0 / (1.0 + lDist * 0.125 + lDist * lDist * 0.05); // Light attenuation.
		li /= lDist; // Normalizing the point light vector.

		float occ = calcAO(pos, nor); // Occlusion.

		float dif = clamp(dot(nor, li), 0.0, 1.0); // Diffuse.
		dif = pow(dif, 4.0) * 2.0;
		float spe = pow(max(dot(reflect(-li, nor), -rd), 0.0), 8.0); // Object specular.
		float spe2 = spe * spe; // Global specular.

		float refl = 0.35; // Reflection coefficient. Different for different materials.

		// Reflection color. Mostly fake.
		float rt = refTrace(pos + ref * 0.1, ref, hitObjID); // Raymarch from "pos" in the reflected direction.
		float rSaveObjID = hitObjID; // IDs change with reflection.
		vec3 rsp = pos + ref * rt; // Reflected surface hit point.
		vec3 rsn = calcNormal(rsp); // Normal at the reflected surface. Too costly to bump reflections.
		vec3 rCol = tex3D(iChannel0, rsp * ts, rsn); // Texel at "rsp."
		vec3 rLi = lp - rsp;
		float rlDist = max(length(rLi), 0.001);
		rLi /= rlDist;
		float rDiff = max(dot(rsn, rLi), 0.0); // Diffuse light at "rsp."
		rDiff = pow(rDiff, 4.0) * 2.0;
		float rAtten = 1.0 / (1.0 + rlDist * 0.125 + rlDist * rlDist * 0.05);

		if (rSaveObjID > 1.5 && rSaveObjID < 2.5)
		{
			rCol = dot(rCol, vec3(0.299, 0.587, 0.114)) * 0.7 + rCol * 0.15;
		}

		if (rSaveObjID > 2.5)
		{
			vec3 rFire = pow(vec3(1.5, 1.0, 1.0) * rCol, vec3(8.0, 2.0, 1.5));
			rCol = rCol + min(mix(vec3(1.5, 0.9, 0.375), vec3(0.75, 0.375, 0.3), rFire), 2.0) * 0.5;
		}

		// Grey metal inner tubing.
		if (saveObjID > 1.5)
		{
			// Grey out the limestone wall color.
			col = vec3(1.0) * dot(col, vec3(0.299, 0.587, 0.114)) * 0.7 + col * 0.15;

			refl = 1.0;

			rDiff *= saveObjID > 2.5 ? 1.0 : 2.0;
		}

		rCol *= (rDiff + 0.15) * rAtten; // Reflected color. Not accurate, but close enough.

		// Gold trimming properties.
		if (saveObjID > 2.5)
		{
			vec3 fire = pow(vec3(1.5, 1.0, 1.0) * col, vec3(8.0, 2.0, 1.5));
			col = col + min(mix(vec3(1.0, 0.9, 0.375), vec3(0.75, 0.375, 0.3), fire), 2.0) * 0.5;

			refl = 0.65;
		}

		// Combining everything together to produce the scene color.
		col = col * (dif + 0.25 + vec3(0.35, 0.45, 0.5) * spe) + vec3(0.7, 0.9, 1.0) * spe2;
		col += rCol * refl;

		{
			// Specular reflection -- requires the "Forest" cube map (iChannel1).
			float speR = pow(max(dot(normalize(li - rd), nor), 0.0), 5.0);
			vec3 rf = reflect(rd, nor); // Surface reflection.
			vec3 rTx = texture(iChannel1, rf).xyz;
			rTx *= rTx;
			float rF = saveObjID > 1.5 ? 4.0 : 1.0;
			col += col * rTx * speR * rF;
		}

		col *= occ * atten; // Applying occlusion.
	}

	// Applying some very slight fog in the distance.
	col = mix(max(col, 0.0), vec3(0.0), 1.0 - exp(-t * t / FAR / FAR * 20.0));

	// Done.
	COLOR = vec4(sqrt(max(col, 0.0)), 1.0);
}
