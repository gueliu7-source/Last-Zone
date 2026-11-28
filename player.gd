extends KinematicBody
# Jogador em terceira pessoa (WASD + mouse).

signal died
signal landed

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
var model_path := "res://player.glb"   # o main define qual personagem antes de adicionar
var gun_node = null
var mode := "ground"        # plane (no avião) · fall (queda livre) · chute (paraquedas) · ground
var in_air := false
var plane = null
var plane_vel := Vector3.ZERO
var air_t := 0.0
var step_t := 0.0
var canopy = null
var agl := 0.0
var vehicle = null          # carro que está dirigindo (mode == "drive")
var cshape = null


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_STOP

    var cs := CollisionShape.new()
    var cyl := CapsuleShape.new()
    cyl.radius = 0.4
    cyl.height = 1.0
    cs.shape = cyl
    cs.rotation_degrees = Vector3(90, 0, 0)
    cs.translation = Vector3(0, 0.9, 0)
    add_child(cs)
    cshape = cs

    # Modelo 3D anime (res://player.glb). Se não existir, usa o boneco simples.
    chr = CharacterScript.new()
    add_child(chr)
    var ok: bool = chr.setup(model_path, MODEL_HEIGHT, MODEL_YAW, OUTLINE_WIDTH)
    if not ok and model_path != "res://player.glb":
        ok = chr.setup("res://player.glb", MODEL_HEIGHT, MODEL_YAW, OUTLINE_WIDTH)
    if not ok:
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
    gun_node = gun

    arm = SpringArm.new()
    arm.spring_length = 3.4
    arm.margin = 0.3
    arm.translation = Vector3(0.7, 1.7, 0)
    arm.add_excluded_object(get_rid())
    add_child(arm)

    cam = Camera.new()
    cam.fov = 70.0
    cam.near = 0.1
    cam.far = 170.0
    arm.add_child(cam)
    cam.make_current()


func _input(event: InputEvent) -> void:
    if not alive:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_SPACE:
        if mode == "plane":
            jump_out()
        elif mode == "fall" and air_t > 1.0:
            open_chute()
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENS)
        pitch = clamp(pitch - event.relative.y * MOUSE_SENS, -1.3, 1.2)
        arm.rotation.x = pitch


func _physics_process(delta: float) -> void:
    if not alive:
        return

    if mode == "plane":
        if plane != null:
            translation = plane.translation + Vector3(0, -4.0, 0)
        return
    if mode == "drive":
        _drive(delta)
        return
    if mode != "ground":
        _air(delta)
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

    # Passos
    if dir.length() > 0.1 and is_on_floor():
        step_t -= delta
        if step_t <= 0.0:
            _snd("step", null, -9.0, rand_range(0.9, 1.1))
            step_t = 0.27
            if spd < SPRINT_SPEED:
                step_t = 0.4
    else:
        step_t = 0.0

    if Input.is_key_pressed(KEY_R):
        start_reload()
    if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(BUTTON_LEFT):
        shoot()


func enter_vehicle(v) -> void:
    if mode != "ground" or v == null or v.wrecked or v.driver != null:
        return
    vehicle = v
    v.driver = self
    v.wake()
    mode = "drive"
    reloading = false
    if chr != null:
        chr.visible = false
    if gun_node != null:
        gun_node.visible = false
    if cshape != null:
        cshape.disabled = true
    arm.add_excluded_object(v.get_rid())
    arm.spring_length = 7.5
    arm.translation = Vector3(0, 2.4, 0)
    var main = get_tree().current_scene
    v.start_engine(main.sfx_bank.get("engine") if "sfx_bank" in main else null)
    _snd("pickup", null, -8.0, 0.7)


func leave_vehicle(forced: bool = false) -> void:
    if vehicle == null:
        return
    var v = vehicle
    var out: Vector3 = v.global_transform.origin + v.global_transform.basis.x * -2.4 + Vector3(0, 1.0, 0)
    # tenta o lado esquerdo; se estiver bloqueado usa o direito
    var space = get_world().direct_space_state
    if not space.intersect_ray(v.global_transform.origin + Vector3(0, 1.0, 0), out, [v]).empty():
        out = v.global_transform.origin + v.global_transform.basis.x * 2.4 + Vector3(0, 1.0, 0)
    v.driver = null
    v.ctrl = Vector3.ZERO
    v.stop_engine()
    vehicle = null
    mode = "ground"
    arm.remove_excluded_object(v.get_rid())
    arm.spring_length = 3.4
    arm.translation = Vector3(0.7, 1.7, 0)
    cam.fov = 70.0
    translation = out
    velocity = Vector3.ZERO
    if chr != null:
        chr.visible = true
    if gun_node != null:
        gun_node.visible = true
    if cshape != null:
        cshape.disabled = false


func _drive(delta: float) -> void:
    if vehicle == null or not is_instance_valid(vehicle):
        leave_vehicle(true)
        return
    translation = vehicle.global_transform.origin + Vector3(0, 0.3, 0)
    # a câmera volta devagar para trás do carro quando você acelera
    if abs(vehicle.speed) > 3.0 and not Input.is_key_pressed(KEY_C):
        rotation.y = lerp_angle(rotation.y, vehicle.rotation.y if vehicle.speed > 0 else vehicle.rotation.y + PI, min(delta * 1.4, 1.0))
    cam.fov = lerp(cam.fov, 70.0 + clamp(abs(vehicle.speed) / 30.0, 0.0, 1.0) * 14.0, min(delta * 3.0, 1.0))


func start_reload() -> void:
    if reloading or reserve <= 0 or ammo >= MAG_SIZE:
        return
    reloading = true
    reload_t = RELOAD_TIME
    _snd("reload", null, -4.0)


