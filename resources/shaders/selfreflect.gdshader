// title: a polyhedron reflecting on itself

shader_type canvas_item;

const float ROTATION_SPEED = 0.25;

const float POLY_U = 1.0;
const float POLY_V = 0.5;
const float POLY_W = 1.0;
const int POLY_TYPE = 3;
const float POLY_ZOOM = 2.0;

const float INNER_SPHERE = 1.0;

const float REFR_INDEX = 0.9;

const int MAX_BOUNCES2 = 6;

const float TOLERANCE2 = 0.0005;
const int MAX_RAY_MARCHES2 = 50;
const float NORM_OFF2 = 0.005;

const float TOLERANCE3 = 0.0005;
const float MAX_RAY_LENGTH3 = 10.0;
const int MAX_RAY_MARCHES3 = 90;
const float NORM_OFF3 = 0.005;

const vec3 RAY_ORIGIN = vec3(0.0, 1.0, -5.0);
const vec3 POLY_PAB = vec3(0.0, 0.0, 1.0);
const float RREFR_INDEX = 1.0 / REFR_INDEX;

const vec4 HSV2RGB_K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);

#define HSV2RGB(c) (c.z * mix(HSV2RGB_K.xxx, clamp(abs(fract(c.xxx + HSV2RGB_K.xyz) * 6.0 - HSV2RGB_K.www) - HSV2RGB_K.xxx, 0.0, 1.0), c.y))

// GDShader's "const" only folds literals/basic arithmetic, not built-in
// function calls (normalize, cos, sqrt, and everything the HSV2RGB macro
// expands to) - so these two groups of derived values are computed once
// per fragment instead and threaded through as parameters, rather than
// being top-level const like the rest of this block.
struct PolyGeom
{
	vec3 nc;
	vec3 pab;
	vec3 pbc;
	vec3 pca;
	vec3 p;
};

struct SceneColors
{
	vec3 sunDir;
	vec3 sunCol;
	vec3 bottomBoxCol;
	vec3 topBoxCol;
	vec3 glowCol0;
	vec3 glowCol1;
	vec3 beerCol;
};

vec3 hsv2rgb(vec3 c)
{
	vec3 p = abs(fract(c.xxx + HSV2RGB_K.xyz) * 6.0 - HSV2RGB_K.www);
	return c.z * mix(HSV2RGB_K.xxx, clamp(p - HSV2RGB_K.xxx, 0.0, 1.0), c.y);
}

mat3 rot(vec3 d, vec3 z)
{
	vec3 v = cross(z, d);
	float c = dot(z, d);
	float k = 1.0 / (1.0 + c);

	return mat3(vec3(v.x * v.x * k + c, v.y * v.x * k - v.z, v.z * v.x * k + v.y),
			vec3(v.x * v.y * k + v.z, v.y * v.y * k + c, v.z * v.y * k - v.x),
			vec3(v.x * v.z * k - v.y, v.y * v.z * k + v.x, v.z * v.z * k + c));
}

vec3 acesApprox(vec3 v)
{
	v = max(v, 0.0);
	v *= 0.6;
	float a = 2.51;
	float b = 0.03;
	float c = 2.43;
	float d = 0.59;
	float e = 0.14;
	return clamp((v * (a * v + b)) / (v * (c * v + d) + e), 0.0, 1.0);
}

float sphere(vec3 p, float r)
{
	return length(p) - r;
}

