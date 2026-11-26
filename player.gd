extends KinematicBody
# Jogador em terceira pessoa (WASD + mouse).

signal died

const FX = preload("res://fx.gd")
const CharacterScript = preload("res://character.gd")

# Ajustes do modelo 3D (mude aqui se o modelo da outra IA vier torto ou do tamanho errado)
const MODEL_HEIGHT := 1.75     # altura do personagem em metros
const MODEL_YAW := 180.0       # 180 = modelo olhando para +Z (padrão glTF); use 0 se ele ficar de costas
const OUTLINE_WIDTH := 0.02    # espessura do contorno preto (metros)
const GUN_POS_MODEL := Vector3(-0.06, 1.23, -0.30)   # arma entre as mãos do modelo Kael (espaço do jogador)
const MUZZLE_MODEL := Vector3(-0.06, 1.23, -0.68)    # ponta do cano (de onde sai o rastro da bala)

const SPEED := 7.0
const SPRINT_SPEED := 11.0
const JUMP_VELOCITY := 7.0
const GRAVITY := 22.0
const MOUSE_SENS := 0.0025
const MAG_SIZE := 30
const DAMAGE := 20.0
const FIRE_DELAY := 0.14
const RELOAD_TIME := 1.6

var health := 100.0
var ammo := 30
var reserve := 90
var alive := true
var reloading := false
var reload_t := 0.0
var fire_cd := 0.0
var pitch := 0.0
var velocity := Vector3.ZERO
var arm
var cam
var chr = null


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_STOP

    var cs := CollisionShape.new()
    var cyl := CylinderShape.new()
    cyl.radius = 0.4
    cyl.height = 1.8
    cs.shape = cyl
    cs.translation = Vector3(0, 0.9, 0)
    add_child(cs)

    # Modelo 3D anime (res://player.glb). Se não existir, usa o boneco simples.
    chr = CharacterScript.new()
    add_child(chr)
    if not chr.setup("res://player.glb", MODEL_HEIGHT, MODEL_YAW, OUTLINE_WIDTH):
        chr.queue_free()
        chr = null
        var mat = FX.make_mat(Color(0.2, 0.45, 0.95))

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
        add_child(body)

        var head := MeshInstance.new()
        var sm := SphereMesh.new()
        sm.radius = 0.25
        sm.height = 0.5
        sm.radial_segments = 8
        sm.rings = 4
        head.mesh = sm
        head.translation = Vector3(0, 1.6, 0)
        head.material_override = mat
        add_child(head)

    var gun := MeshInstance.new()
    var gm := CubeMesh.new()
    gm.size = Vector3(0.1, 0.12, 0.7)
    gun.mesh = gm
    if chr != null:
        gun.translation = GUN_POS_MODEL
    else:
        gun.translation = Vector3(0.4, 1.3, -0.5)
    gun.material_override = FX.make_mat(Color(0.1, 0.1, 0.1))
    add_child(gun)

    arm = SpringArm.new()
    arm.spring_length = 3.4
    arm.margin = 0.3
    arm.translation = Vector3(0.7, 1.7, 0)
    arm.add_excluded_object(get_rid())
    add_child(arm)

    cam = Camera.new()
    cam.fov = 70.0
    cam.near = 0.1
    cam.far = 130.0
    arm.add_child(cam)
    cam.make_current()


func _input(event: InputEvent) -> void:
    if not alive:
        return
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENS)
        pitch = clamp(pitch - event.relative.y * MOUSE_SENS, -1.3, 1.2)
        arm.rotation.x = pitch


func _physics_process(delta: float) -> void:
    if not alive:
        return

    fire_cd = max(fire_cd - delta, 0.0)

    if reloading:
        reload_t -= delta
        if reload_t <= 0.0:
            var need: int = MAG_SIZE - ammo
            var take: int = int(min(need, reserve))
            ammo += take
            reserve -= take
            reloading = false

    velocity.y -= GRAVITY * delta
    if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
        velocity.y = JUMP_VELOCITY

    var dir := Vector3.ZERO
    var fwd: Vector3 = -global_transform.basis.z
    var right: Vector3 = global_transform.basis.x
    if Input.is_key_pressed(KEY_W):
        dir += fwd
    if Input.is_key_pressed(KEY_S):
        dir -= fwd
    if Input.is_key_pressed(KEY_D):
        dir += right
    if Input.is_key_pressed(KEY_A):
        dir -= right
    dir.y = 0.0
    dir = dir.normalized()

    var spd: float = SPEED
    if Input.is_key_pressed(KEY_SHIFT):
        spd = SPRINT_SPEED
    velocity.x = dir.x * spd
    velocity.z = dir.z * spd
    velocity = move_and_slide(velocity, Vector3.UP, true)

    if chr != null:
        if dir.length() > 0.1:
            chr.play("run")
        else:
            chr.play("idle")

    if Input.is_key_pressed(KEY_R):
        start_reload()
    if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(BUTTON_LEFT):
        shoot()


func start_reload() -> void:
    if reloading or reserve <= 0 or ammo >= MAG_SIZE:
        return
    reloading = true
    reload_t = RELOAD_TIME


func shoot() -> void:
    if fire_cd > 0.0 or reloading:
        return
    if ammo <= 0:
        start_reload()
        return
    ammo -= 1
    fire_cd = FIRE_DELAY
    if chr != null:
        chr.play_once("shoot")

    var from: Vector3 = cam.global_transform.origin
    var dir: Vector3 = -cam.global_transform.basis.z
    var to: Vector3 = from + dir * 120.0
    var hit: Dictionary = get_world().direct_space_state.intersect_ray(from, to, [self])
    var end: Vector3 = to
    if not hit.empty():
        end = hit["position"]
        var c = hit["collider"]
        if c != null and c.has_method("take_damage"):
            c.take_damage(DAMAGE, self)

    var mz := Vector3(0.4, 1.3, -0.9)
    if chr != null:
        mz = MUZZLE_MODEL
    var muzzle: Vector3 = global_transform.xform(mz)
    FX.tracer(get_tree().current_scene, muzzle, end)


func take_damage(amount: float, _by = null) -> void:
    if not alive:
        return
    health -= amount
    if health <= 0.0:
        health = 0.0
        alive = false
        if chr != null:
            chr.play_once("death")
        emit_signal("died")


func heal(amount: float) -> void:
    health = min(health + amount, 100.0)


func add_ammo(n: int) -> void:
    reserve += n
