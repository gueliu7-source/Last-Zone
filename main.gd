extends Spatial
# Cena principal: monta o mapa, spawna jogador/bots/itens e controla o HUD.
# Tudo é feito para rodar leve em PCs fracos (GLES2, sem sombras, 960x540).

const PlayerScript = preload("res://player.gd")
const BotScript = preload("res://bot.gd")
const ZoneScript = preload("res://zone.gd")
const FX = preload("res://fx.gd")
const MapData = preload("res://map_data.gd")
const Sfx = preload("res://sfx.gd")
const BrainScript = preload("res://brain.gd")

const PLANE_Y := 260.0
const PLANE_SPEED := 30.0

const BOT_COUNT := 15
const PICKUP_COUNT := 44

var rng := RandomNumberGenerator.new()
var player
var zone
var env
var bots: Array = []
var pickups: Array = []
var last_region := ""
var sfx_bank := {}
var brain
var cover_points: Array = []   # [x, z, raio] de prédios/caixas grandes (cobertura dos bots)
var loop_wind
var loop_engine
var plane
var plane_dir := Vector3.FORWARD
var plane_end := Vector3.ZERO
var was_shrinking := false
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

    brain = BrainScript.new()
    brain.load_data()
    for b in MapData.BOXES:
        if b[4] > 2.2 and max(b[3], b[5]) > 1.5:
            cover_points.append([b[0], b[2], max(b[3], b[5]) * 0.5])
    _setup_environment()
    _setup_audio()
    _build_island()

    var pool: Array = MapData.SPAWNS.duplicate()
    pool.shuffle()
    var spawns: Array = []
    for i in range(BOT_COUNT + 1):
        spawns.append(pool[i % pool.size()])

    zone = ZoneScript.new()
    add_child(zone)

    player = PlayerScript.new()
    add_child(player)
    player.connect("died", self, "_on_player_died")
    player.connect("landed", self, "_on_landed")

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
    _start_flight()


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

    var grass_mat := ShaderMaterial.new()
    grass_mat.shader = load("res://grass.shader")

    var root = null
    if ResourceLoader.exists("res://island.glb"):
        var res = load("res://island.glb")
        if res != null and res is PackedScene:
            root = res.instance()
    if root != null:
        add_child(root)
        _style_island(root, island_mat, grass_mat)
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


func _style_island(node: Node, mat: Material, gmat: Material) -> void:
    if node is MeshInstance:
        node.material_override = mat
        node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        if node.name.begins_with("G_"):
            node.material_override = gmat
            node.add_to_group("grass")
        elif node.name.begins_with("T_"):
            node.create_trimesh_collision()
    for c in node.get_children():
        _style_island(c, mat, gmat)


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


# ---------------------------------------------------------------- som

func _setup_audio() -> void:
    sfx_bank = Sfx.build_all()
    loop_wind = AudioStreamPlayer.new()
    loop_wind.stream = sfx_bank["wind"]
    loop_wind.volume_db = -60.0
    add_child(loop_wind)
    loop_wind.play()
    loop_engine = AudioStreamPlayer.new()
    loop_engine.stream = sfx_bank["engine"]
    loop_engine.volume_db = -60.0
    add_child(loop_engine)
    loop_engine.play()


# pos == null: som "na cabeça" (2D). Com posição: som 3D que some com a distância.
func snd(sname: String, pos = null, db: float = 0.0, pitch: float = 1.0) -> void:
    if not sfx_bank.has(sname):
        return
    if pos == null:
        var p := AudioStreamPlayer.new()
        p.stream = sfx_bank[sname]
        p.volume_db = db
        p.pitch_scale = pitch
        add_child(p)
        p.play()
        p.connect("finished", p, "queue_free")
    else:
        if player != null and Vector2(pos.x - player.translation.x, pos.z - player.translation.z).length() > 95.0:
            return
        var p3 := AudioStreamPlayer3D.new()
        p3.stream = sfx_bank[sname]
        p3.unit_db = db
        p3.unit_size = 10.0
        p3.max_distance = 110.0
        p3.pitch_scale = pitch
        add_child(p3)
        p3.translation = pos
        p3.play()
        p3.connect("finished", p3, "queue_free")


func _update_loops(delta: float) -> void:
    var wind_db: float = -60.0
    var eng_db: float = -60.0
    if player.alive:
        if player.mode == "plane":
            eng_db = -8.0
            wind_db = -22.0
        elif player.mode == "fall":
            wind_db = -3.0
        elif player.mode == "chute":
            wind_db = -13.0
        else:
            wind_db = -27.0
    loop_wind.volume_db = lerp(loop_wind.volume_db, wind_db, min(4.0 * delta, 1.0))
    loop_engine.volume_db = lerp(loop_engine.volume_db, eng_db, min(4.0 * delta, 1.0))


# ---------------------------------------------------------------- avião e queda

func _make_plane() -> Spatial:
    var root := Spatial.new()
    var mat = FX.make_mat(Color(0.82, 0.84, 0.88))
    var dark = FX.make_mat(Color(0.25, 0.3, 0.45))
    var parts := [
        [Vector3(2.4, 2.2, 12.0), Vector3(0, 0, 0), mat],
        [Vector3(16.0, 0.25, 2.8), Vector3(0, -0.2, 0.8), dark],
        [Vector3(5.5, 0.25, 1.8), Vector3(0, 0.2, 5.2), dark],
        [Vector3(0.25, 2.4, 2.0), Vector3(0, 1.6, 5.2), dark],
        [Vector3(1.9, 1.0, 1.6), Vector3(0, 0.5, -6.2), dark]
    ]
    for pt in parts:
        var mi := MeshInstance.new()
        var cm := CubeMesh.new()
        cm.size = pt[0]
        mi.mesh = cm
        mi.translation = pt[1]
        mi.material_override = pt[2]
        mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        root.add_child(mi)
    return root


