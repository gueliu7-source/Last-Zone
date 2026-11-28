extends KinematicBody
# Inimigo com IA simples: vagueia, foge da zona e ataca o jogador.

signal bot_died(killer)

const FX = preload("res://fx.gd")
const CharacterScript = preload("res://character.gd")
const MapData = preload("res://map_data.gd")

# Mesmos ajustes do jogador (veja player.gd)
const MODEL_HEIGHT := 1.75
const MODEL_YAW := 180.0
const OUTLINE_WIDTH := 0.02
const GUN_POS_MODEL := Vector3(-0.06, 1.23, -0.30)

const MOVE_SPEED := 4.5
const GRAVITY := 22.0
const SIGHT_RANGE := 55.0
const BOT_DAMAGE := 10.0
const MAX_HEALTH := 80.0

var health := 80.0
var alive := true
var target = null   # o jogador (definido pelo main)
var zone = null     # a zona (definida pelo main)
var main = null
var char_path := ""      # modelo escolhido pelo main (vazio = padrão)

var velocity := Vector3.ZERO
var flash_t := 0.0

# IA
var state := "roam"          # roam · loot · fight · chase · zone · investigate
var enemy = null
var enemy_visible := false
var last_seen := Vector3.ZERO
var lose_t := 0.0
var goal := Vector3.ZERO
var goal_t := 0.0
var think_t := 0.0
var strafe := 1.0
var strafe_t := 0.0
var burst_left := 0
var react_t := 0.0
var fire_cd := 1.0
var avoid_dir := Vector3.ZERO
var avoid_t := 0.0
var avoid_hold := 0.0
var loot_item = null
var loot_t := 0.0
var loot_block := 0.0
var inv_pos := Vector3.ZERO
var inv_t := 0.0
var retreat_goal := Vector3.ZERO
var retreat_t := 0.0
var stuck_t := 0.0

var chr = null
var visual
var mat
var shape_node
var base_color := Color(0.9, 0.3, 0.3)


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_STOP

    var palette := [
        Color(0.9, 0.3, 0.3), Color(0.9, 0.6, 0.2), Color(0.8, 0.3, 0.8),
        Color(0.25, 0.8, 0.8), Color(0.9, 0.9, 0.3), Color(0.6, 0.4, 0.9)
    ]
    base_color = palette[randi() % palette.size()]

    shape_node = CollisionShape.new()
    var cyl := CapsuleShape.new()
    cyl.radius = 0.4
    cyl.height = 1.0
    shape_node.shape = cyl
    shape_node.rotation_degrees = Vector3(90, 0, 0)
    shape_node.translation = Vector3(0, 0.9, 0)
    add_child(shape_node)

    visual = Spatial.new()
    add_child(visual)

    mat = FX.make_mat(base_color)

    # Modelo 3D anime (res://bot.glb). Se não existir, usa o boneco simples colorido.
    chr = CharacterScript.new()
    visual.add_child(chr)
    var model_path: String = char_path
    var custom: bool = model_path != "" and ResourceLoader.exists(model_path)
    if not custom:
        model_path = "res://bot.glb"
        if not ResourceLoader.exists(model_path):
            model_path = "res://player.glb"   # sem bot.glb, os bots usam o mesmo modelo (com cor diferente)
    if chr.setup(model_path, MODEL_HEIGHT, MODEL_YAW, OUTLINE_WIDTH):
        if not custom:
            chr.set_tint(base_color)
    else:
        chr.queue_free()
        chr = null

        var body := MeshInstance.new()
        var cm := CylinderMesh.new()
        cm.top_radius = 0.35
        cm.bottom_radius = 0.4
        cm.height = 1.4
        cm.radial_segments = 8
        cm.rings = 1
        body.mesh = cm
        body.translation = Vector3(0, 0.7, 0)
        body.material_override = mat
        visual.add_child(body)

        var head := MeshInstance.new()
        var sm := SphereMesh.new()
        sm.radius = 0.25
        sm.height = 0.5
        sm.radial_segments = 8
        sm.rings = 4
        head.mesh = sm
        head.translation = Vector3(0, 1.6, 0)
        head.material_override = mat
        visual.add_child(head)

    var gun := MeshInstance.new()
    var gm := CubeMesh.new()
    gm.size = Vector3(0.1, 0.12, 0.7)
    gun.mesh = gm
    if chr != null:
        gun.translation = GUN_POS_MODEL
    else:
        gun.translation = Vector3(0.4, 1.3, -0.5)
    gun.material_override = FX.make_mat(Color(0.1, 0.1, 0.1))
    visual.add_child(gun)

    fire_cd = rand_range(0.5, 2.0)


