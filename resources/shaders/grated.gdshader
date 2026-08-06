// title: this is the grated shader and it is neat

shader_type canvas_item;

#define SIN(x) (sin(x) * 0.5 + 0.5)
#define BUMP_EPS 0.004

uniform samplerCube iChannel0 : source_color;

const highp float NOISE_GRANULARITY = 0.5 / 255.0;

mat2 rot(float a)
{
	return mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
}

// zucconis spectral palette https://www.alanzucconi.com/2017/07/15/improving-the-rainbow-2/
vec3 bump3y(vec3 x, vec3 yoffset)
{
	vec3 y = 1.0 - x * x;
	y = clamp((y - yoffset), vec3(0.0), vec3(1.0));
	return y;
}

highp float random(highp vec2 coords)
{
	return fract(sin(dot(coords.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float rect(vec2 p, vec2 b, float r)
{
	vec2 d = abs(p) - (b - r);
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void pixarONB(vec3 n, out vec3 b1, out vec3 b2)
{
	float sign_ = sign(n.z);
	float a = -1.0 / (sign_ + n.z);
	float b = n.x * n.y * a;
	b1 = vec3(1.0 + sign_ * n.x * n.x * a, sign_ * b, -sign_ * n.x);
	b2 = vec3(b, sign_ + n.y * n.y * a, -n.y);
}

vec3 invGamma(vec3 col)
{
	return pow(col, vec3(2.2));
}

vec3 gamma(vec3 col)
{
	return pow(col, vec3(1.0 / 2.2));
}

vec3 waveSpectrum(float w)
{
	if (w > 700.0 || w < 400.0)
	{
		return vec3(0.0);
	}

	float x = fract((w - 400.0) / 300.0);

	const vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
	const vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
	const vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);

	const vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
	const vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
	const vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);

	vec3 col = bump3y(c1 * (x - x1), y1) + bump3y(c2 * (x - x2), y2);

	// https://twitter.com/Atrix256/status/1019359890660192256
	// Undo gamma
	col = invGamma(col);

	return col;
}

vec3 diffraction(vec3 rd, vec3 n, vec3 td, vec3 l, float d)
{
	vec3 col = vec3(0.0);

	float cosThetaL = dot(l, td);
	float cosThetaV = dot(rd, td);

	float u = abs(cosThetaL - cosThetaV);

	if (u == 0.0)
	{
		return vec3(0.0);
	}

	for (float i = 1.0; i < 2.0; i++)
	{
		float wavelength = u * d / i;
		col += waveSpectrum(wavelength);
	}
	col = clamp(col, vec3(0.0), vec3(1.0));
	return col;
}

vec3 transform(vec3 p)
{
	p.yz *= rot(PI * 0.25 + TIME * 0.6);
	p.yx *= rot(PI * 0.25 + 0.75 * TIME * 0.6);
	return p;
}

vec2 torusUV(vec3 p)
{
	p = transform(p);
	float a = atan(p.z, p.x);
	float r = length(p.zx);

	return vec2(r, a);
}

float map(vec3 p)
{
	float edge = 0.02;

	p = transform(p);

	float r = 1.4;
	vec2 cp = vec2(length(p.xz) - r, p.y);

	float rev = 0.5;
	float a = atan(p.z, p.x);

	cp *= rot(rev * a);
	cp = abs(cp) - 1.0 * SIN(TIME * 0.6);
	cp = abs(cp) - SIN(TIME * 0.6);

	float dr = rect(cp.xy, vec2(0.3), edge);

	return 0.3 * dr;
}

float gridSurf(in vec3 p)
{
	p.z += 0.3 * TIME * 0.6;
	p = abs(mod(p * 2.0, 1.0 * 0.125) - 0.0125);

	float x = min(p.x, min(p.z, p.y)) / 0.03125;

	return clamp(x, 0.0, 1.0);
}

// Standard function-based bump mapping function (from Shane)
vec3 doBumpMap(in vec3 p, in vec3 nor, float bumpfactor)
{
	const float eps = BUMP_EPS;
	float ref = gridSurf(p);
	vec3 grad = vec3(gridSurf(vec3(p.x - eps, p.y, p.z)) - ref,
			gridSurf(vec3(p.x, p.y - eps, p.z)) - ref,
			gridSurf(vec3(p.x, p.y, p.z - eps)) - ref) / eps;

	grad -= nor * dot(nor, grad);

	return normalize(nor + bumpfactor * grad);
}

vec2 raymarch(vec3 ro, vec3 rd, float steps)
{
	float mat = 0.0;
	float t = 0.0;
	float d = 0.0;
	vec3 p = ro;
	for (float i = 0.0; i < steps; i++)
	{
		d = map(p);
		mat = 0.0; // g_mat was never written in the source shader

		if (abs(d) < 0.0001 || t > 100.0)
		{
			break;
		}

		t += d;
		p += rd * d;
	}

	return vec2(t, mat);
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = UV * resolution;
	vec2 uv = (fragCoord - 0.5 * resolution) / resolution.y;

	vec3 ro = vec3(uv * 6.0, -4.0);
	vec3 rd = vec3(0.0, 0.0, 1.0);
	vec3 lp = vec3(3.0, 0.0, -5.0);
	vec3 lp2 = vec3(-3.0, 0.0, -5.0);

	vec3 col = vec3(0.0);

	float mat = 0.0;

	vec2 e = vec2(0.0035, -0.0035);

	// light color
	vec3 lc1 = vec3(0.745, 0.761, 0.976);
	vec3 lc2 = vec3(0.573, 0.922, 0.969);

	// currently only one pass
	for (float i = 0.0; i < 1.0; i++)
	{
		float steps = i > 0.0 ? 50.0 : 200.0;
		vec2 rm = raymarch(ro, rd, steps);
		mat = rm.y;

		vec3 p = ro + rm.x * rd;

		vec3 n = normalize(e.xyy * map(p + e.xyy) + e.yyx * map(p + e.yyx) +
				e.yxy * map(p + e.yxy) + e.xxx * map(p + e.xxx));

		vec2 tuv = torusUV(p);

		n = doBumpMap(vec3(tuv.x, 0.0, tuv.y * 2.0 * PI), n, 0.001);

		if (rm.x < 50.0)
		{
			vec3 l = normalize(lp - p);
			vec3 l2 = normalize(lp2 - p);
			float dif = max(dot(n, l), 0.0);
			float dif2 = max(dot(n, l2), 0.0);

			vec3 td = vec3(tuv.x, tuv.y, 0.0).yxz;
			vec3 tangent;
			vec3 bitangent;

			pixarONB(n, tangent, bitangent);
			tangent = normalize(tangent);
			bitangent = normalize(bitangent);

			mat3 tbn = mat3(tangent, bitangent, n);
			l = normalize(vec3(0.0, 1.0, 0.0));
			vec3 difr = diffraction(-rd, n, normalize(tbn * td), l, 700.0);
			col += 0.6 * (lc1 * dif + lc2 * dif2) + difr;

			col = mix(col, col * (smoothstep(0.0, 1.0, sin(tuv.y * 150.0 + 10.0 * TIME * 0.6))), 0.5);

			if (mat == 0.0)
			{
				rd = reflect(rd, n);

				rd.yz *= rot(PI * 0.8);

				vec3 refl = texture(iChannel0, rd).rgb;

				refl = invGamma(refl);

				col = mix(col, 0.7 * refl, 0.5);
			}
		}
		else
		{
			col = invGamma(col);
		}
	}

	col += mix(-NOISE_GRANULARITY, NOISE_GRANULARITY, random(uv));
	col *= mix(0.2, 1.0, (1.5 - pow(dot(uv, uv), 0.5))); // vignette
	col = gamma(col); // gamma

	COLOR = vec4(col, 1.0);
}
