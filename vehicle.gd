extends KinematicBody
# Carro dirigível (movimento arcade, leve para PCs fracos).
# Frente do carro = -Z (padrão do Godot). Se existir res://car.glb ele é usado no lugar do carro simples.

const FX = preload("res://fx.gd")
const MapData = preload("res://map_data.gd")

const GRAVITY := 24.0
const MAX_HP := 300.0
const ACCEL := 15.0
const BRAKE := 26.0
const MAX_FWD_ROAD := 30.0      # m/s (~108 km/h) no asfalto e na terra
const MAX_FWD_OFF := 17.0       # no mato e na areia
const MAX_REV := 9.0
const CAR_LENGTH := 4.4

const COLORS := [Color(0.8, 0.2, 0.2), Color(0.2, 0.4, 0.8), Color(0.9, 0.85, 0.25), Color(0.85, 0.85, 0.88), Color(0.25, 0.25, 0.28), Color(0.3, 0.6, 0.35)]

var hp := MAX_HP
var driver = null
var wrecked := false
var vel := Vector3.ZERO
var speed := 0.0             # velocidade para frente (m/s, negativa = ré)
var ctrl := Vector3.ZERO     # x = acelerador (-1..1), y = direção (-1 esquerda .. 1 direita), z = freio de mão (0/1)
var manual_test := false
var body_vis: Spatial        # parte visual (inclina com o terreno)
var engine_snd = null
var hit_cd := {}
var on_road := false
var smoke_t := 0.0


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_STOP
    var cs := CollisionShape.new()
    var box := BoxShape.new()
    box.extents = Vector3(0.95, 0.62, 2.05)
    cs.shape = box
    cs.translation = Vector3(0, 0.78, 0)
    add_child(cs)
    add_to_group("vehicles")

    body_vis = Spatial.new()
    add_child(body_vis)
    var col: Color = COLORS[randi() % COLORS.size()]
    if not _load_model():
        _build_simple(col)


func _load_model() -> bool:
    if not ResourceLoader.exists("res://car.glb"):
        return false
    var scn = load("res://car.glb")
    if scn == null:
        return false
    var inst = scn.instance()
    var holder := Spatial.new()
    body_vis.add_child(holder)
    holder.add_child(inst)
    var aabb := _aabb_of(inst, Transform.IDENTITY)
    if aabb.size.x < 0.01 or aabb.size.z < 0.01:
        holder.queue_free()
        return false
    var longest: float = max(aabb.size.x, aabb.size.z)
    var sc: float = CAR_LENGTH / longest
    holder.scale = Vector3(sc, sc, sc)
    holder.rotation_degrees = Vector3(0, 180 if aabb.size.z >= aabb.size.x else 90, 0)   # modelo olha para +Z
    var c: Vector3 = aabb.position + aabb.size / 2.0
    var off := Vector3(-c.x, -aabb.position.y, -c.z)
    inst.translation = off
    return true


func _aabb_of(n: Node, xf: Transform) -> AABB:
    var out := AABB()
    var first := true
    var stack: Array = [[n, xf]]
    while not stack.empty():
        var it = stack.pop_back()
        var node = it[0]
        var t: Transform = it[1]
        if node is Spatial and node != n:
            t = t * node.transform
        if node is MeshInstance and node.mesh != null:
            var a: AABB = t.xform(node.mesh.get_aabb())
            if first:
                out = a
                first = false
            else:
                out = out.merge(a)
        for c in node.get_children():
            stack.append([c, t])
    return out


func _box(parent: Spatial, size: Vector3, pos: Vector3, color: Color, unshaded: bool = false) -> void:
    var mi := MeshInstance.new()
    var cm := CubeMesh.new()
    cm.size = size
    mi.mesh = cm
    mi.material_override = FX.make_mat(color, unshaded)
    mi.translation = pos
    parent.add_child(mi)


