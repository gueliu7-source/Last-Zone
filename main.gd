extends Spatial
# Cena principal: monta o mapa, spawna jogador/bots/itens e controla o HUD.
# Tudo é feito para rodar leve em PCs fracos (GLES2, sem sombras, 960x540).

const PlayerScript = preload("res://player.gd")
const BotScript = preload("res://bot.gd")
const ZoneScript = preload("res://zone.gd")
const FX = preload("res://fx.gd")
const MapData = preload("res://map_data.gd")

const BOT_COUNT := 15
const PICKUP_COUNT := 44

var rng := RandomNumberGenerator.new()
var player
var zone
var env
var bots: Array = []
var pickups: Array = []
var last_region := ""
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
var lbl_region


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_PROCESS
    randomize()
    rng.randomize()
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    OS.window_size = Vector2(1280, 720)
    OS.center_window()

    _setup_environment()
    _build_island()

    var pool: Array = MapData.SPAWNS.duplicate()
    pool.shuffle()
    var spawns: Array = []
    for i in range(BOT_COUNT + 1):
        spawns.append(pool[i % pool.size()])

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
    env.fog_depth_begin = 85.0
    env.fog_depth_end = 160.0
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


func _build_island() -> void:
    # Água (plano grande no nível 0); a ilha fica por cima
    var water := MeshInstance.new()
    var pm := PlaneMesh.new()
    pm.size = Vector2(900, 900)
    water.mesh = pm
    water.translation = Vector3(0, 0.0, 0)
    var wmat := FX.make_mat(Color(0.18, 0.52, 0.78))
    water.material_override = wmat
    water.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
    add_child(water)

    var island_mat := SpatialMaterial.new()
    island_mat.vertex_color_use_as_albedo = true
    island_mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
    island_mat.roughness = 1.0
    island_mat.metallic = 0.0

    var root = null
    if ResourceLoader.exists("res://island.glb"):
        var res = load("res://island.glb")
        if res != null and res is PackedScene:
            root = res.instance()
    if root != null:
        add_child(root)
        _style_island(root, island_mat)
    else:
        # Sem o arquivo da ilha: chão plano de emergência
        var body := StaticBody.new()
        var cs := CollisionShape.new()
        var bs := BoxShape.new()
        bs.extents = Vector3(170, 0.5, 170)
        cs.shape = bs
        body.add_child(cs)
        body.translation = Vector3(0, 0.5, 0)
        add_child(body)

    # Colisores de prédios, árvores, caixas... (todos num corpo só)
    var sb := StaticBody.new()
    for b in MapData.BOXES:
        var cs2 := CollisionShape.new()
        var bs2 := BoxShape.new()
        bs2.extents = Vector3(b[3], b[4], b[5]) * 0.5
        cs2.shape = bs2
        cs2.transform = Transform(Basis(Vector3(0, 1, 0), b[6]), Vector3(b[0], b[1], b[2]))
        sb.add_child(cs2)
    add_child(sb)

    # Fundo do mar (rede de segurança) e paredes invisíveis na borda do mapa
    var edge := StaticBody.new()
    var floor_cs := CollisionShape.new()
    var floor_bs := BoxShape.new()
    floor_bs.extents = Vector3(260, 0.5, 260)
    floor_cs.shape = floor_bs
    floor_cs.translation = Vector3(0, -3.0, 0)
    edge.add_child(floor_cs)
    var h: float = MapData.HALF - 2.0
    for w in [Vector3(0, 10, h), Vector3(0, 10, -h), Vector3(h, 10, 0), Vector3(-h, 10, 0)]:
        var wc := CollisionShape.new()
        var wb := BoxShape.new()
        if abs(w.x) > 1.0:
            wb.extents = Vector3(1, 20, 200)
        else:
            wb.extents = Vector3(200, 20, 1)
        wc.shape = wb
        wc.translation = w
        edge.add_child(wc)
    add_child(edge)


func _style_island(node: Node, mat: Material) -> void:
    if node is MeshInstance:
        node.material_override = mat
        node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        if node.name.begins_with("T_"):
            node.create_trimesh_collision()
    for c in node.get_children():
        _style_island(c, mat)


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

    var loot: Array = MapData.LOOT.duplicate()
    loot.shuffle()
    for i in range(min(PICKUP_COUNT, loot.size())):
        var kind: String = "ammo"
        if i % 2 == 0:
            kind = "health"
        var p: Vector3 = loot[i]
        var mi := MeshInstance.new()
        mi.mesh = box
        if kind == "health":
            mi.material_override = health_mat
        else:
            mi.material_override = ammo_mat
        mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        mi.translation = Vector3(p.x, p.y + 0.4, p.z)
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
    lbl_region = _make_label(Control.PRESET_CENTER_TOP, 22)
    lbl_region.margin_top = 40


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
    lbl_region.text = _region_name(player.translation)
    if not game_over:
        if captured:
            lbl_center.text = ""
        else:
            lbl_center.text = "CLIQUE PARA JOGAR\n\nWASD mover  •  Mouse mirar  •  Botão esquerdo atirar\nShift correr  •  Espaço pular  •  R recarregar  •  Esc pausar\nF11 tela cheia  •  F2 modo leve\n\nCubos verdes = vida  •  Cubos amarelos = munição\nFique dentro da zona segura!"


func _region_name(p: Vector3) -> String:
    var best: String = ""
    var best_d: float = 1e9
    for r in MapData.REGIONS:
        var d: float = Vector2(p.x - r[1], p.z - r[2]).length()
        if d <= r[3] and d < best_d:
            best_d = d
            best = r[0]
    return best


func set_quality(q: int) -> void:
    quality = q
    var cam = player.cam
    if q == 0:
        cam.far = 170.0
        env.fog_depth_begin = 85.0
        env.fog_depth_end = 160.0
    else:
        cam.far = 90.0
        env.fog_depth_begin = 45.0
        env.fog_depth_end = 85.0


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
