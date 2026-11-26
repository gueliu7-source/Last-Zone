shader_type spatial;
// Contorno preto (casco invertido): desenha o modelo de novo, um pouco inchado,
// mostrando só as faces de trás em preto. A espessura cresce com a distância
// para o contorno continuar visível nos inimigos longe.
render_mode cull_front, unshaded;

uniform float width = 0.02;
uniform float far_boost = 5.0;      // quanto a linha pode engrossar de longe (vezes)
uniform vec4 line_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
    float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
    VERTEX += NORMAL * width * clamp(dist / 4.0, 1.0, far_boost);
}

void fragment() {
    ALBEDO = line_color.rgb;
}
