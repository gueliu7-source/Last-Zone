extends KinematicBody
# Inimigo com IA simples: vagueia, foge da zona e ataca o jogador.

signal bot_died(killer)

const FX = preload("res://fx.gd")
const CharacterScript = preload("res://character.gd")

# Mesmos ajustes do jogador (veja player.gd)
const MODEL_HEIGHT := 1.75
const MODEL_YAW := 180.0
const OUTLINE_WIDTH := 0.02
const GUN_POS_MODEL := Vector3(-0.06, 1.23, -0.30)

const MOVE_SPEED := 4.5
const GRAVITY := 22.0
const SIGHT_RANGE := 45.0
const BOT_DAMAGE := 10.0

var health := 80.0
var alive := true
var target = null   # o jogador (definido pelo main)
var zone = null     # a zona (definida pelo main)

var velocity := Vector3.ZERO
var wander_dir := Vector3.ZERO
var wander_t := 0.0
var shoot_cd := 1.0
var stuck_t := 0.0
var stuck_dir := Vector3.ZERO
var flash_t := 0.0

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
    var cyl := CylinderShape.new()
    cyl.radius = 0.4
    cyl.height = 1.8
    shape_node.shape = cyl
    shape_node.translation = Vector3(0, 0.9, 0)
    add_child(shape_node)

    visual = Spatial.new()
    add_child(visual)

    mat = FX.make_mat(base_color)

    # Modelo 3D anime (res://bot.glb). Se não existir, usa o boneco simples colorido.
    chr = CharacterScript.new()
    visual.add_child(chr)
    var model_path := "res://bot.glb"
    if not ResourceLoader.exists(model_path):
        model_path = "res://player.glb"   # sem bot.glb, os bots usam o mesmo modelo (com cor diferente)
    if chr.setup(model_path, MODEL_HEIGHT, MODEL_YAW, OUTLINE_WIDTH):
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

    shoot_cd = rand_range(0.5, 2.0)


func _physics_process(delta: float) -> void:
    if not alive:
        return

    if flash_t > 0.0:
        flash_t -= delta
        if flash_t <= 0.0:
            mat.albedo_color = base_color
            if chr != null:
                chr.set_flash(0.0)

    velocity.y -= GRAVITY * delta

    var move_dir := Vector3.ZERO
    var face_dir := Vector3.ZERO
    var dist: float = 9999.0
    var to_player := Vector3.ZERO
    if target != null and target.alive:
        to_player = target.global_transform.origin - global_transform.origin
        to_player.y = 0.0
        dist = to_player.length()

    var outside: bool = zone != null and zone.is_outside(global_transform.origin)

    if outside:
        var back: Vector3 = zone.center - global_transform.origin
        back.y = 0.0
        move_dir = back.normalized()
        face_dir = move_dir
    elif dist < SIGHT_RANGE:
        face_dir = to_player.normalized()
        if dist > 14.0:
            move_dir = face_dir
        elif dist < 8.0:
            move_dir = -face_dir
        shoot_cd -= delta
        if shoot_cd <= 0.0:
            fire(dist)
            shoot_cd = rand_range(0.5, 1.1)
    else:
        wander_t -= delta
        if wander_t <= 0.0:
            var ang: float = randf() * TAU
            wander_dir = Vector3(cos(ang), 0.0, sin(ang))
            wander_t = rand_range(2.0, 5.0)
        move_dir = wander_dir
        face_dir = move_dir

    # Desvia de paredes e construções
    if is_on_wall() and stuck_t <= 0.0:
        stuck_t = 1.0
        var side: float = 1.0
        if randf() < 0.5:
            side = -1.0
        stuck_dir = Vector3(-move_dir.z, 0.0, move_dir.x) * side
        wander_t = 0.0
    if stuck_t > 0.0:
        stuck_t -= delta
        move_dir = stuck_dir

    velocity.x = move_dir.x * MOVE_SPEED
    velocity.z = move_dir.z * MOVE_SPEED

    if face_dir.length() > 0.01:
        var yaw: float = atan2(-face_dir.x, -face_dir.z)
        rotation.y = lerp_angle(rotation.y, yaw, 8.0 * delta)

    velocity = move_and_slide(velocity, Vector3.UP, true)

    if chr != null:
        if move_dir.length() > 0.1:
            chr.play("run")
        else:
            chr.play("idle")


func fire(dist: float) -> void:
    var origin: Vector3 = global_transform.origin + Vector3(0, 1.3, 0)
    var tpos: Vector3 = target.global_transform.origin + Vector3(0, 1.0, 0)
    var spread: float = 0.5 + dist * 0.04
    var aim: Vector3 = tpos + Vector3(rand_range(-spread, spread), rand_range(-spread, spread), rand_range(-spread, spread))
    var to: Vector3 = origin + (aim - origin).normalized() * 70.0
    var hit: Dictionary = get_world().direct_space_state.intersect_ray(origin, to, [self])
    var end: Vector3 = to
    if not hit.empty():
        end = hit["position"]
        if hit["collider"] == target:
            target.take_damage(BOT_DAMAGE, self)
    FX.tracer(get_tree().current_scene, origin, end, Color(1.0, 0.45, 0.35))
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