float box(vec2 p, vec2 b)
{
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void polyFold(inout vec3 pos, PolyGeom poly)
{
	vec3 p = pos;

	for (int i = 0; i < POLY_TYPE; ++i)
	{
		p.xy = abs(p.xy);
		p -= 2.0 * min(0.0, dot(p, poly.nc)) * poly.nc;
	}

	pos = p;
}

float polyPlane(vec3 pos, PolyGeom poly)
{
	float d0 = dot(pos, poly.pab);
	float d1 = dot(pos, poly.pbc);
	float d2 = dot(pos, poly.pca);
	float d = d0;
	d = max(d, d1);
	d = max(d, d2);
	return d;
}

float polyCorner(vec3 pos)
{
	return length(pos) - 0.0125;
}

float dot2(vec3 p)
{
	return dot(p, p);
}

float polyEdge(vec3 pos, PolyGeom poly)
{
	float dla = dot2(pos - min(0.0, pos.x) * vec3(1.0, 0.0, 0.0));
	float dlb = dot2(pos - min(0.0, pos.y) * vec3(0.0, 1.0, 0.0));
	float dlc = dot2(pos - min(0.0, dot(pos, poly.nc)) * poly.nc);
	return sqrt(min(min(dla, dlb), dlc)) - 0.002;
}

vec3 shape(vec3 pos, mat3 rotMat, PolyGeom poly)
{
	pos *= rotMat;
	pos /= POLY_ZOOM;
	polyFold(pos, poly);
	pos -= poly.p;

	return vec3(polyPlane(pos, poly), polyEdge(pos, poly), polyCorner(pos)) * POLY_ZOOM;
}

vec3 render0(vec3 ro, vec3 rd, SceneColors colors)
{
	vec3 col = vec3(0.0);

	float srd = sign(rd.y);
	float tp = -(ro.y - 6.0) / abs(rd.y);

	if (srd < 0.0)
		col += colors.bottomBoxCol * exp(-0.5 * length((ro + tp * rd).xz));

	if (srd > 0.0)
	{
		vec3 pos = ro + tp * rd;
		vec2 pp = pos.xz;
		float db = box(pp, vec2(5.0, 9.0)) - 3.0;

		col += colors.topBoxCol * rd.y * rd.y * smoothstep(0.25, 0.0, db);
		col += 0.2 * colors.topBoxCol * exp(-0.5 * max(db, 0.0));
		col += 0.05 * sqrt(colors.topBoxCol) * max(-db, 0.0);
	}

	col += colors.sunCol / (1.001 - dot(colors.sunDir, rd));
	return col;
}

float df2(vec3 p, mat3 rotMat, PolyGeom poly, inout vec2 gd)
{
	vec3 ds = shape(p, rotMat, poly);
	float d2 = ds.y - 0.005;
	float d0 = min(-ds.x, d2);
	float d1 = sphere(p, INNER_SPHERE);
	gd = min(gd, vec2(d2, d1));
	float d = min(d0, d1);
	return d;
}

float rayMarch2(vec3 ro, vec3 rd, float tinit, mat3 rotMat, PolyGeom poly, inout vec2 gd)
{
	float t = tinit;
	vec2 dti = vec2(1e10, 0.0);
	int i = 0;
	while (i < MAX_RAY_MARCHES2)
	{
		float d = df2(ro + rd * t, rotMat, poly, gd);
		if (d < dti.x)
			dti = vec2(d, t);
		if (d < TOLERANCE2)
			break;
		t += d;
		++i;
	}
	if (i == MAX_RAY_MARCHES2)
		t = dti.y;
	return t;
}

vec3 normal2(vec3 pos, mat3 rotMat, PolyGeom poly)
{
	vec2 eps = vec2(NORM_OFF2, 0.0);
	vec2 gd = vec2(0.0);
	vec3 nor;
	nor.x = df2(pos + eps.xyy, rotMat, poly, gd) - df2(pos - eps.xyy, rotMat, poly, gd);
	nor.y = df2(pos + eps.yxy, rotMat, poly, gd) - df2(pos - eps.yxy, rotMat, poly, gd);
	nor.z = df2(pos + eps.yyx, rotMat, poly, gd) - df2(pos - eps.yyx, rotMat, poly, gd);
	return normalize(nor);
}

vec3 render2(vec3 ro, vec3 rd, float db, mat3 rotMat, PolyGeom poly, SceneColors colors)
{
	vec3 agg = vec3(0.0);
	float ragg = 1.0;
	float tagg = 0.0;

	for (int bounce = 0; bounce < MAX_BOUNCES2; ++bounce)
	{
		if (ragg < 0.1)
			break;
		vec2 gd = vec2(1000.0);
		float t2 = rayMarch2(ro, rd, min(db + 0.05, 0.3), rotMat, poly, gd);
		vec2 gd2 = gd;
		tagg += t2;

		vec3 p2 = ro + rd * t2;
		vec3 n2 = normal2(p2, rotMat, poly);
		vec3 r2 = reflect(rd, n2);
		vec3 rr2 = refract(rd, n2, RREFR_INDEX);
		float fre2 = 1.0 + dot(n2, rd);

		vec3 beer = ragg * exp(0.2 * colors.beerCol * tagg);
		agg += colors.glowCol1 * beer * ((1.0 + tagg * tagg * 0.04) * 6.0 / max(gd2.x, 0.0005 + tagg * tagg * 0.0002 / ragg));
		vec3 ocol = 0.2 * beer * render0(p2, rr2, colors);
		if (gd2.y <= TOLERANCE2)
			ragg *= 1.0 - 0.9 * fre2;
		else
		{
			agg += ocol;
			ragg *= 0.8;
		}

		ro = p2;
		rd = r2;
		db = gd2.x;
	}

	return agg;
}

float df3(vec3 p, mat3 rotMat, PolyGeom poly, inout vec2 gd)
{
	vec3 ds = shape(p, rotMat, poly);
	gd = min(gd, ds.yz);
	const float sw = 0.02;
	float d1 = min(ds.y, ds.z) - sw;
	float d0 = ds.x;
	d0 = min(d0, ds.y);
	d0 = min(d0, ds.z);
	return d0;
}

float rayMarch3(vec3 ro, vec3 rd, float tinit, mat3 rotMat, PolyGeom poly, inout vec2 gd, out int iter)
{
	float t = tinit;
	int i = 0;
	while (i < MAX_RAY_MARCHES3)
	{
		float d = df3(ro + rd * t, rotMat, poly, gd);
		if (d < TOLERANCE3 || t > MAX_RAY_LENGTH3)
			break;
		t += d;
		++i;
	}
	iter = i;
	return t;
}

vec3 normal3(vec3 pos, mat3 rotMat, PolyGeom poly)
{
	vec2 eps = vec2(NORM_OFF3, 0.0);
	vec2 gd = vec2(0.0);
	vec3 nor;
	nor.x = df3(pos + eps.xyy, rotMat, poly, gd) - df3(pos - eps.xyy, rotMat, poly, gd);
	nor.y = df3(pos + eps.yxy, rotMat, poly, gd) - df3(pos - eps.yxy, rotMat, poly, gd);
	nor.z = df3(pos + eps.yyx, rotMat, poly, gd) - df3(pos - eps.yyx, rotMat, poly, gd);
	return normalize(nor);
}

vec3 render3(vec3 ro, vec3 rd, mat3 rotMat, PolyGeom poly, SceneColors colors)
{
	vec3 skyCol = render0(ro, rd, colors);
	vec3 col = skyCol;

	int iter;
	vec2 gd = vec2(1000.0);
	float t1 = rayMarch3(ro, rd, 0.1, rotMat, poly, gd, iter);
	vec2 gd1 = gd;
	vec3 p1 = ro + t1 * rd;
	vec3 n1 = normal3(p1, rotMat, poly);
	vec3 r1 = reflect(rd, n1);
	vec3 rr1 = refract(rd, n1, REFR_INDEX);
	float fre1 = 1.0 + dot(rd, n1);
	fre1 *= fre1;

	float ifo = mix(0.5, 1.0, smoothstep(1.0, 0.9, float(iter) / float(MAX_RAY_MARCHES3)));

	if (t1 < MAX_RAY_LENGTH3)
	{
		col = render0(p1, r1, colors) * (0.5 + 0.5 * fre1) * ifo;
		vec3 icol = render2(p1, rr1, gd1.x, rotMat, poly, colors);
		if (gd1.x > TOLERANCE3 && gd1.y > TOLERANCE3 && rr1 != vec3(0.0))
			col += icol * (1.0 - 0.75 * fre1) * ifo;
	}

	col += (colors.glowCol0 + 1.0 * fre1 * colors.glowCol0) / max(gd1.x, 0.0003);
	return col;
}

vec3 effect(vec2 p, vec2 pp, mat3 rotMat, PolyGeom poly, SceneColors colors)
{
	const float fov = 2.0;

	const vec3 up = vec3(0.0, 1.0, 0.0);
	const vec3 la = vec3(0.0);

	vec3 ww = normalize(normalize(la - RAY_ORIGIN));
	vec3 uu = normalize(cross(up, ww));
	vec3 vv = cross(ww, uu);

	vec3 rd = normalize(-p.x * uu + p.y * vv + fov * ww);

	vec3 col = render3(RAY_ORIGIN, rd, rotMat, poly, colors);

	col -= 0.02 * vec3(2.0, 3.0, 1.0) * (length(p) + 0.25);
	col = acesApprox(col);
	col = sqrt(col);
	return col;
}

PolyGeom makePolyGeom()
{
	float cospin = cos(PI / float(POLY_TYPE));
	float scospin = sqrt(0.75 - cospin * cospin);
	vec3 pbcRaw = vec3(scospin, 0.0, 0.5);
	vec3 pcaRaw = vec3(0.0, scospin, cospin);

	PolyGeom poly;
	poly.nc = vec3(-0.5, -cospin, scospin);
	poly.pab = POLY_PAB;
	poly.pbc = normalize(pbcRaw);
	poly.pca = normalize(pcaRaw);
	poly.p = normalize(POLY_U * poly.pab + POLY_V * pbcRaw + POLY_W * pcaRaw);
	return poly;
}

SceneColors makeSceneColors()
{
	SceneColors colors;
	colors.sunDir = normalize(-RAY_ORIGIN);
	colors.sunCol = HSV2RGB(vec3(0.06, 0.90, 0.01)) * 1.0;
	colors.bottomBoxCol = HSV2RGB(vec3(0.66, 0.80, 0.5)) * 1.0;
	colors.topBoxCol = HSV2RGB(vec3(0.60, 0.90, 1.0)) * 1.0;
	colors.glowCol0 = HSV2RGB(vec3(0.05, 0.7, 0.001)) * 1.0;
	colors.glowCol1 = HSV2RGB(vec3(0.95, 0.7, 0.001)) * 1.0;
	colors.beerCol = -HSV2RGB(vec3(0.65, 0.7, 2.0));
	return colors;
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = vec2(UV.x, 1.0 - UV.y) * resolution;

	vec2 q = fragCoord / resolution;
	vec2 p = -1.0 + 2.0 * q;
	vec2 pp = p;
	p.x *= resolution.x / resolution.y;

	float a = TIME * ROTATION_SPEED;
	vec3 r0 = vec3(1.0, sin(vec2(sqrt(0.5), 1.0) * a));
	vec3 r1 = vec3(cos(vec2(sqrt(0.5), 1.0) * 0.913 * a), 1.0);
	mat3 rotMat = rot(normalize(r0), normalize(r1));

	PolyGeom poly = makePolyGeom();
	SceneColors colors = makeSceneColors();

	vec3 col = effect(p, pp, rotMat, poly, colors);

	COLOR = vec4(col, 1.0);
}
