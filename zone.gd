extends Spatial
# Zona segura que fecha em fases (estilo battle royale).

const WAIT_TIME := 20.0
const SHRINK_TIME := 15.0

var radii: Array = [88.0, 60.0, 38.0, 22.0, 10.0, 3.0]

var center := Vector3.ZERO
var radius: float = 88.0
var phase := 0
var timer: float = 20.0
var shrinking := false

var from_radius: float = 88.0
var to_radius: float = 88.0
var from_center := Vector3.ZERO
var to_center := Vector3.ZERO

var mi


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_STOP
    mi = MeshInstance.new()
    mi.mesh = _build_tube()
    var mat := SpatialMaterial.new()
    mat.albedo_color = Color(1.0, 0.15, 0.1, 0.22)
    mat.flags_transparent = true
    mat.flags_unshaded = true
    mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
    mi.material_override = mat
    mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
    add_child(mi)
    _update_visual()


# Tubo aberto (sem tampas) com raio 1 e altura 80; é escalado conforme o raio da zona.
func _build_tube() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var n: int = 64
    var h: float = 80.0
    for i in range(n):
        var a0: float = TAU * float(i) / float(n)
        var a1: float = TAU * float(i + 1) / float(n)
        var b0 := Vector3(cos(a0), 0.0, sin(a0))
        var b1 := Vector3(cos(a1), 0.0, sin(a1))
        var t0 := Vector3(cos(a0), h, sin(a0))
        var t1 := Vector3(cos(a1), h, sin(a1))
        st.add_vertex(b0)
        st.add_vertex(b1)
        st.add_vertex(t1)
        st.add_vertex(b0)
        st.add_vertex(t1)
        st.add_vertex(t0)
    return st.commit()


func _process(delta: float) -> void:
    if phase < radii.size() - 1:
        timer -= delta
        if not shrinking:
            if timer <= 0.0:
                shrinking = true
                timer = SHRINK_TIME
                from_radius = radius
                from_center = center
                to_radius = radii[phase + 1]
                var ang: float = randf() * TAU
                var d: float = randf() * max(0.0, from_radius - to_radius)
                to_center = from_center + Vector3(cos(ang) * d, 0.0, sin(ang) * d)
        else:
            var t: float = 1.0 - clamp(timer / SHRINK_TIME, 0.0, 1.0)
            radius = lerp(from_radius, to_radius, t)
            center = from_center.linear_interpolate(to_center, t)
            if timer <= 0.0:
                shrinking = false
                timer = WAIT_TIME
                phase += 1
    _update_visual()


func _update_visual() -> void:
    var r: float = max(radius, 0.5)
    mi.scale = Vector3(r, 1.0, r)
    mi.translation = Vector3(center.x, 0.0, center.z)


func is_outside(pos: Vector3) -> bool:
    return Vector2(pos.x - center.x, pos.z - center.z).length() > radius


func damage_per_second() -> float:
    return 1.0 + float(phase) * 1.5


func status_text() -> String:
    if phase >= radii.size() - 1:
        return "ZONA FINAL!  Dano: %d/s" % int(damage_per_second())
    if shrinking:
        return "ZONA FECHANDO!  Dano: %d/s" % int(damage_per_second())
    return "Zona fecha em %ds" % int(ceil(timer))
