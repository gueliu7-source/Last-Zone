extends Spatial
# Carrega um personagem .glb, ajusta o tamanho, aplica cel shading + contorno preto
# e controla as animações (idle / run / shoot / death).

const CEL_SHADER = preload("res://cel.shader")
const OUTLINE_SHADER = preload("res://outline.shader")

const ALIASES = {
    "idle": ["idle", "Idle", "IDLE", "stand", "Stand"],
    "run": ["run", "Run", "RUN", "walk", "Walk", "WALK"],
    "shoot": ["shoot", "Shoot", "SHOOT", "fire", "Fire", "attack", "Attack"],
    "death": ["death", "Death", "DEATH", "die", "Die"]
}

var model_root = null
var anim = null
var cels: Array = []
var outlines: Array = []     # [cel_material, outline_material]
var lod := 0                 # 0 perto (contorno + animação), 1 médio (sem contorno), 2 longe (sem contorno, animação parada)
var current := ""
var lock := 0.0


# Retorna false se o arquivo não existir (aí o jogo usa o boneco simples).
func setup(path: String, height: float, yaw_deg: float, outline_world: float) -> bool:
    if not ResourceLoader.exists(path):
        return false
    var res = load(path)
    if res == null or not (res is PackedScene):
        return false

    model_root = res.instance()
    add_child(model_root)
    model_root.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)

    # Mede o modelo e ajusta para a altura desejada, com os pés no chão
    var acc: Array = []
    _measure(model_root, acc)
    var s: float = 1.0
    var foot: float = 0.0
    if not acc.empty():
        var box: AABB = acc[0]
        if box.size.y > 0.001:
            s = height / box.size.y
            foot = -box.position.y * s
    model_root.scale = Vector3(s, s, s)
    model_root.translation = Vector3(0.0, foot, 0.0)

    _style(model_root, outline_world / s)
    anim = _find_anim(model_root)
    play("idle")
    return true


func _measure(node: Node, acc: Array) -> void:
    if node is MeshInstance and node.mesh != null:
        var rel: Transform = global_transform.affine_inverse() * node.global_transform
        var b: AABB = rel.xform(node.get_aabb())
        if acc.empty():
            acc.append(b)
        else:
            acc[0] = acc[0].merge(b)
    for c in node.get_children():
        _measure(c, acc)


func _style(node: Node, outline_width: float) -> void:
    if node is MeshInstance and node.mesh != null:
        node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        for i in range(node.mesh.get_surface_count()):
            var orig = node.get_active_material(i)
            var cel := ShaderMaterial.new()
            cel.shader = CEL_SHADER
            if orig != null and orig is SpatialMaterial:
                cel.set_shader_param("tint", orig.albedo_color)
                if orig.albedo_texture != null:
                    cel.set_shader_param("albedo_tex", orig.albedo_texture)
            var ol := ShaderMaterial.new()
            ol.shader = OUTLINE_SHADER
            ol.set_shader_param("width", outline_width)
            cel.next_pass = ol
            outlines.append([cel, ol])
            node.set_surface_material(i, cel)
            cels.append(cel)
    for c in node.get_children():
        _style(c, outline_width)


func set_lod(l: int) -> void:
    if l == lod or lod == -1 or current == "death":
        return
    lod = l
    for e in outlines:
        e[0].next_pass = e[1] if l == 0 else null
    if anim != null and current != "death":
        anim.playback_active = (l < 2)


func _find_anim(node: Node):
    if node is AnimationPlayer:
        return node
    for c in node.get_children():
        var r = _find_anim(c)
        if r != null:
            return r
    return null


func _resolve(action: String) -> String:
    if anim == null:
        return ""
    for n in ALIASES.get(action, [action]):
        if anim.has_animation(n):
            return n
    # Sem animação chamada "idle": usa a primeira que existir
    if action == "idle":
        var list = anim.get_animation_list()
        if list.size() > 0:
            return list[0]
    return ""


func has_anim(action: String) -> bool:
    return _resolve(action) != ""


func play(action: String) -> void:
    if anim == null or lock > 0.0 or action == current:
        return
    var n: String = _resolve(action)
    if n == "":
        return
    if action == "idle" or action == "run":
        anim.get_animation(n).loop = true
    anim.play(n, 0.15)
    current = action


func play_once(action: String) -> void:
    if anim == null:
        return
    # Atirando correndo: mantém a corrida (os braços já estão na posição de tiro)
    if action == "shoot" and current == "run":
        return
    var n: String = _resolve(action)
    if n == "":
        return
    var a = anim.get_animation(n)
    a.loop = false
    if action == "death":
        anim.playback_active = true
        lod = -1   # morto: nunca mais pausa a animação
    anim.play(n, 0.05)
    current = action
    lock = a.length
    if action == "death":
        lock = 99999.0


func _process(delta: float) -> void:
    if lock > 0.0 and lock < 90000.0:
        lock -= delta
        if lock <= 0.0:
            current = ""


# Cor de variação para os bots não ficarem todos iguais (mistura leve com a cor original)
func set_tint(c: Color) -> void:
    for m in cels:
        var base = m.get_shader_param("tint")
        if base == null:
            base = Color(1, 1, 1, 1)
        m.set_shader_param("tint", base.linear_interpolate(c, 0.25))


func set_flash(v: float) -> void:
    for m in cels:
        m.set_shader_param("flash", v)


func set_dark(v: float) -> void:
    for m in cels:
        m.set_shader_param("dark", v)
