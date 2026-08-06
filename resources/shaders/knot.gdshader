// title: this is the knot, aint it grand?

shader_type canvas_item;

const int STEPS = 64;
const float EPS = 0.01;
const float FAR = 21.0;
// const float TAU = 6.28318530718;

// Set from script via mesh/material params if mouse-driven camera tilt is
// ever wanted; defaults to "not pressed" so the camera follows its orbit.
uniform vec4 mouse = vec4(0.0, 0.0, 0.0, 0.0);

float knot(vec3 p, float k)
{
	float r = length(p.xy);
	float a = atan(p.y, p.x);
	float oa = k * a;
	a = mod(a, 0.001 * TAU) - 0.001 * TAU / 2.0;
	p.xy = r * vec2(cos(a), sin(a));
	p.x -= 6.0;
	p.xz = cos(oa) * p.xz + sin(oa) * vec2(-p.z, p.x);
	p.x = abs(p.x) - 1.35;
	return length(p) - 1.0;
}

float map(vec3 p)
{
	float t = mod(TIME + 8.0, 12.0);
	float k = step(5.0, t) * smoothstep(5.0, 6.0, t) * step(t, 11.0);
	k += step(11.0, t) * (1.0 - smoothstep(11.0, 12.0, t));

	return knot(p, mix(1.5, 3.5, k));
}

vec3 grad(vec3 p)
{
	vec2 q = vec2(0.0, EPS);
	return vec3(map(p + q.yxx) - map(p - q.yxx),
			map(p + q.xyx) - map(p - q.xyx),
			map(p + q.xxy) - map(p - q.xxy));
}

vec3 bgColor(vec3 rd)
{
	vec3 bl = vec3(22.0, 122.0, 198.0) / 255.0;
	return bl * (1.0 + 2.0 * rd.y) / 3.0 + 0.35;
}

vec3 shade(vec3 ro, vec3 rd, float t, vec2 resolution)
{
	vec3 p = ro + t * rd;
	for (int i = 0; i < 3; ++i)
	{
		p = p + rd * (map(p) - 4.0 * t / resolution.x);
	}

	vec3 n = normalize(grad(p));
	return bgColor(reflect(rd, n)) * (0.2 + 0.8 * pow(1.0 - dot(-rd, n), 0.5));
}

mat3 lookAt(vec3 p)
{
	vec3 z = normalize(p);
	vec3 x = normalize(cross(vec3(0.0, 1.0, 0.0), z));
	return mat3(x, cross(z, x), z);
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = UV * resolution;

	vec2 uv = (-resolution.xy + 2.0 * fragCoord.xy) / resolution.y;
	float ms = -1.0 + 2.0 * mouse.y / resolution.y;

	vec3 ro = vec3(5.0 * cos(TIME), mouse.z > 0.0 ? 10.0 * ms : 0.0, 10.0);
	vec3 rd = normalize(lookAt(ro) * vec3(uv, -1.0));

	float d = 0.0;
	float t = 0.0;
	for (int i = 0; i < STEPS; ++i)
	{
		d = map(ro + t * rd);
		if (d < EPS)
		{
			break;
		}
		t += 0.85 * d;
	}
	vec3 col = d < EPS ? shade(ro, rd, t, resolution) : bgColor(rd);

	vec2 vig = fragCoord.xy / resolution.xy;
	col *= 0.5 + 0.7 * pow(vig.x * (1.0 - vig.x) * vig.y * (1.0 - vig.y), 0.15);
	col = smoothstep(0.0, 0.8, col);
	col = pow(col, vec3(0.45));

	COLOR = vec4(col, 1.0);
}