func _flat(v: Vector3) -> Vector3:
    return Vector3(v.x, 0.0, v.z)


func _brain():
    if main != null:
        return main.brain
    return null


func _skill() -> float:
    var b = _brain()
    if b == null:
        return 0.4
    return b.skill()


func hear(pos: Vector3) -> void:
    if not alive or enemy_visible:
        return
    if _flat(pos - global_transform.origin).length() < 75.0 and randf() < 0.6:
        inv_pos = pos
        inv_t = 8.0


func _candidates() -> Array:
    var out: Array = []
    if target != null and target.alive and not target.in_air:
        out.append(target)
    for b in main.bots:
        if b != self and is_instance_valid(b) and b.alive:
            out.append(b)
    return out


func _los(c) -> bool:
    var o: Vector3 = global_transform.origin + Vector3(0, 1.4, 0)
    var t: Vector3 = c.global_transform.origin + Vector3(0, 1.2, 0)
    var hit: Dictionary = get_world().direct_space_state.intersect_ray(o, t, [self])
    if hit.empty() or hit["collider"] == c:
        return true
    var veh = c.get("vehicle")   # jogador dentro de um carro: o carro conta como o jogador
    return veh != null and hit["collider"] == veh


func _find_health() -> Dictionary:
    var best: Dictionary = {}
    var bd: float = 60.0
    var pos: Vector3 = global_transform.origin
    for p in main.pickups:
        if p["kind"] == "health":
            var d: float = _flat(p["node"].translation - pos).length()
            if d < bd:
                bd = d
                best = p
    return best


func _find_cover(from_enemy: Vector3) -> Vector3:
    # Procura um prédio/caixa grande por perto e vai para o lado oposto ao inimigo
    var pos: Vector3 = global_transform.origin
    var best := Vector3.ZERO
    var bd: float = 24.0
    for c in main.cover_points:
        var d: float = _flat(Vector3(c[0], 0, c[1]) - pos).length()
        if d < bd:
            var away: Vector3 = _flat(Vector3(c[0], 0, c[1]) - from_enemy).normalized()
            var spot: Vector3 = Vector3(c[0], 0, c[1]) + away * (c[2] + 1.6)
            bd = d
            best = spot
    return best


func _pick_goal() -> void:
    var c := Vector3.ZERO
    var r: float = 110.0
    if zone != null:
        c = zone.center
        r = zone.radius
    var p := Vector3.ZERO
    if randf() < 0.55:
        var reg = MapData.REGIONS[randi() % MapData.REGIONS.size()]
        p = Vector3(reg[1] + rand_range(-14.0, 14.0), 0.0, reg[2] + rand_range(-14.0, 14.0))
    else:
        var a: float = randf() * TAU
        var rr: float = sqrt(randf()) * r * 0.8
        p = c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
    var dc: Vector3 = _flat(p - c)
    if dc.length() > r * 0.85:
        p = c + dc.normalized() * r * 0.6
    var hit: Dictionary = get_world().direct_space_state.intersect_ray(Vector3(p.x, 120, p.z), Vector3(p.x, -5, p.z))
    if hit.empty() or hit["position"].y < 0.6:
        var reg2 = MapData.REGIONS[randi() % MapData.REGIONS.size()]
        p = Vector3(reg2[1], 0.0, reg2[2])
    goal = p
    goal_t = rand_range(12.0, 25.0)


