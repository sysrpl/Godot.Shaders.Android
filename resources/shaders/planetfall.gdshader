shader_type canvas_item;

// AA=2 in the source's "normal hardware" branch (the HW_PERFORMANCE==0 low-
// power branch dropped to AA=1); HW_PERFORMANCE doesn't exist outside
// Shadertoy, so this is just fixed at the real-antialiasing value.
const int AA = 2;

mat3 makeBase(in vec3 w)
{
	float k = inversesqrt(1.0 - w.y * w.y);
	return mat3(vec3(-w.z, 0.0, w.x) * k,
			vec3(-w.x * w.y, 1.0 - w.y * w.y, -w.y * w.z) * k,
			w);
}

// https://iquilezles.org/articles/intersectors
vec2 sphIntersect(in vec3 ro, in vec3 rd, in float rad)
{
	float b = dot(ro, rd);
	float c = dot(ro, ro) - rad * rad;
	float h = b * b - c;
	if (h < 0.0)
	{
		return vec2(-1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

// https://iquilezles.org/articles/distfunctions
float sdCapsule(in vec3 p, in float b, in float r)
{
	float h = clamp(p.z / b, 0.0, 1.0);
	return length(p - vec3(0.0, 0.0, b) * h) - r;
}

// modified Keinert et al's inverse Spherical Fibonacci Mapping
vec4 inverseSF(in vec3 p, const in float n)
{
	const float PHI = 1.61803398875;

	float phi = min(atan(p.y, p.x), PI);
	float k = max(floor(log(n * PI * sqrt(5.0) * (1.0 - p.z * p.z)) / log(PHI + 1.0)), 2.0);
	float Fk = pow(PHI, k) / sqrt(5.0);
	vec2 F = vec2(round(Fk), round(Fk * PHI));
	vec2 G = PI * (fract((F + 1.0) * PHI) - (PHI - 1.0));

	mat2 iB = mat2(vec2(F.y, -F.x), vec2(G.y, -G.x)) / (F.y * G.x - F.x * G.y);
	vec2 c = floor(iB * 0.5 * vec2(phi, n * p.z - n + 1.0));

	float ma = 0.0;
	vec4 res = vec4(0.0);
	for (int s = 0; s < 4; s++)
	{
		vec2 uv = vec2(float(s & 1), float(s >> 1));
		float i = dot(F, uv + c);
		float phi2 = 2.0 * PI * fract(i * PHI);
		float cT = 1.0 - (2.0 * i + 1.0) / n;
		float sT = sqrt(1.0 - cT * cT);
		vec3 q = vec3(cos(phi2) * sT, sin(phi2) * sT, cT);
		float a = dot(p, q);
		if (a > ma)
		{
			ma = a;
			res.xyz = q;
			res.w = i;
		}
	}
	return res;
}

float map(in vec3 p, out vec4 color, const in bool doColor)
{
	float lp = length(p);
	float dmin = lp - 1.0;
	{
		vec3 w = p / lp;
		vec4 fibo = inverseSF(w, 700.0);
		float hh = 1.0 - smoothstep(0.05, 0.1, length(fibo.xyz - w));
		dmin -= 0.07 * hh;
		color = vec4(0.05, 0.1, 0.1, 1.0) * hh * (1.0 + 0.5 * sin(fibo.w * 111.1));
	}

	float s = 1.0;

	for (int i = 0; i < 3; i++)
	{
		float h = float(i) / float(3 - 1);

		vec4 f = inverseSF(normalize(p), 65.0 + h * 75.0);

		// snap
		p -= f.xyz;

		// orient to surface
		p = p * makeBase(f.xyz);

		// scale
		float scale = 6.6 + 2.0 * sin(111.0 * f.w);
		p *= scale;
		p.xy *= 1.2;

		// translate
		p.z -= 3.0 - length(p.xy) * 0.6 * sin(f.w * 212.1);

		// measure distance
		s *= scale;
		float d = sdCapsule(p, -6.0, 0.42);
		d /= s;

		if (d < dmin)
		{
			if (doColor)
			{
				color.w *= smoothstep(0.0, 5.0 / s, dmin - d);

				if (i == 0)
				{
					color.xyz = vec3(0.425, 0.36, 0.1) * 1.1; // fall
				}

				color.zyx += 0.3 * (1.0 - sqrt(h)) * sin(f.w * 1111.0 + vec3(0.0, 1.0, 2.0));
				color.xyz = max(color.xyz, 0.0);
			}
			dmin = d;
		}
		else
		{
			color.w *= 0.4 * (0.1 + 0.9 * smoothstep(0.0, 1.0 / s, d - dmin));
		}
	}

	return dmin;
}

// https://iquilezles.org/articles/normalsSDF
vec3 calcNormal(in vec3 pos, in float ep)
{
	vec4 kk;
	// Manual finite differences (the source also has a #if-0'd-out
	// dFdx/dFdy fast path that's permanently disabled, so only this one is
	// reachable). The source loops from a runtime-derived "ZERO" instead of
	// a literal 0 as a Shadertoy/WebGL workaround to stop the compiler
	// inlining map() 4x; that's not a concern here, so it's a plain loop.
	vec3 n = vec3(0.0);
	for (int i = 0; i < 4; i++)
	{
		vec3 e = 0.5773 * (2.0 * vec3(float(((i + 3) >> 1) & 1), float((i >> 1) & 1), float(i & 1)) - 1.0);
		n += e * map(pos + e * ep, kk, false);
	}
	return normalize(n);
}

// https://iquilezles.org/articles/rmshadows
float calcSoftshadow(in vec3 ro, in vec3 rd, float tmin, float tmax, const float k)
{
	vec2 bound = sphIntersect(ro, rd, 2.1);
	tmin = max(tmin, bound.x);
	tmax = min(tmax, bound.y);

	float res = 1.0;
	float t = tmin;
	for (int i = 0; i < 50; i++)
	{
		vec4 kk;
		float h = map(ro + rd * t, kk, false);
		res = min(res, k * h / t);
		t += clamp(h, 0.02, 0.20);
		if (res < 0.005 || t > tmax)
		{
			break;
		}
	}
	return clamp(res, 0.0, 1.0);
}

float raycast(in vec3 ro, in vec3 rd, in float tmin, in float tmax, in float resX)
{
	vec4 kk;
	float t = tmin;
	for (int i = 0; i < 512; i++)
	{
		vec3 p = ro + t * rd;
		float h = map(p, kk, false);
		if (abs(h) < (0.15 * t / resX))
		{
			break;
		}
		t += h * 0.5;
		if (t > tmax)
		{
			return -1.0;
		}
	}

	return t;
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = vec2(UV.x, 1.0 - UV.y) * resolution;

	float an = (TIME - 10.0) * 0.05;

	// camera
	vec3 ro = vec3(4.5 * sin(an), 0.0, 4.5 * cos(an));
	vec3 ta = vec3(0.0, 0.0, 0.0);
	// camera-to-world rotation
	mat3 ca = makeBase(normalize(ta - ro));

	// render
	vec3 tot = vec3(0.0);

	for (int m = 0; m < AA; m++)
	{
		for (int n = 0; n < AA; n++)
		{
			// pixel coordinates
			vec2 o = vec2(float(m), float(n)) / float(AA) - 0.5;
			vec2 p = (-resolution + 2.0 * (fragCoord + o)) / resolution.y;

			// ray direction
			vec3 rd = ca * normalize(vec3(p.xy, 2.2));

			// background
			vec3 col = vec3(0.1, 0.14, 0.18) + 0.1 * rd.y;

			// bounding volume
			vec2 bound = sphIntersect(ro, rd, 2.1);
			if (bound.x > 0.0)
			{
				// raycast
				float t = raycast(ro, rd, bound.x, bound.y, resolution.x);
				if (t > 0.0)
				{
					// local geometry
					vec3 pos = ro + t * rd;
					vec3 nor = calcNormal(pos, 0.01);
					vec3 upp = normalize(pos);

					// color and occlusion
					vec4 mate;
					map(pos, mate, true);

					// lighting
					col = vec3(0.0);

					// key light
					{
						vec3 lig = normalize(vec3(1.0, 0.0, 0.7));
						float dif = clamp(0.5 + 0.5 * dot(nor, lig), 0.0, 1.0);
						float sha = calcSoftshadow(pos + 0.0001 * nor, lig, 0.0001, 2.0, 6.0);
						col += mate.xyz * dif * vec3(1.8, 0.6, 0.5) * 1.1 * vec3(sha, sha * 0.3 + 0.7 * sha * sha, sha * sha);
						// spec
						vec3 hal = normalize(lig - rd);
						float spe = clamp(dot(nor, hal), 0.0, 1.0);
						float fre = clamp(dot(-rd, lig), 0.0, 1.0);
						fre = 0.2 + 0.8 * pow(fre, 5.0);
						spe *= spe;
						spe *= spe;
						spe *= spe;
						col += 1.0 * (0.25 + 0.75 * mate.x) * spe * dif * sha * fre;
					}

					// back light
					{
						vec3 lig = normalize(vec3(-1.0, 0.0, 0.0));
						float dif = clamp(0.5 + 0.5 * dot(nor, lig), 0.0, 1.0);
						col += mate.rgb * dif * vec3(1.2, 0.9, 0.6) * 0.2 * mate.w;
					}

					// dome light
					{
						float dif = clamp(0.3 + 0.7 * dot(nor, upp), 0.0, 1.0);
						col += mate.xyz * dif * 3.0 * vec3(0.1, 0.1, 0.3) * mate.w * (0.2 + 0.8 * mate.w);
					}

					// fake sss
					{
						float fre = clamp(1.0 + dot(rd, nor), 0.0, 1.0);
						col += 0.3 * vec3(1.0, 0.3, 0.2) * mate.xyz * mate.xyz * fre * fre * mate.w;
					}

					// grade/sss
					{
						col = 2.0 * pow(col, vec3(0.7, 0.85, 1.0));
					}

					// exposure control
					col *= 0.7 + 0.3 * smoothstep(0.0, 25.0, abs(TIME - 31.0));
				}
			}

			// gamma
			col = pow(col, vec3(0.4545));

			tot += col;
		}
	}
	tot /= float(AA * AA);

	// vignetting
	vec2 q = fragCoord / resolution;
	tot *= pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.2);

	COLOR = vec4(tot, 1.0);
}