func _build_simple(col: Color) -> void:
    var dark := col * 0.55
    dark.a = 1.0
    _box(body_vis, Vector3(1.9, 0.62, 4.3), Vector3(0, 0.72, 0), col)
    _box(body_vis, Vector3(1.75, 0.5, 2.1), Vector3(0, 1.28, 0.25), Color(0.14, 0.2, 0.3))
    _box(body_vis, Vector3(1.6, 0.06, 1.9), Vector3(0, 1.55, 0.25), col * 0.9)
    _box(body_vis, Vector3(1.92, 0.22, 0.3), Vector3(0, 0.5, -2.1), dark)
    _box(body_vis, Vector3(1.92, 0.22, 0.3), Vector3(0, 0.5, 2.1), dark)
    _box(body_vis, Vector3(0.38, 0.16, 0.06), Vector3(-0.6, 0.85, -2.17), Color(1.0, 0.95, 0.7), true)
    _box(body_vis, Vector3(0.38, 0.16, 0.06), Vector3(0.6, 0.85, -2.17), Color(1.0, 0.95, 0.7), true)
    _box(body_vis, Vector3(0.38, 0.14, 0.06), Vector3(-0.6, 0.85, 2.17), Color(0.9, 0.1, 0.1), true)
    _box(body_vis, Vector3(0.38, 0.14, 0.06), Vector3(0.6, 0.85, 2.17), Color(0.9, 0.1, 0.1), true)
    var wm := FX.make_mat(Color(0.08, 0.08, 0.09))
    for sx in [-1, 1]:
        for sz in [-1, 1]:
            var w := MeshInstance.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 0.37
            cyl.bottom_radius = 0.37
            cyl.height = 0.3
            cyl.radial_segments = 10
            cyl.rings = 1
            w.mesh = cyl
            w.material_override = wm
            w.rotation_degrees = Vector3(0, 0, 90)
            w.translation = Vector3(sx * 0.93, 0.37, sz * 1.4)
            body_vis.add_child(w)


func _road_dist(x: float, z: float) -> float:
    var best := 999.0
    for s in MapData.ROAD_SEGS:
        var ax: float = s[0]
        var az: float = s[1]
        var dx: float = s[2] - ax
        var dz: float = s[3] - az
        var l2: float = dx * dx + dz * dz
        var t := 0.0
        if l2 > 0.0001:
            t = clamp(((x - ax) * dx + (z - az) * dz) / l2, 0.0, 1.0)
        var px: float = ax + dx * t - x
        var pz: float = az + dz * t - z
        var d: float = sqrt(px * px + pz * pz) - s[4]
        if d < best:
            best = d
    return best


func _ground_normal() -> Vector3:
    # 4 raios nos cantos para inclinar a parte visual junto com o terreno
    var space = get_world().direct_space_state
    var gp: Vector3 = global_transform.origin
    var ys := []
    var pts := [Vector3(-0.9, 0, -1.7), Vector3(0.9, 0, -1.7), Vector3(-0.9, 0, 1.7), Vector3(0.9, 0, 1.7)]
    for p in pts:
        var o: Vector3 = global_transform.xform(p) + Vector3(0, 1.2, 0)
        var h: Dictionary = space.intersect_ray(o, o + Vector3(0, -3.5, 0), [self])
        if h.empty():
            ys.append(gp.y)
        else:
            ys.append(h["position"].y)
    var fwd_slope: float = ((ys[0] + ys[1]) - (ys[2] + ys[3])) / 2.0 / 3.4     # + = frente mais alta
    var side_slope: float = ((ys[1] + ys[3]) - (ys[0] + ys[2])) / 2.0 / 1.8    # + = direita mais alta
    return Vector3(fwd_slope, side_slope, 0.0)