# Decide o que fazer (roda ~4x por segundo, para ser leve)
func _think() -> void:
    var pos: Vector3 = global_transform.origin
    var best = null
    var bd: float = SIGHT_RANGE
    for c in _candidates():
        var d: float = _flat(c.global_transform.origin - pos).length()
        if d < bd and _los(c):
            best = c
            bd = d
    if best != null:
        if best != enemy:
            react_t = 0.25 + (1.0 - _skill()) * 0.5
            burst_left = 0
        enemy = best
        enemy_visible = true
        last_seen = best.global_transform.origin
        lose_t = 6.0
        state = "fight"
    else:
        enemy_visible = false
        if state == "fight":
            state = "chase"

    var outside: bool = zone != null and zone.active and zone.is_outside(pos)
    if outside:
        state = "zone"
        goal = zone.center
        return
    if state == "zone":
        state = "roam"
        goal_t = 0.0

    if state == "fight":
        # Vida baixa: recua para uma cobertura (e depois procura cura)
        if health < MAX_HEALTH * 0.4:
            retreat_t -= 0.3
            if retreat_t <= 0.0:
                retreat_goal = _find_cover(last_seen)
                retreat_t = 3.0
        else:
            retreat_goal = Vector3.ZERO
        return

    retreat_goal = Vector3.ZERO
    if state == "chase":
        lose_t -= 0.3
        goal = last_seen
        if lose_t <= 0.0 or _flat(goal - pos).length() < 3.0:
            state = "roam"
            goal_t = 0.0
        return

    loot_block -= 0.3
    if health < MAX_HEALTH * 0.6 and loot_block <= 0.0:
        if loot_item == null or not main.pickups.has(loot_item):
            loot_item = _find_health()
            if loot_item.empty():
                loot_item = null
        if loot_item != null:
            state = "loot"
            loot_t += 0.3
            if loot_t > 20.0:
                # não consegue chegar nesse item: desiste por um tempo
                loot_item = null
                loot_t = 0.0
                loot_block = 40.0
                state = "roam"
                return
            goal = loot_item["node"].translation
            if _flat(goal - pos).length() < 1.8:
                if main.take_pickup(loot_item):
                    health = min(health + 40.0, MAX_HEALTH)
                loot_item = null
                loot_t = 0.0
                state = "roam"
            return

    if inv_t > 0.0:
        inv_t -= 0.3
        state = "investigate"
        goal = inv_pos
        if _flat(goal - pos).length() < 5.0:
            inv_t = 0.0
        return

    state = "roam"
    goal_t -= 0.3
    if goal_t <= 0.0 or _flat(goal - pos).length() < 3.0 or goal == Vector3.ZERO:
        _pick_goal()


func _blocked(space, origin: Vector3, dir: Vector3) -> bool:
    return not space.intersect_ray(origin, origin + dir * 3.0, [self]).empty()


# Desvia de paredes e prédios com "antenas" (raios) na frente
func _avoid(dir: Vector3, delta: float) -> Vector3:
    if dir.length() < 0.1:
        return dir
    if is_on_wall() and stuck_t <= 0.0:
        stuck_t = 0.6
        var sgn: float = 1.0
        if randf() < 0.5:
            sgn = -1.0
        avoid_dir = dir.rotated(Vector3.UP, 1.3 * sgn)
        avoid_hold = 0.6
    if stuck_t > 0.0:
        stuck_t -= delta
    avoid_t -= delta
    avoid_hold -= delta
    if avoid_t <= 0.0:
        avoid_t = 0.12
        var space = get_world().direct_space_state
        var origin: Vector3 = global_transform.origin + Vector3(0, 1.0, 0)
        if _blocked(space, origin, dir):
            var chosen := Vector3.ZERO
            for ang in [0.7, -0.7, 1.4, -1.4, 2.2, -2.2]:
                var d2: Vector3 = dir.rotated(Vector3.UP, ang)
                if not _blocked(space, origin, d2):
                    chosen = d2
                    break
            if chosen == Vector3.ZERO:
                chosen = -dir
            avoid_dir = chosen
            avoid_hold = 0.5
        elif avoid_hold <= 0.0:
            avoid_dir = Vector3.ZERO
    if avoid_dir != Vector3.ZERO and avoid_hold > 0.0:
        return avoid_dir
    return dir


