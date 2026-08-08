// title: a rollercoaster ride through neon tunnels

shader_type canvas_item;

float boxen(vec3 p)
{
	p = abs(fract(p / 40.0) * 40.0 - 20.0) - 2.0;
	return min(p.x, min(p.y, p.z));
}

vec3 trackPosition(float z)
{
	return vec3(cos(z * 0.015) * 16.0 + cos(z * 0.006) * 64.0,
		cos(z * 0.011) * 24.0 + cos(z * 0.009) * 32.0, z);
}

mat2 wobbleMat(float a)
{
	vec4 c = cos(a + vec4(0.0, 33.0, 11.0, 0.0));
	return mat2(vec2(c.x, c.y), vec2(c.z, c.w));
}

float map(vec3 p, inout vec4 lights)
{
	vec3 q = trackPosition(p.z);
	float g = q.y - p.y + 6.0;
	float m = boxen(p);

	p.xy -= q.xy;

	float red = length(p.xy - sin(p.y / 12.0 + vec2(5.0, 1.0)) * 12.0) - 1.0;
	float blue = length(p.xy - sin(p.y / 12.0 + vec2(0.0, 1.0)) * 12.0) - 1.0;
	float e = min(red, blue);

	lights += vec4(2.0, 10.0, 10.0, 0.0) / (0.1 + abs(red) / 10.0);
	lights += vec4(10.0, 2.0, 10.0, 0.0) / (0.1 + abs(blue) / 10.0);

	p = abs(p);

	float tex = abs(length(sin(p * cos(p.yzx / 30.0) * 4.0) / (p * 4.0)));
	float tun = min(64.0 - p.x - p.y + m, 32.0 - p.y - m);

	float d = max(min(m, g), tun) - tex;
	return min(e, d);
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = vec2(UV.x, 1.0 - UV.y) * resolution;

	float stepDist = 0.0;
	float t = 0.0;

	vec2 u = (fragCoord - resolution / 2.0) / resolution.y;
	u.y -= 0.2;

	vec4 o = vec4(0.0);
	vec4 lights = vec4(0.0);

	float trackTime = sin(TIME * 0.6) * 64.0 + TIME * 200.0;

	vec3 p = trackPosition(trackTime);
	vec3 ro = p;
	vec3 fwd = normalize(trackPosition(trackTime + 10.0) - p);
	vec3 right = normalize(vec3(fwd.z, 0.0, -fwd.x));
	vec3 rd = normalize(vec3(wobbleMat(sin(trackTime * 0.005) * 0.4) * u, 1.0)
		* mat3(-right, cross(right, fwd), fwd));

	for (float i = 0.0; i < 128.0; i++)
	{
		p = ro + rd * t;
		stepDist = map(p, lights) * 0.8;
		t += stepDist;
		o += lights + 1.0 / max(stepDist, 0.01);
	}

	const float h = 0.005;
	const vec2 k = vec2(1.0, -1.0);
	vec4 nDummy = vec4(0.0);
	vec3 n = normalize(k.xyy * map(p + k.xyy * h, nDummy) +
		k.yyx * map(p + k.yyx * h, nDummy) +
		k.yxy * map(p + k.yxy * h, nDummy) +
		k.xxx * map(p + k.xxx * h, nDummy));

	o *= 0.1 + max(dot(n, -rd), 0.0);

	vec4 ref = vec4(0.0);
	lights = vec4(0.0);
	p += n * 0.05;
	rd = reflect(rd, n);
	stepDist = 0.0;
	for (float i = 0.0; i < 40.0; i++)
	{
		p += rd * stepDist;
		stepDist = map(p, lights) * 0.8;
		ref += lights + 1.0 / max(stepDist, 0.01);
	}

	o += o * ref;
	o = tanh(o / 6e6 / t);

	COLOR = vec4(o.rgb, 1.0);
}
