// title: curved hexagons and triangles, extruded

shader_type canvas_item;

const float FAR = 20.0;

// sqrt(3.0) precomputed by hand, since GDShader "const" can't fold
// function calls - see the note further down where distField's old
// global state gets bundled into MapState for the same reason.
const vec2 G_SC = vec2(1.0, 1.0) / 4.0;
const vec2 S = vec2(1.0, 1.7320508) * G_SC;

const vec2 V0 = vec2(-6.0, -2.0) * S / 12.0;
const vec2 V1 = vec2(-6.0, 2.0) * S / 12.0;
const vec2 V2 = vec2(0.0, 4.0) * S / 12.0;
const vec2 V3 = vec2(6.0, 2.0) * S / 12.0;
const vec2 V4 = vec2(6.0, -2.0) * S / 12.0;
const vec2 V5 = vec2(0.0, -4.0) * S / 12.0;

const vec2 E0 = vec2(-6.0, 0.0) * S / 12.0;
const vec2 E1 = vec2(-3.0, 3.0) * S / 12.0;
const vec2 E2 = vec2(3.0, 3.0) * S / 12.0;
const vec2 E3 = vec2(6.0, 0.0) * S / 12.0;
const vec2 E4 = vec2(3.0, -3.0) * S / 12.0;
const vec2 E5 = vec2(-3.0, -3.0) * S / 12.0;

const vec2 VID0 = vec2(-6.0, -2.0);
const vec2 VID1 = vec2(-6.0, 2.0);
const vec2 VID2 = vec2(0.0, 4.0);
const vec2 VID3 = vec2(6.0, 2.0);
const vec2 VID4 = vec2(6.0, -2.0);
const vec2 VID5 = vec2(0.0, -4.0);

