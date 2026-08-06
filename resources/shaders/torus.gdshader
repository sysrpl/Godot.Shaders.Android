// title: A lighting torus in a bottle!

shader_type canvas_item;

const float I_MAX = 400.0;
const float EZ = 0.00001;
const float FAR = 50.0;

vec3 blackbody(float temp)
{
	vec3 col = vec3(255.0);
	col.x = 56100000.0 * pow(temp, (-3.0 / 2.0)) + 148.0;
	col.y = 100.04 * log(temp) - 623.6;
	if (temp > 6500.0)
	{
		col.y = 35200000.0 * pow(temp, (-3.0 / 2.0)) + 184.0;
	}
	col.z = 194.18 * log(temp) - 1448.6;
	col = clamp(col, 0.0, 255.0) / 255.0;
	if (temp < 1000.0)
	{
		col *= temp / 1000.0;
	}
	return col;
}

void rotate(inout vec2 v, float angle)
{
	v = vec2(cos(angle) * v.x + sin(angle) * v.y, -sin(angle) * v.x + cos(angle) * v.y);
}

vec3 camera(vec2 uv)
{
	float fov = 1.0;
	vec3 forw = vec3(0.0, 0.0, -1.0);
	vec3 right = vec3(1.0, 0.0, 0.0);
	vec3 up = vec3(0.0, 1.0, 0.0);

	return normalize((uv.x) * right + (uv.y) * up + fov * forw);
}

float scene(vec3 p, inout vec3 h, inout vec3 retCol)
{
	p.z += 10.0;

	rotate(p.xz, 1.57 - 0.5 * TIME);
	rotate(p.yz, 1.57 - 0.5 * TIME);
	float var = atan(p.x, p.y);
	vec2 q = vec2(length(p.xy) - 6.0, p.z);
	rotate(q, var * 0.25 + TIME * 2.0 * 0.0);
	vec2 oq = q;
	q = abs(q) - 2.5;
	if (oq.x < q.x && oq.y > q.y)
	{
		rotate(q, ((var * 1.0) + TIME * 0.0) * 3.14 + TIME * 0.0);
	}
	else
	{
		rotate(q, (0.28 - (var * 1.0) + TIME * 0.0) * 3.14 + TIME * 0.0);
	}
	retCol = 1.0 - vec3(0.350, 0.2, 0.3);
	float mind = length(q) + 0.5 + 1.05 * (length(fract(q * 0.5 * (3.0 + 3.0 * sin(var * 1.0 - TIME * 2.0))) - 0.5) - 1.215);
	h -= vec3(-3.20, 0.20, 1.0) * vec3(1.0) * 0.0025 / (0.051 + (mind - sin(var * 1.0 - TIME * 2.0 + 3.14) * 0.125) * (mind - sin(var * 1.0 - TIME * 2.0 + 3.14) * 0.125));
	h -= vec3(1.20, -0.50, -0.50) * vec3(1.0) * 0.025 / (0.501 + (mind - sin(var * 1.0 - TIME * 2.0) * 0.5) * (mind - sin(var * 1.0 - TIME * 2.0) * 0.5));
	h += vec3(0.25, 0.4, 0.5) * 0.0025 / (0.021 + mind * mind);

	return mind;
}

vec2 march(vec3 pos, vec3 dir, inout vec3 h, inout vec3 retCol)
{
	vec2 dist = vec2(0.0, 0.0);
	vec3 p = vec3(0.0, 0.0, 0.0);
	vec2 s = vec2(0.0, 0.0);

	for (float i = -1.0; i < I_MAX; ++i)
	{
		p = pos + dir * dist.y;
		dist.x = scene(p, h, retCol);
		dist.y += dist.x * 0.2;
		if (log(dist.y * dist.y / dist.x / 1e5) > 0.0 || dist.x < EZ || dist.y > FAR)
		{
			break;
		}
		s.x++;
	}
	s.y = dist.y;
	return s;
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = UV * resolution;

	float localTime = TIME * 0.125;
	vec3 col = vec3(0.0, 0.0, 0.0);
	vec2 uv = vec2(fragCoord - resolution / 2.0) / resolution.y;
	vec3 dir = camera(uv);
	vec3 pos = vec3(0.0, 0.0, 0.0);

	pos.z = 4.5 + 1.5 * sin(localTime * 10.0);

	vec3 h = vec3(0.0);
	vec3 retCol = vec3(0.0);
	vec2 inter = march(pos, dir, h, retCol);
	col.xyz = retCol * (1.0 - inter.x * 0.0125);
	col += h * 0.4;

	COLOR = vec4(col, 1.0);
}
