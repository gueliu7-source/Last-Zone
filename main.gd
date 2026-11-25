extends Spatial
# Cena principal: monta o mapa, spawna jogador/bots/itens e controla o HUD.
# Tudo é feito para rodar leve em PCs fracos (GLES2, sem sombras, 960x540).

const PlayerScript = preload("res://player.gd")
const BotScript = preload("res://bot.gd")
const ZoneScript = preload("res://zone.gd")
const FX = preload("res://fx.gd")

const MAP_RADIUS := 85.0
const BOT_COUNT := 15

var rng := RandomNumberGenerator.new()
var player
var zone
var env
var bots: Array = []
var pickups: Array = []
var obstacles: Array = []   # Vector3(x, raio, z)
var mat_cache := {}
var kills := 0
var rank := 0
var game_over := false

var quality := 0            # 0 = normal, 1 = leve (automático se cair de 50 fps)
var fps_timer := -4.0

var hud
var lbl_top_left
var lbl_top_right
var lbl_fps
var lbl_health
var lbl_ammo
var lbl_center
var lbl_cross


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_PROCESS
    randomize()
    rng.randomize()
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    OS.window_size = Vector2(1280, 720)
    OS.center_window()

    _setup_environment()
    add_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400), Color(0.28, 0.5, 0.25))

    var spawns: Array = []
    for i in range(BOT_COUNT + 1):
        spawns.append(_random_spawn(spawns))

    _build_scenery(spawns)

    zone = ZoneScript.new()
    add_child(zone)

    player = PlayerScript.new()
    player.translation = spawns[0]
    add_child(player)
    player.connect("died", self, "_on_player_died")

    for i in range(BOT_COUNT):
        var b = BotScript.new()
        b.translation = spawns[i + 1]
        b.target = player
        b.zone = zone
        add_child(b)
        b.connect("bot_died", self, "_on_bot_died")
        bots.append(b)

    _spawn_pickups(spawns)
    _build_hud()


# ---------------------------------------------------------------- mundo

func _setup_environment() -> void:
    env = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.55, 0.75, 0.95)
    env.ambient_light_color = Color(0.7, 0.72, 0.8)
    env.ambient_light_energy = 0.8
    env.fog_enabled = true
    env.fog_color = Color(0.55, 0.75, 0.95)
    env.fog_depth_begin = 60.0
    env.fog_depth_end = 125.0
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)

    var sun := DirectionalLight.new()
    sun.rotation_degrees = Vector3(-50, -30, 0)
    sun.light_energy = 0.9
    sun.shadow_enabled = false
    add_child(sun)


func _mat(color: Color):
    if not mat_cache.has(color):
        mat_cache[color] = FX.make_mat(color)
    return mat_cache[color]


func add_box(pos: Vector3, size: Vector3, color: Color) -> StaticBody:
    var body := StaticBody.new()
    body.translation = pos
    var cs := CollisionShape.new()
    var bs := BoxShape.new()
    bs.extents = size / 2.0
    cs.shape = bs
    body.add_child(cs)
    var mi := MeshInstance.new()
    var cm := CubeMesh.new()
    cm.size = size
    mi.mesh = cm
    mi.material_override = _mat(color)
    mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
    body.add_child(mi)
    add_child(body)
    return body


func _random_spawn(existing: Array) -> Vector3:
    var p := Vector3.ZERO
    for _t in range(60):
        var ang: float = rng.randf() * TAU
        var r: float = rng.randf_range(10.0, MAP_RADIUS - 8.0)
        p = Vector3(cos(ang) * r, 1.0, sin(ang) * r)
        var ok := true
        for s in existing:
            if Vector2(p.x - s.x, p.z - s.z).length() < 22.0:
                ok = false
                break
        if ok:
            return p
    return p


func _free_point(spawns: Array, spawn_clear: float, own_radius: float) -> Vector3:
    var p := Vector3.ZERO
    for _t in range(40):
        var ang: float = rng.randf() * TAU
        var r: float = sqrt(rng.randf()) * (MAP_RADIUS + 5.0)
        p = Vector3(cos(ang) * r, 0.0, sin(ang) * r)
        var ok := true
        for s in spawns:
            if Vector2(p.x - s.x, p.z - s.z).length() < spawn_clear:
                ok = false
                break
        if ok:
            for o in obstacles:
                if Vector2(p.x - o.x, p.z - o.z).length() < o.y + own_radius:
                    ok = false
                    break
        if ok:
            return p
    return p