func _start_flight() -> void:
    var ang: float = rng.randf() * TAU
    plane_dir = Vector3(cos(ang), 0.0, sin(ang))
    var side: Vector3 = Vector3(-plane_dir.z, 0.0, plane_dir.x) * rng.randf_range(-45.0, 45.0)
    var start: Vector3 = -plane_dir * 215.0 + side
    plane_end = plane_dir * 215.0 + side
    plane = _make_plane()
    plane.translation = Vector3(start.x, PLANE_Y, start.z)
    plane.rotation.y = atan2(-plane_dir.x, -plane_dir.z)
    add_child(plane)
    player.begin_flight(plane, plane_dir * PLANE_SPEED, plane.rotation.y)
    # Visão longa e sem neblina enquanto está no ar
    player.cam.far = 900.0
    player.cam.near = 0.3
    env.fog_enabled = false
    for g in get_tree().get_nodes_in_group("grass"):
        g.visible = false


# Alguém atirou: os bots por perto vão investigar (é assim que eles acabam brigando entre si)
func alert(pos: Vector3, src) -> void:
    for b in bots:
        if is_instance_valid(b) and b != src and b.alive:
            b.hear(pos)


# Bot pegou um item de cura
func take_pickup(item) -> bool:
    if not pickups.has(item):
        return false
    pickups.erase(item)
    var node = item["node"]
    snd("pickup", node.translation, -6.0)
    node.queue_free()
    return true


func _notification(what: int) -> void:
    if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST and brain != null:
        brain.save_data()


func _on_landed() -> void:
    zone.active = true
    player.cam.near = 0.1
    env.fog_enabled = true
    fps_timer = -4.0
    set_quality(quality)


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
    lbl_top_left.text = "VIVOS: %d\nABATES: %d\nIA: nível %d%%" % [alive_count, kills, int((brain.skill() - 0.3) / 0.5 * 100.0)]
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
    var hint: String = ""
    if player.mode == "plane":
        hint = "\nESPAÇO: pular do avião"
    elif player.mode == "fall":
        hint = "\nESPAÇO: abrir paraquedas (abre sozinho perto do chão)  •  WASD: direcionar"
    elif player.mode == "chute":
        hint = "\nWASD: direcionar a descida"
    if player.mode != "ground":
        hint += "\nALTURA: %d m" % int(player.translation.y)
    lbl_region.text = _region_name(player.translation) + hint
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
    if player.mode != "ground":
        return
    var cam = player.cam
    if q == 0:
        cam.far = 170.0
        env.fog_depth_begin = 85.0
        env.fog_depth_end = 160.0
    else:
        cam.far = 90.0
        env.fog_depth_begin = 45.0
        env.fog_depth_end = 85.0
    for g in get_tree().get_nodes_in_group("grass"):
        g.visible = (q == 0)


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
    loop_wind.stream_paused = get_tree().paused
    loop_engine.stream_paused = get_tree().paused
    if get_tree().paused:
        return

    _update_loops(delta)

    # A IA observa como o jogador se move durante os tiroteios
    if player.alive and player.mode == "ground":
        var fighters: Array = []
        for b in bots:
            if is_instance_valid(b) and b.alive and b.enemy == player and b.enemy_visible:
                fighters.append(b)
        brain.observe(player, fighters, delta)

    # Avião: voa em linha reta; se o jogador não pular, é lançado no fim da rota
    if plane != null and is_instance_valid(plane):
        plane.translation += plane_dir * PLANE_SPEED * delta
        if player.mode == "plane" and (plane.translation - plane_end).dot(plane_dir) > 0.0:
            player.jump_out()
        if (plane.translation - Vector3(0, PLANE_Y, 0)).length() > 330.0:
            plane.queue_free()
            plane = null

    # Qualidade automática: se ficar abaixo de 50 fps, ativa o modo leve
    fps_timer += delta
    if fps_timer >= 3.0:
        fps_timer = 0.0
        if quality == 0 and player.mode == "ground" and Engine.get_frames_per_second() < 50:
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
            snd("pickup", null, -4.0)
            pickups.erase(p)
            node.queue_free()

    # Dano da zona
    var dps: float = zone.damage_per_second()
    if zone.shrinking and not was_shrinking:
        snd("zone", null, -4.0)
    was_shrinking = zone.shrinking
    if player.alive and player.mode == "ground" and zone.is_outside(player.translation):
        player.take_damage(dps * delta, null)
    for b in bots:
        if zone.active and is_instance_valid(b) and b.alive and zone.is_outside(b.translation):
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
    brain.save_data()
    get_tree().paused = false
    if won:
        snd("win", null, -2.0)
    else:
        snd("lose", null, -2.0)
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    if won:
        lbl_center.text = "BOOYAH!\nVocê é o último sobrevivente!\n\nAbates: %d\n\nPressione R para jogar de novo" % kills
    else:
        lbl_center.text = "VOCÊ FOI ELIMINADO\n\nPosição: #%d   •   Abates: %d\n\nPressione R para jogar de novo" % [rank, kills]