func _physics_process(delta: float) -> void:
    if not alive:
        return
    if main == null:
        main = get_tree().current_scene
        if main == null or not main.has_method("alert"):
            main = null
            return

    if flash_t > 0.0:
        flash_t -= delta
        if flash_t <= 0.0:
            mat.albedo_color = base_color
            if chr != null:
                chr.set_flash(0.0)

    velocity.y -= GRAVITY * delta

    think_t -= delta
    if think_t <= 0.0:
        think_t = 0.3
        _think()

    var pos: Vector3 = global_transform.origin
    var want := Vector3.ZERO
    var face := Vector3.ZERO
    var speed: float = MOVE_SPEED

    if state == "fight" and enemy != null and is_instance_valid(enemy) and enemy.alive:
        var to_e: Vector3 = _flat(enemy.global_transform.origin - pos)
        var d: float = to_e.length()
        var f: Vector3 = to_e.normalized()
        face = f
        if retreat_goal != Vector3.ZERO:
            want = _flat(retreat_goal - pos)
            if want.length() < 1.5:
                want = Vector3.ZERO
            want = want.normalized()
            speed = MOVE_SPEED * 1.15
        else:
            strafe_t -= delta
            if strafe_t <= 0.0:
                strafe = -strafe
                strafe_t = rand_range(0.7, 2.0)
            var pref: float = 15.0
            var b = _brain()
            if b != null:
                pref = b.pref_distance()
            var adv: float = 0.0
            if d > pref + 5.0:
                adv = 1.0
            elif d < pref - 5.0:
                adv = -1.0
            want = (f.cross(Vector3.UP) * strafe * 0.9 + f * adv).normalized()
            speed = MOVE_SPEED * 0.9
        # atirar
        react_t -= delta
        fire_cd -= delta
        if enemy_visible and react_t <= 0.0 and fire_cd <= 0.0:
            fire(d)
            burst_left -= 1
            if burst_left <= 0:
                burst_left = 3 + randi() % 3
                fire_cd = rand_range(0.7, 1.4) * (1.35 - _skill() * 0.6)
            else:
                fire_cd = 0.16
    else:
        var to_g: Vector3 = _flat(goal - pos)
        if to_g.length() > 2.0:
            want = to_g.normalized()
        face = want
        if state == "zone":
            speed = MOVE_SPEED * 1.25

    want = _avoid(want, delta)
    velocity.x = want.x * speed
    velocity.z = want.z * speed

    if face.length() > 0.01:
        var yaw: float = atan2(-face.x, -face.z)
        rotation.y = lerp_angle(rotation.y, yaw, 8.0 * delta)

    velocity = move_and_slide(velocity, Vector3.UP, true)

    if chr != null:
        if want.length() > 0.1:
            chr.play("run")
        else:
            chr.play("idle")


func fire(dist: float) -> void:
    if enemy == null or not is_instance_valid(enemy):
        return
    var origin: Vector3 = global_transform.origin + Vector3(0, 1.3, 0)
    var tpos: Vector3 = enemy.global_transform.origin + Vector3(0, 1.0, 0)
    var skill: float = _skill()
    # Prevê para onde o alvo vai (quanto mais treinado, melhor)
    var ev = enemy.get("velocity")
    if ev == null:
        ev = Vector3.ZERO
    tpos += Vector3(ev.x, 0.0, ev.z) * clamp(dist / 40.0, 0.0, 1.0) * 0.35 * skill
    # Aprendizado: se o jogador costuma desviar para um lado, mira um pouco para esse lado
    if enemy == target and main != null:
        var f: Vector3 = _flat(tpos - origin).normalized()
        tpos += f.cross(Vector3.UP) * main.brain.strafe_bias * 1.3 * skill
    var spread: float = (0.35 + dist * 0.035) * (1.35 - skill)
    var aim: Vector3 = tpos + Vector3(rand_range(-spread, spread), rand_range(-spread, spread), rand_range(-spread, spread))
    var to: Vector3 = origin + (aim - origin).normalized() * 75.0
    var hit: Dictionary = get_world().direct_space_state.intersect_ray(origin, to, [self])
    var end: Vector3 = to
    if not hit.empty():
        end = hit["position"]
        var c = hit["collider"]
        if c != null and c.has_method("take_damage"):
            c.take_damage(BOT_DAMAGE, self)
    FX.tracer(get_tree().current_scene, origin, end, Color(1.0, 0.45, 0.35))
    main.snd("shot", origin, -5.0, 0.8)
    main.alert(origin, self)
    if chr != null:
        chr.play_once("shoot")


func take_damage(amount: float, by = null) -> void:
    if not alive:
        return
    health -= amount
    mat.albedo_color = Color(1, 1, 1)
    if chr != null:
        chr.set_flash(0.8)
    flash_t = 0.08
    # Revida: vira para quem atirou e procura o atirador
    if by != null and by != self and by is Spatial and not enemy_visible:
        last_seen = by.global_transform.origin
        lose_t = 6.0
        state = "chase"
    if health <= 0.0:
        die(by)


func die(by) -> void:
    alive = false
    shape_node.set_deferred("disabled", true)
    if chr != null:
        chr.set_flash(0.0)
        chr.set_dark(1.0)
        if chr.has_anim("death"):
            chr.play_once("death")
        else:
            visual.rotation.x = deg2rad(90.0)
            visual.translation.y = 0.35
    else:
        visual.rotation.x = deg2rad(90.0)
        visual.translation.y = 0.35
    mat.albedo_color = base_color.darkened(0.5)
    emit_signal("bot_died", by)
    get_tree().create_timer(4.0).connect("timeout", self, "queue_free")
