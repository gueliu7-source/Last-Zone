shader_type spatial;
render_mode unshaded, cull_disabled;
// Mato balançando com o vento. COLOR.a = 0 na raiz e 1 na ponta (quanto balança).
uniform float wind_speed = 2.2;
uniform float wind_force = 0.16;
varying vec3 vcol;

void vertex() {
    vcol = COLOR.rgb;
    vec3 wp = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float ph = wp.x * 0.35 + wp.z * 0.27;
    float gust = sin(TIME * wind_speed + ph) + 0.5 * sin(TIME * wind_speed * 2.3 + ph * 1.9);
    VERTEX.x += gust * wind_force * COLOR.a;
    VERTEX.z += cos(TIME * wind_speed * 0.8 + ph) * wind_force * 0.6 * COLOR.a;
}

void fragment() {
    ALBEDO = vcol;
}
