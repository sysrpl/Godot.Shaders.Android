// title: rocky cube

shader_type canvas_item;

const float PRECIS = 0.0005;

float hash(vec3 p)
{
	p = 17.0 * fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float sdBox(vec3 p, vec3 b)
{
	vec3 d = abs(p) - b;
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float smax(float a, float b, float k)
{
	float h = max(k - abs(a - b), 0.0);
	return max(a, b) + h * h * 0.25 / k;
}

vec2 iBox(in vec3 ro, in vec3 rd, in vec3 rad)
{
	vec3 m = 1.0 / rd;
	vec3 n = m * ro;
	vec3 k = abs(m) * rad;
	vec3 t1 = -n - k;
	vec3 t2 = -n + k;
	float tN = max(max(t1.x, t1.y), t1.z);
	float tF = min(min(t2.x, t2.y), t2.z);
	if (tN > tF || tF < 0.0)
		return vec2(-1.0);
	return vec2(tN, tF);
}

float sdBase(in vec3 p)
{
	vec3 i = floor(p);
	vec3 f = fract(p);

#define RAD(r) ((r) * (r) * 0.7)
#define SPH(i, f, c) length(f - c) - RAD(hash(i + c))

	return min(min(min(SPH(i, f, vec3(0.0, 0.0, 0.0)),
		SPH(i, f, vec3(0.0, 0.0, 1.0))),
		min(SPH(i, f, vec3(0.0, 1.0, 0.0)),
		SPH(i, f, vec3(0.0, 1.0, 1.0)))),
		min(min(SPH(i, f, vec3(1.0, 0.0, 0.0)),
		SPH(i, f, vec3(1.0, 0.0, 1.0))),
		min(SPH(i, f, vec3(1.0, 1.0, 0.0)),
		SPH(i, f, vec3(1.0, 1.0, 1.0)))));
}

vec2 sdFbm(in vec3 p, float d)
{
	const mat3 m = mat3(vec3(0.00, 0.80, 0.60), vec3(-0.80, 0.36, -0.48), vec3(-0.60, -0.48, 0.64));
	float t = 0.0;
	float s = 1.0;
	for (int i = 0; i < 7; i++)
	{
		float n = s * sdBase(p);
		d = smax(d, -n, 0.15 * s);
		t += d;
		p = 2.0 * m * p;
		s = 0.55 * s;
	}

	return vec2(d, t);
}

vec2 map(in vec3 p)
{
	float d = sdBox(p, vec3(1.0));
	vec2 dt = sdFbm(p + 0.5, d);
	dt.y = 1.0 + dt.y * 2.0;
	dt.y = dt.y * dt.y;
	return dt;
}

vec2 raycast(in vec3 ro, in vec3 rd)
{
	vec2 res = vec2(-1.0);

	vec2 dis = iBox(ro, rd, vec3(1.0));
	if (dis.y < 0.0)
		return res;

	float t = dis.x;
	for (int i = 0; i < 256; i++)
	{
		vec3 pos = ro + t * rd;
		vec2 h = map(pos);
		res.x = t;
		res.y = h.y;

		if (h.x < PRECIS || t > dis.y)
			break;
		t += h.x;
	}

	if (t > dis.y)
		res = vec2(-1.0);
	return res;
}

vec3 calcNormal(in vec3 pos)
{
	vec2 e = vec2(1.0, -1.0) * 0.5773 * PRECIS;
	return normalize(e.xyy * map(pos + e.xyy).x +
		e.yyx * map(pos + e.yyx).x +
		e.yxy * map(pos + e.yxy).x +
		e.xxx * map(pos + e.xxx).x);
}

float calcSoftShadow(vec3 ro, vec3 rd, float tmin, float tmax, float w)
{
	vec2 dis = iBox(ro, rd, vec3(1.0));
	if (dis.y < 0.0)
		return 1.0;

	tmin = max(tmin, dis.x);
	tmax = min(tmax, dis.y);

	float t = tmin;
	float res = 1.0;
	for (int i = 0; i < 128; i++)
	{
		float h = map(ro + t * rd).x;
		res = min(res, h / (w * t));
		t += clamp(h, 0.005, 0.50);
		if (res < -1.0 || t > tmax)
			break;
	}
	res = max(res, -1.0);

	return 0.25 * (1.0 + res) * (1.0 + res) * (2.0 - res);
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = vec2(UV.x, 1.0 - UV.y) * resolution;

	vec2 p = (2.0 * fragCoord - resolution) / resolution.y;

	float an = -0.1 * TIME;
	vec3 ro = 4.0 * vec3(cos(an), 0.4, sin(an));
	vec3 ta = vec3(0.0, -0.35, 0.0);

	vec3 cw = normalize(ta - ro);
	vec3 cu = normalize(cross(cw, vec3(0.0, 1.0, 0.0)));
	vec3 cv = normalize(cross(cu, cw));
	vec3 rd = normalize(p.x * cu + p.y * cv + 2.7 * cw);

	vec3 col = vec3(0.01);
	vec2 tm = raycast(ro, rd);
	float t = tm.x;
	if (t > 0.0)
	{
		vec3 pos = ro + t * rd;
		vec3 nor = calcNormal(pos);
		float occ = tm.y * tm.y;

		vec3 mate = mix(vec3(0.6, 0.3, 0.1), vec3(1.0), tm.y) * 0.7;

		const vec3 lig = normalize(vec3(1.0, 0.5, 0.6));
		float dif = dot(lig, nor);
		if (dif > 0.0)
			dif *= calcSoftShadow(pos + nor * 0.001, lig, 0.001, 10.0, 0.003);
		dif = clamp(dif, 0.0, 1.0);
		vec3 hal = normalize(lig - rd);
		float spe = clamp(dot(hal, nor), 0.0, 1.0);
		spe = pow(spe, 4.0) * dif * (0.04 + 0.96 * pow(max(1.0 - dot(hal, lig), 0.0), 5.0));

		col = vec3(0.0);
		col += mate * 1.5 * vec3(1.30, 0.85, 0.75) * dif;
		col += 9.0 * spe;

		col += mate * 0.2 * vec3(0.40, 0.45, 0.60) * occ * (0.6 + 0.4 * nor.y);
	}
	col = col * 1.7 / (1.0 + col);
	col = pow(col, vec3(0.4545));
	vec3 tot = col;
	vec2 q = fragCoord / resolution;
	tot *= 0.7 + 0.3 * pow(16.0 * q.x * q.y * (1.0 - q.x) * (1.0 - q.y), 0.2);
	tot += sin(fragCoord.x * 114.0) * sin(fragCoord.y * 211.1) / 512.0;

	COLOR = vec4(tot, 1.0);
}