func _physics_process(delta: float) -> void:
    for k in hit_cd.keys():
        hit_cd[k] -= delta
        if hit_cd[k] <= 0.0:
            hit_cd.erase(k)

    var th := 0.0
    var st := 0.0
    var hb := 0.0
    if driver != null and not wrecked:
        if not manual_test:
            th = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
            st = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
            hb = 1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0
            ctrl = Vector3(th, st, hb)
        else:
            th = ctrl.x
            st = ctrl.y
            hb = ctrl.z

    var gp: Vector3 = global_transform.origin
    var fwd: Vector3 = -global_transform.basis.z
    var right: Vector3 = global_transform.basis.x

    on_road = _road_dist(gp.x, gp.z) < 1.0
    var vmax: float = MAX_FWD_ROAD if on_road else MAX_FWD_OFF

    # aceleração / freio / arrasto
    if th > 0.1:
        if speed < -0.5:
            speed += BRAKE * delta
        elif speed < vmax:
            speed += ACCEL * delta * (1.0 - clamp(speed / vmax, 0.0, 1.0) * 0.75)
    elif th < -0.1:
        if speed > 0.5:
            speed -= BRAKE * delta
        elif speed > -MAX_REV:
            speed -= ACCEL * 0.6 * delta
    else:
        speed = move_toward(speed, 0.0, (3.5 + abs(speed) * 0.12) * delta)
    if hb > 0.5:
        speed = move_toward(speed, 0.0, 14.0 * delta)
    if speed > vmax:
        speed = move_toward(speed, vmax, 12.0 * delta)

    # direção: gira mais com velocidade média, menos em alta
    var turn_gain: float = clamp(abs(speed) / 5.0, 0.0, 1.0) * (1.0 - clamp(abs(speed) / 70.0, 0.0, 0.5))
    var rate: float = 1.7 * turn_gain * sign(speed)
    if hb > 0.5:
        rate *= 1.35
    rotate_y(-st * rate * delta)

    # aderência: velocidade lateral some rápido (menos com freio de mão = derrapa)
    fwd = -global_transform.basis.z
    right = global_transform.basis.x
    var vf: float = vel.dot(fwd)
    var vl: float = vel.dot(right)
    var grip: float = 9.0
    if hb > 0.5:
        grip = 1.6
    vl = move_toward(vl, 0.0, grip * abs(vl) * delta + 0.5 * delta)
    # a velocidade para frente segue o "speed" calculado
    vf = speed
    var vy: float = vel.y - GRAVITY * delta
    vel = fwd * vf + right * vl
    vel.y = vy
    vel = move_and_slide(vel, Vector3.UP, true, 4, 0.8)
    speed = vel.dot(-global_transform.basis.z)

    # atropela quem estiver na frente (bots)
    if abs(speed) > 5.0:
        for i in range(get_slide_count()):
            var c = get_slide_collision(i).collider
            if c != null and c != driver and c.has_method("take_damage") and not hit_cd.has(c.get_instance_id()):
                hit_cd[c.get_instance_id()] = 0.6
                var dmg: float = abs(speed) * 6.0
                c.take_damage(dmg, driver)
                if driver != null:
                    var main = get_tree().current_scene
                    if main.has_method("snd"):
                        main.snd("hit", null, -2.0)

    # visual: inclina com o terreno (suavizado)
    var sl: Vector3 = _ground_normal()
    var tx: float = clamp(atan(sl.x), -0.5, 0.5)
    var tz: float = clamp(-atan(sl.y), -0.4, 0.4)
    body_vis.rotation.x = lerp(body_vis.rotation.x, tx, min(delta * 6.0, 1.0))
    body_vis.rotation.z = lerp(body_vis.rotation.z, tz - st * speed * 0.004, min(delta * 6.0, 1.0))

    # som do motor
    if engine_snd != null:
        engine_snd.pitch_scale = 0.55 + clamp(abs(speed) / vmax, 0.0, 1.3) * 1.1
        engine_snd.unit_db = -2.0 + min(abs(th), 1.0) * 3.0

    # fumaça quando a vida está baixa
    if wrecked or (hp < MAX_HP * 0.35 and driver != null):
        smoke_t -= delta
        if smoke_t <= 0.0:
            smoke_t = 0.12
            _puff()


func _puff() -> void:
    var mi := MeshInstance.new()
    var sm := SphereMesh.new()
    sm.radius = 0.35
    sm.height = 0.7
    sm.radial_segments = 6
    sm.rings = 3
    mi.mesh = sm
    mi.material_override = FX.make_mat(Color(0.18, 0.18, 0.18, 1.0), true)
    mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
    get_tree().current_scene.add_child(mi)
    mi.translation = global_transform.xform(Vector3(0, 1.3, -1.8))
    var tw := Tween.new()
    mi.add_child(tw)
    tw.interpolate_property(mi, "translation", mi.translation, mi.translation + Vector3(0, 2.5, 0), 0.9, Tween.TRANS_LINEAR, Tween.EASE_IN)
    tw.interpolate_property(mi, "scale", Vector3(1, 1, 1), Vector3(2.4, 2.4, 2.4), 0.9, Tween.TRANS_LINEAR, Tween.EASE_IN)
    tw.start()
    get_tree().create_timer(0.9).connect("timeout", mi, "queue_free")


func start_engine(stream) -> void:
    if engine_snd == null and stream != null:
        engine_snd = AudioStreamPlayer3D.new()
        engine_snd.stream = stream
        engine_snd.unit_size = 14.0
        engine_snd.max_distance = 120.0
        engine_snd.unit_db = -2.0
        add_child(engine_snd)
        engine_snd.play()


func stop_engine() -> void:
    if engine_snd != null:
        engine_snd.queue_free()
        engine_snd = null


# Balas e atropelamentos: o carro absorve parte do dano e passa o resto para quem dirige.
func take_damage(amount: float, by = null) -> void:
    if wrecked:
        return
    hp -= amount
    if driver != null and by != null:
        driver.take_damage(amount * 0.4, by)
    if hp <= 0.0:
        _wreck()


func _wreck() -> void:
    wrecked = true
    hp = 0.0
    _darken(body_vis)
    var main = get_tree().current_scene
    if main.has_method("snd"):
        main.snd("zone", global_transform.origin, 2.0, 1.4)
        main.snd("hit", global_transform.origin, 4.0, 0.5)
    if driver != null:
        var d = driver
        d.leave_vehicle(true)
        d.take_damage(35.0, self)
    stop_engine()


func _darken(n: Node) -> void:
    if n is MeshInstance:
        n.material_override = FX.make_mat(Color(0.07, 0.07, 0.07))
    for c in n.get_children():
        _darken(c)