mat2 rot2(float a)
{
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float smax(float a, float b, float k)
{
	float f = max(0.0, 1.0 - abs(b - a) / k);
	return max(a, b) + k * 0.25 * f * f;
}

float hash21(vec2 p)
{
	p = fract(p * vec2(223.547, 256.483));
	p += dot(p, p + 145.627);
	return fract(p.x * p.y);
}

float hash31(vec3 p3)
{
	p3 = fract(p3 * vec3(0.6031, 0.5030, 0.4973));
	p3 += dot(p3, p3.zyx + 43.527);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 circumcircle(vec2 a, vec2 b, vec2 c)
{
	vec2 cb = c - b;
	vec2 baT = b - a;
	baT = baT.yx * vec2(-1.0, 1.0);
	vec2 p = (a + b + baT * dot(c - a, cb) / dot(baT, cb)) / 2.0;
	return vec3(p, length(a - p));
}

vec2 vGet(int i)
{
	if (i == 0)
		return V0;
	if (i == 1)
		return V1;
	if (i == 2)
		return V2;
	if (i == 3)
		return V3;
	if (i == 4)
		return V4;
	return V5;
}

vec2 eGet(int i)
{
	if (i == 0)
		return E0;
	if (i == 1)
		return E1;
	if (i == 2)
		return E2;
	if (i == 3)
		return E3;
	if (i == 4)
		return E4;
	return E5;
}

vec2 vidGet(int i)
{
	if (i == 0)
		return VID0;
	if (i == 1)
		return VID1;
	if (i == 2)
		return VID2;
	if (i == 3)
		return VID3;
	if (i == 4)
		return VID4;
	return VID5;
}

vec4 getGrid(vec2 p)
{
	vec4 h = vec4(p, p - S / 2.0);
	vec4 iC = floor(h / S.xyxy) + 0.5;

	h -= iC * S.xyxy;

	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, iC.xy * 12.0) : vec4(h.zw, iC.zw * 12.0 + 6.0);
}

// Everything that was global mutable state in the source (pID, gP, cntr,
// cLn[6], gCD, gVal, vObj) bundled into one struct threaded through
// distField()/map() and back out to their callers - GDShader doesn't
// reliably support mutable file-scope globals. cLn's 6 slots are named
// fields rather than an array for the same reason the constants above are
// unrolled: array types are untested territory here, so this conversion
// avoids them entirely. gRd/gDir (the other two former globals) aren't
// part of this struct - gRd is just the primary camera ray direction,
// constant for the whole frame, so it's threaded as a plain "rd"
// parameter instead; gDir was computed but never actually read anywhere
// in the source, so it's dropped rather than plumbed through for nothing.
struct MapState
{
	int pID;
	vec2 gP;
	vec2 cntr;
	vec3 cLn0;
	vec3 cLn1;
	vec3 cLn2;
	vec3 cLn3;
	vec3 cLn4;
	vec3 cLn5;
	float gCD;
	vec4 gVal;
	vec4 vObj;
};

vec3 cLnGet(MapState state, int i)
{
	if (i == 0)
		return state.cLn0;
	if (i == 1)
		return state.cLn1;
	if (i == 2)
		return state.cLn2;
	if (i == 3)
		return state.cLn3;
	if (i == 4)
		return state.cLn4;
	return state.cLn5;
}

vec4 distField(vec2 p, inout MapState state)
{
	vec4 p4 = getGrid(p);
	vec2 id = p4.zw;

	float poly = -1e5;
	float innerPoly = -1e5;
	float crvF = 2.4;

	state.cLn0 = circumcircle(E5, E0, V0 * crvF);
	state.cLn1 = circumcircle(E0, E1, V1 * crvF);
	state.cLn2 = circumcircle(E1, E2, V2 * crvF);
	state.cLn3 = circumcircle(E2, E3, V3 * crvF);
	state.cLn4 = circumcircle(E3, E4, V4 * crvF);
	state.cLn5 = circumcircle(E4, E5, V5 * crvF);

	innerPoly = max(innerPoly, -(length(p4.xy - state.cLn0.xy) - state.cLn0.z));
	innerPoly = max(innerPoly, -(length(p4.xy - state.cLn1.xy) - state.cLn1.z));
	innerPoly = max(innerPoly, -(length(p4.xy - state.cLn2.xy) - state.cLn2.z));
	innerPoly = max(innerPoly, -(length(p4.xy - state.cLn3.xy) - state.cLn3.z));
	innerPoly = max(innerPoly, -(length(p4.xy - state.cLn4.xy) - state.cLn4.z));
	innerPoly = max(innerPoly, -(length(p4.xy - state.cLn5.xy) - state.cLn5.z));

	if (innerPoly < 0.0)
	{
		poly = innerPoly;
		state.pID = 6;
		state.cntr = vec2(0.0);
	}
	else
	{
		poly = max(poly, -innerPoly);

		int i = int(fract(atan(p4.y, -p4.x) / TAU) * 6.0 + 1.0) % 6;

		id += vidGet(i);

		state.pID = 3;

		state.cLn0 = cLnGet(state, i);
		int k = (i + 2) % 6;
		vec2 ngb = eGet((i + 5) % 6) * 2.0;
		state.cLn1 = circumcircle(ngb + eGet((k + 5) % 6), ngb + eGet(k), ngb + vGet(k) * crvF);
		ngb = eGet(i) * 2.0;
		k = (i + 4) % 6;
		state.cLn2 = circumcircle(ngb + eGet((k + 5) % 6), ngb + eGet(k), ngb + vGet(k) * crvF);

		state.cntr = vGet(i);
	}

	poly = max(poly, -(length(p4.xy - state.cntr) - 0.005));

	state.gP = p4.xy;

	return vec4(poly, id, float(state.pID));
}

float ggxSchlick(float nv, float rough)
{
	float r = 0.5 + 0.5 * rough;
	float k = (r * r) / 2.0;
	float denom = nv * (1.0 - k) + k;
	return max(nv, 0.001) / denom;
}

vec3 getSpec(vec3 fs, float nh, float nr, float nl, float rough)
{
	float alpha = pow(rough, 4.0);
	float b = nh * nh * (alpha - 1.0) + 1.0;
	float d = alpha / (3.14159265 * b * b);

	float g1l = ggxSchlick(nl, rough);
	float g1v = ggxSchlick(nr, rough);
	float g = g1l * g1v;

	return fs * d * g / (4.0 * max(nr, 0.001)) * 3.14159265;
}

vec3 getDiff(vec3 fs, float nl, float type)
{
	vec3 diff = nl * (1.0 - fs);
	return diff * (1.0 - type);
}

float rayLine(vec2 ro, vec2 rd, vec2 p, vec2 n)
{
	float dn = dot(p - ro, n) / dot(rd, n);
	return dn < 0.0 ? 1e8 : dn;
}

float circleIntersect(vec2 ro, vec2 rd, vec2 ce, float ra)
{
	vec2 oc = ro - ce;
	float b = dot(oc, rd);

	vec2 qc = oc - b * rd;
	float h = ra * ra - dot(qc, qc);

	if (h < 0.0)
		return 1e8;

	h = sqrt(h);

	vec2 pI = vec2(-b - h, -b + h);

	return pI.y < 0.0 ? 1e8 : pI.x < 0.0 ? pI.y : pI.x;
}

float hm(vec2 p)
{
	float d = dot(sin(p * 0.125 - cos(p.yx * 0.2875)), vec2(0.25)) + 0.5;
	return mix(d, dot(sin(p * 0.25 - cos(p.yx * 0.575)), vec2(0.25)) + 0.5, 1.0 / 3.0);
}

float opExtrusion(float sdf, float pz, float h)
{
	vec2 w = vec2(sdf, abs(pz) - h);
	return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

float opExtrusion(float sdf, float pz, float h, float sf)
{
	vec2 w = vec2(sdf, abs(pz) - h) + sf;
	return min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - sf;
}

float map(vec3 p3, vec3 rd, inout MapState state)
{
	float fl = p3.y;

	vec4 p4 = distField(p3.xz, state);
	vec2 id = p4.yz;
	float d2 = p4.x;
	d2 += 0.003;

	vec2 p = state.gP;

	state.gCD = 1e8;
	vec2 rdXZ = normalize(rd.xz);

	if (0 < state.pID)
		state.gCD = min(state.gCD, circleIntersect(p, rdXZ, state.cLn0.xy, state.cLn0.z));
	if (1 < state.pID)
		state.gCD = min(state.gCD, circleIntersect(p, rdXZ, state.cLn1.xy, state.cLn1.z));
	if (2 < state.pID)
		state.gCD = min(state.gCD, circleIntersect(p, rdXZ, state.cLn2.xy, state.cLn2.z));
	if (3 < state.pID)
		state.gCD = min(state.gCD, circleIntersect(p, rdXZ, state.cLn3.xy, state.cLn3.z));
	if (4 < state.pID)
		state.gCD = min(state.gCD, circleIntersect(p, rdXZ, state.cLn4.xy, state.cLn4.z));
	if (5 < state.pID)
		state.gCD = min(state.gCD, circleIntersect(p, rdXZ, state.cLn5.xy, state.cLn5.z));

	state.gCD = max(state.gCD, 0.0) + 0.005;

	float h = hm(id + 0.13) * 0.42 + 0.03;
	float d = opExtrusion(d2, p3.y - h / 2.0 + 0.5, h / 2.0 + 0.5, 0.004);

	d += max(d2, -0.024) * 0.15;
	d += length(state.gP - state.cntr) * 0.03;
	d = max(d, -abs(d2 + 0.012) + 0.0025);

	state.gVal = vec4(d2, id, h);

	state.vObj = vec4(fl, d, 1e5, 1e5);

	return min(fl, d);
}

float trace(vec3 ro, vec3 rd, inout MapState state)
{
	float t = (0.5 - ro.y) / rd.y;
	float d = 0.0;

	for (int i = 0; i < 96; i++)
	{
		d = map(ro + rd * t, rd, state);
		if (abs(d) < 0.001 || t > FAR)
			break;
		t += min(d * 0.8, state.gCD);
	}

	return min(t, FAR);
}

vec3 normal(vec3 p, vec3 rd)
{
	float sgn = 1.0;
	vec3 e = vec3(0.002, 0.0, 0.0);
	vec3 mp = e.zzz;
	MapState dummy;
	for (int i = 0; i < 6; i++)
	{
		mp.x += map(p + sgn * e, rd, dummy) * sgn;
		sgn = -sgn;
		if ((i & 1) == 1)
		{
			mp = mp.yzx;
			e = e.zxy;
		}
	}
	return normalize(mp);
}

float softShadow(vec3 ro, vec3 rd, vec3 n, float lDist, float k)
{
	float shade = 1.0;
	float t = 0.0;

	ro += n * 0.0015 + rd * hash31(ro + rd + n) * 0.005;

	lDist = (0.5 - ro.y) / rd.y;

	MapState state;
	for (int i = 0; i < 48; i++)
	{
		float d = map(ro + rd * t, rd, state);
		shade = min(shade, k * d / t);

		if (d < 0.0 || t > lDist)
			break;

		t += clamp(min(d * 0.8, state.gCD), 0.01, 0.25);
	}

	return max(shade, 0.0);
}

float calcAO(vec3 p, vec3 n, vec3 rd)
{
	float sca = 2.0;
	float occ = 0.0;
	MapState dummy;
	for (int i = 0; i < 5; i++)
	{
		float hr = float(i + 1) * 0.15 / 5.0;
		float d = map(p + n * hr, rd, dummy);
		occ += (hr - d) * sca;
		sca *= 0.75;
	}
	return clamp(1.0 - occ, 0.0, 1.0);
}

void fragment()
{
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 fragCoord = vec2(UV.x, 1.0 - UV.y) * resolution;

	vec2 uv = (fragCoord - resolution * 0.5) / resolution.y;
	uv *= 0.85 + dot(uv, uv) * 0.3;

	vec3 lk = vec3(TIME / 6.0, 0.0, TIME / 16.0);
	vec3 ro = lk + vec3(-0.1, 1.0, -0.1);

	vec3 lp = ro + vec3(0.75, 0.0, 1.5);

	float fov = TAU / 6.0;

	vec3 camDir = normalize(lk - ro);
	vec3 worldFwd = vec3(0.0, 0.0, 1.0);
	vec3 camRight = normalize(cross(worldFwd, camDir));
	vec3 camUp = cross(camDir, camRight);

	vec3 rd = normalize(camRight * uv.x + camUp * uv.y + camDir / fov);

	MapState state;
	float t = trace(ro, rd, state);

	int objID = state.vObj.x < state.vObj.y ? 0 : 1;

	vec4 svVal = state.gVal;

	vec3 col = vec3(0.0);

	if (t < FAR)
	{
		vec3 sp = ro + rd * t;
		vec3 sn = normal(sp, rd);

		vec3 ld = lp - sp;
		float lDist = max(length(ld), 0.001);
		ld /= lDist;

		float sh = softShadow(sp, ld, sn, lDist, 16.0);
		float ao = calcAO(sp, sn, rd);

		float atten = 1.0 / (1.0 + lDist * 0.05);

		vec3 texCol = vec3(0.6);

		int rim = 0;

		if (objID > 0)
		{
			rim = svVal.x < -0.012 - 0.0025 / 2.0 ? 0 : 1;

			vec2 iid = svVal.yz;
			float rnd = hash21(iid + 0.1);
			texCol = 0.5 + 0.45 * cos(TAU * rnd / 4.0 + vec3(0.0, 1.0, 2.0));

			texCol = mix(texCol.zyx, texCol.yxz, smoothstep(-0.6, 0.6, -uv.y));

			if (rim == 1)
				texCol = vec3(0.05);
			else
				texCol /= 4.0;
		}
		else
			texCol = vec3(0.05);

		float bac = clamp(dot(sn, -normalize(vec3(ld.x, 0.0, ld.z))), 0.0, 1.0);
		texCol += texCol * vec3(1.0, 0.97, 0.92) * bac * 8.0;

		float amb = length(sin(sn * 2.0) * 0.5 + 0.5) / sqrt(3.0) * smoothstep(-1.0, 1.0, sn.y);

		float af = rim == 1 ? 3.0 : 1.0;
		amb += amb * af / (1.0 + t * t);

		float type = 0.8;
		float rough = 0.25;
		float fresRef = 0.5;

		vec3 h = normalize(ld - rd);
		float ndl = dot(sn, ld);
		float nr = clamp(dot(sn, -rd), 0.0, 1.0);
		float nl = clamp(ndl, 0.0, 1.0);
		float nh = clamp(dot(sn, h), 0.0, 1.0);
		float vh = clamp(dot(-rd, h), 0.0, 1.0);
		vec3 f0 = vec3(0.16 * (fresRef * fresRef));
		f0 = mix(f0, texCol, type);
		vec3 fs = f0 + (1.0 - f0) * pow(1.0 - vh, 5.0);

		vec3 spec = getSpec(fs, nh, nr, nl, rough);
		vec3 diff = getDiff(fs, nl, type);
		float speR = pow(nh, 5.0);

		col = texCol * (diff * sh + spec * sh + amb * (sh * 0.5 + 0.5));

		col *= ao * atten;

		vec3 rf = reflect(rd, sn);
		vec3 rTx = vec3(0.0);
		float rF = objID == 0 ? 0.0 : rim == 1 ? 16.0 : 8.0;
		col = col + col * speR * rTx * rF;
	}

	col = mix(col, vec3(0.0), smoothstep(0.0, 0.99, t / FAR));

	uv = fragCoord / resolution;
	col *= pow(16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y), 1.0 / 16.0);

	COLOR = vec4(pow(max(col, 0.0), vec3(1.0) / 2.2), 1.0);
}