func _build_scenery(spawns: Array) -> void:
    var palette := [
        Color(0.62, 0.6, 0.55), Color(0.5, 0.5, 0.52), Color(0.7, 0.62, 0.5),
        Color(0.45, 0.48, 0.55), Color(0.65, 0.55, 0.5)
    ]

    # Construções
    for _i in range(22):
        var size := Vector3(rng.randf_range(6.0, 14.0), rng.randf_range(3.0, 7.0), rng.randf_range(6.0, 14.0))
        var rad: float = max(size.x, size.z) * 0.5 + 1.0
        var p: Vector3 = _free_point(spawns, 14.0, rad)
        var col: Color = palette[rng.randi() % palette.size()]
        add_box(Vector3(p.x, size.y / 2.0, p.z), size, col)
        obstacles.append(Vector3(p.x, rad, p.z))

    # Caixotes (cobertura)
    for _i in range(18):
        var p: Vector3 = _free_point(spawns, 4.0, 1.8)
        add_box(Vector3(p.x, 0.75, p.z), Vector3(1.5, 1.5, 1.5), Color(0.55, 0.38, 0.2))
        obstacles.append(Vector3(p.x, 1.8, p.z))

    # Árvores
    var leaf_mat = FX.make_mat(Color(0.12, 0.42, 0.14))
    var leaf_mesh := SphereMesh.new()
    leaf_mesh.radius = 2.2
    leaf_mesh.height = 4.4
    leaf_mesh.radial_segments = 8
    leaf_mesh.rings = 4
    for _i in range(45):
        var p: Vector3 = _free_point(spawns, 3.0, 1.5)
        var trunk := add_box(Vector3(p.x, 2.5, p.z), Vector3(0.7, 5.0, 0.7), Color(0.35, 0.22, 0.1))
        var leaf := MeshInstance.new()
        leaf.mesh = leaf_mesh
        leaf.translation = Vector3(0, 3.5, 0)
        leaf.material_override = leaf_mat
        leaf.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        leaf.add_to_group("leaf")
        trunk.add_child(leaf)
        obstacles.append(Vector3(p.x, 1.5, p.z))


func _spawn_pickups(spawns: Array) -> void:
    var health_mat := SpatialMaterial.new()
    health_mat.albedo_color = Color(0.15, 0.9, 0.3)
    health_mat.emission_enabled = true
    health_mat.emission = Color(0.15, 0.9, 0.3)
    health_mat.emission_energy = 0.6
    var ammo_mat := SpatialMaterial.new()
    ammo_mat.albedo_color = Color(1.0, 0.85, 0.1)
    ammo_mat.emission_enabled = true
    ammo_mat.emission = Color(1.0, 0.85, 0.1)
    ammo_mat.emission_energy = 0.6
    var box := CubeMesh.new()
    box.size = Vector3(0.7, 0.7, 0.7)

    for i in range(26):
        var kind: String = "ammo"
        if i % 2 == 0:
            kind = "health"
        var p: Vector3 = _free_point(spawns, 0.0, 1.0)
        var mi := MeshInstance.new()
        mi.mesh = box
        if kind == "health":
            mi.material_override = health_mat
        else:
            mi.material_override = ammo_mat
        mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        mi.translation = Vector3(p.x, 0.8, p.z)
        add_child(mi)
        pickups.append({"node": mi, "kind": kind})


# ---------------------------------------------------------------- HUD

func _make_font(size_px: int):
    var data = load("res://font.ttf")
    if data == null:
        return null
    var f := DynamicFont.new()
    f.font_data = data
    f.size = size_px
    f.outline_size = 2
    f.outline_color = Color(0, 0, 0)
    return f


func _make_label(preset: int, size_px: int) -> Label:
    var l := Label.new()
    var f = _make_font(size_px)
    if f != null:
        l.add_font_override("font", f)
    hud.add_child(l)
    l.set_anchors_and_margins_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
    if preset == Control.PRESET_BOTTOM_RIGHT or preset == Control.PRESET_TOP_RIGHT:
        l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        l.align = Label.ALIGN_RIGHT
    if preset == Control.PRESET_BOTTOM_RIGHT or preset == Control.PRESET_BOTTOM_LEFT:
        l.grow_vertical = Control.GROW_DIRECTION_BEGIN
    if preset == Control.PRESET_CENTER_TOP:
        l.grow_horizontal = Control.GROW_DIRECTION_BOTH
        l.align = Label.ALIGN_CENTER
    return l


func _make_full_label(size_px: int) -> Label:
    var l := Label.new()
    var f = _make_font(size_px)
    if f != null:
        l.add_font_override("font", f)
    hud.add_child(l)
    l.set_anchors_and_margins_preset(Control.PRESET_WIDE)
    l.align = Label.ALIGN_CENTER
    l.valign = Label.VALIGN_CENTER
    return l