func shoot() -> void:
    if fire_cd > 0.0 or reloading:
        return
    if ammo <= 0:
        start_reload()
        return
    ammo -= 1
    fire_cd = FIRE_DELAY
    _snd("shot", null, -3.0, rand_range(0.95, 1.05))
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
            _snd("hit", null, -2.0)

    var mz := Vector3(0.4, 1.3, -0.9)
    if chr != null:
        mz = MUZZLE_MODEL
    var muzzle: Vector3 = global_transform.xform(mz)
    FX.tracer(get_tree().current_scene, muzzle, end)
    var mn = get_tree().current_scene
    if mn.has_method("alert"):
        mn.alert(muzzle, self)


func take_damage(amount: float, _by = null) -> void:
    if not alive:
        return
    health -= amount
    if _by != null:
        _snd("hurt", null, -3.0)
    if health <= 0.0:
        health = 0.0
        if vehicle != null:
            leave_vehicle(true)
        alive = false
        if chr != null:
            chr.play_once("death")
        emit_signal("died")


func heal(amount: float) -> void:
    health = min(health + amount, 100.0)


func add_ammo(n: int) -> void:
    reserve += n


# ---------------------------------------------------------------- avião e paraquedas

func _snd(name: String, pos = null, db: float = 0.0, pitch: float = 1.0) -> void:
    var m = get_tree().current_scene
    if m != null and m.has_method("snd"):
        m.snd(name, pos, db, pitch)


func begin_flight(plane_node, vel: Vector3, yaw: float) -> void:
    mode = "plane"
    in_air = true
    plane = plane_node
    plane_vel = vel
    visible = false
    rotation.y = yaw
    pitch = -0.55
    arm.rotation.x = pitch
    translation = plane.translation + Vector3(0, -4.0, 0)
    if gun_node != null:
        gun_node.visible = false


func jump_out() -> void:
    if mode != "plane":
        return
    mode = "fall"
    visible = true
    velocity = Vector3(plane_vel.x, 0.0, plane_vel.z) * 0.6
    air_t = 0.0
    if chr != null:
        chr.rotation_degrees = Vector3(-80, 0, 0)


func open_chute() -> void:
    if mode != "fall":
        return
    mode = "chute"
    if chr != null:
        chr.rotation_degrees = Vector3.ZERO
    _make_canopy()
    _snd("chute", null, -2.0)


func _make_canopy() -> void:
    canopy = Spatial.new()
    add_child(canopy)
    var dome := MeshInstance.new()
    var sm := SphereMesh.new()
    sm.radius = 2.4
    sm.height = 4.8
    sm.radial_segments = 10
    sm.rings = 4
    dome.mesh = sm
    dome.scale = Vector3(1.0, 0.5, 1.0)
    dome.translation = Vector3(0, 3.7, 0)
    var cmat := FX.make_mat(Color(0.95, 0.45, 0.1), true)
    cmat.params_cull_mode = SpatialMaterial.CULL_DISABLED
    dome.material_override = cmat
    dome.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
    canopy.add_child(dome)
    var lmat = FX.make_mat(Color(0.9, 0.9, 0.9), true)
    var base := Vector3(0, 1.5, 0)
    for k in range(4):
        var a: float = TAU * float(k) / 4.0 + 0.78
        var top := Vector3(cos(a) * 2.0, 3.6, sin(a) * 2.0)
        var mid: Vector3 = (top + base) * 0.5
        var ln := MeshInstance.new()
        var cm := CubeMesh.new()
        cm.size = Vector3(0.03, 0.03, top.distance_to(base))
        ln.mesh = cm
        ln.material_override = lmat
        ln.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
        ln.transform = Transform(Basis(), mid).looking_at(top, Vector3.UP)
        canopy.add_child(ln)


func _air(delta: float) -> void:
    air_t += delta
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

    if mode == "fall":
        velocity.y = max(velocity.y - 20.0 * delta, -42.0)
        velocity.x = lerp(velocity.x, dir.x * 18.0, 1.5 * delta)
        velocity.z = lerp(velocity.z, dir.z * 18.0, 1.5 * delta)
        var hit: Dictionary = get_world().direct_space_state.intersect_ray(translation, translation + Vector3(0, -700, 0), [self])
        if not hit.empty():
            agl = translation.y - hit["position"].y
            if agl < 55.0:
                open_chute()
    else:
        velocity.y = lerp(velocity.y, -7.0, 3.0 * delta)
        velocity.x = lerp(velocity.x, dir.x * 11.0, 3.0 * delta)
        velocity.z = lerp(velocity.z, dir.z * 11.0, 3.0 * delta)

    if chr != null:
        chr.play("idle")
    velocity = move_and_slide(velocity, Vector3.UP)
    if is_on_floor():
        _land()


func _land() -> void:
    mode = "ground"
    in_air = false
    velocity = Vector3.ZERO
    if chr != null:
        chr.rotation_degrees = Vector3.ZERO
    if canopy != null:
        canopy.queue_free()
        canopy = null
    if gun_node != null:
        gun_node.visible = true
    _snd("land", null, -2.0)
    emit_signal("landed")


# Troca a aparência (usado na tela inicial)
func set_character(path: String) -> void:
    if chr == null:
        return
    chr.queue_free()
    chr = CharacterScript.new()
    add_child(chr)
    if not chr.setup(path, MODEL_HEIGHT, MODEL_YAW, OUTLINE_WIDTH):
        chr.setup("res://player.glb", MODEL_HEIGHT, MODEL_YAW, OUTLINE_WIDTH)
