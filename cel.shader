shader_type spatial;
// Sombreado de desenho (cel shading) calculado POR PIXEL, sem depender das luzes da cena
// (assim funciona mesmo com "force_vertex_shading" ligado, que deixa o jogo leve).
render_mode unshaded;

uniform sampler2D albedo_tex : hint_albedo;
uniform vec4 tint : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 light_dir = vec3(-0.321, 0.766, 0.557);  // direção PARA a luz (mundo); igual ao sol do main.gd
uniform float flash = 0.0;   // 1.0 = piscar branco ao levar dano
uniform float dark = 0.0;    // 1.0 = escurecido (morto)

varying vec3 wn;

void vertex() {
    wn = (WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
    float nl = dot(normalize(wn), normalize(light_dir));
    // 3 faixas: sombra, meio-tom, luz
    float shade = 0.58 + 0.24 * smoothstep(-0.05, 0.05, nl) + 0.18 * smoothstep(0.35, 0.45, nl);
    c *= shade;
    c = mix(c, c * 0.45, dark);
    c = mix(c, vec3(1.0), flash);
    ALBEDO = c;
}