func _build_hud() -> void:
    hud = CanvasLayer.new()
    add_child(hud)

    lbl_top_left = _make_label(Control.PRESET_TOP_LEFT, 20)
    lbl_top_right = _make_label(Control.PRESET_TOP_RIGHT, 20)
    lbl_fps = _make_label(Control.PRESET_CENTER_TOP, 16)
    lbl_health = _make_label(Control.PRESET_BOTTOM_LEFT, 26)
    lbl_ammo = _make_label(Control.PRESET_BOTTOM_RIGHT, 26)

    lbl_cross = _make_full_label(24)
    lbl_cross.text = "+"
    lbl_cross.visible = false

    lbl_center = _make_full_label(26)


func _update_hud(captured: bool) -> void:
    var alive_count: int = _alive_bots()
    if player.alive:
        alive_count += 1
    lbl_top_left.text = "VIVOS: %d\nABATES: %d" % [alive_count, kills]
    lbl_top_right.text = zone.status_text()
    var q: String = ""
    if quality == 1:
        q = "  (modo leve)"
    lbl_fps.text = "FPS: %d%s" % [Engine.get_frames_per_second(), q]
    lbl_health.text = "VIDA: %d" % int(ceil(max(player.health, 0.0)))
    var a: String = "MUNIÇÃO: %d / %d" % [player.ammo, player.reserve]
    if player.reloading:
        a += "  (recarregando...)"
    lbl_ammo.text = a
    lbl_cross.visible = captured and not game_over
    if not game_over:
        if captured:
            lbl_center.text = ""
        else:
            lbl_center.text = "CLIQUE PARA JOGAR\n\nWASD mover  •  Mouse mirar  •  Botão esquerdo atirar\nShift correr  •  Espaço pular  •  R recarregar  •  Esc pausar\nF11 tela cheia  •  F2 modo leve\n\nCubos verdes = vida  •  Cubos amarelos = munição\nFique dentro da zona segura!"


func set_quality(q: int) -> void:
    quality = q
    var cam = player.cam
    if q == 0:
        cam.far = 130.0
        env.fog_depth_begin = 60.0
        env.fog_depth_end = 125.0
    else:
        cam.far = 70.0
        env.fog_depth_begin = 30.0
        env.fog_depth_end = 68.0
    for l in get_tree().get_nodes_in_group("leaf"):
        l.visible = (q == 0)


# ---------------------------------------------------------------- lógica

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and not game_over:
        if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    if event is InputEventKey and event.pressed and not event.echo:
        if event.scancode == KEY_ESCAPE:
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        elif event.scancode == KEY_R and game_over:
            get_tree().paused = false
            get_tree().reload_current_scene()
        elif event.scancode == KEY_F11:
            OS.window_fullscreen = not OS.window_fullscreen
        elif event.scancode == KEY_F2:
            set_quality(1 - quality)


func _alive_bots() -> int:
    var n := 0
    for b in bots:
        if is_instance_valid(b) and b.alive:
            n += 1
    return n


func _process(delta: float) -> void:
    var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
    if not game_over:
        get_tree().paused = not captured

    _update_hud(captured)
    if get_tree().paused:
        return

    # Qualidade automática: se ficar abaixo de 50 fps, ativa o modo leve
    fps_timer += delta
    if fps_timer >= 3.0:
        fps_timer = 0.0
        if quality == 0 and Engine.get_frames_per_second() < 50:
            set_quality(1)

    # Itens: girar e coletar
    for p in pickups.duplicate():
        var node = p["node"]
        node.rotate_y(delta * 2.0)
        if player.alive and node.translation.distance_to(player.translation + Vector3(0, 0.8, 0)) < 1.8:
            if p["kind"] == "health":
                player.heal(40.0)
            else:
                player.add_ammo(30)
            pickups.erase(p)
            node.queue_free()

    # Dano da zona
    var dps: float = zone.damage_per_second()
    if player.alive and zone.is_outside(player.translation):
        player.take_damage(dps * delta, null)
    for b in bots:
        if is_instance_valid(b) and b.alive and zone.is_outside(b.translation):
            b.take_damage(dps * delta, null)

    # Vitória
    if not game_over and player.alive and _alive_bots() == 0:
        _finish(true)


func _on_player_died() -> void:
    rank = _alive_bots() + 1
    _finish(false)


func _on_bot_died(killer) -> void:
    if killer == player:
        kills += 1


func _finish(won: bool) -> void:
    if game_over:
        return
    game_over = true
    get_tree().paused = false
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    if won:
        lbl_center.text = "BOOYAH!\nVocê é o último sobrevivente!\n\nAbates: %d\n\nPressione R para jogar de novo" % kills
    else:
        lbl_center.text = "VOCÊ FOI ELIMINADO\n\nPosição: #%d   •   Abates: %d\n\nPressione R para jogar de novo" % [rank, kills]
