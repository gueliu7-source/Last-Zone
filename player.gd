extends KinematicBody
# Jogador em terceira pessoa (WASD + mouse) com suporte ao modelo otimizado Kael (.obj + .jpg)
# e poses procedurais (respiracao, corrida, pulo, recuo ao atirar, recarga e queda ao morrer).

signal died

const FX = preload("res://fx.gd")
const CharacterScript = preload("res://character.gd")
const CEL_SHADER = preload("res://cel.shader")
const OUTLINE_SHADER = preload("res://outline.shader")

const MODEL_HEIGHT := 1.75
const MODEL_YAW := 180.0
const OUTLINE_WIDTH := 0.02
const GUN_POS_MODEL := Vector3(-0.06, 1.23, -0.30)
const MUZZLE_MODEL := Vector3(-0.06, 1.23, -0.68)

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
var kael_pivot: Spatial = null
var gun_node: MeshInstance = null
var pose_time := 0.0
var recoil_t := 0.0
var death_t := 0.0


func _ready() -> void:
    pause_mode = Node.PAUSE_MODE_STOP

    var cs := CollisionShape.new()
    var cyl := CylinderShape.new()
    cyl.radius = 0.4
    cyl.height = 1.8
    cs.shape = cyl
    cs.translation = Vector3(0, 0.9, 0)
    add_child(cs)

    if not _setup_kael_obj("res://kael.obj", "res://kael_albedo.jpg"):
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

    gun_node = MeshInstance.new()
    var gm := CubeMesh.new()
    gm.size = Vector3(0.1, 0.12, 0.7)
    gun_node.mesh = gm
    if kael_pivot != null or chr != null:
        gun_node.translation = GUN_POS_MODEL
    else:
        gun_node.translation = Vector3(0.4, 1.3, -0.5)
    gun_node.material_override = FX.make_mat(Color(0.1, 0.1, 0.1))
    add_child(gun_node)

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


func _setup_kael_obj(obj_path: String, tex_path: String) -> bool:
    var f := File.new()
    if not f.file_exists(obj_path):
        return false
    if f.open(obj_path, File.READ) != OK:
        return false

    var verts: Array = []
    var uvs: Array = []
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var min_y := 1e9
    var max_y := -1e9
    var face_count := 0

    while not f.eof_reached():
        var line: String = f.get_line().strip_edges()
        if line.begins_with("v "):
            var p: PoolStringArray = line.split(" ", false)
            if p.size() >= 4:
                var vx := float(p[1])
                var vy := float(p[2])
                var vz := float(p[3])
                verts.append(Vector3(vx, vy, vz))
                if vy < min_y:
                    min_y = vy
                if vy > max_y:
                    max_y = vy
        elif line.begins_with("vt "):
            var p: PoolStringArray = line.split(" ", false)
            if p.size() >= 3:
                uvs.append(Vector2(float(p[1]), 1.0 - float(p[2])))
        elif line.begins_with("f "):
            var p: PoolStringArray = line.split(" ", false)
            if p.size() >= 4:
                var tri_idx := []
                for i in range(1, p.size()):
                    var parts: PoolStringArray = p[i].split("/")
                    var vi := int(parts[0]) - 1
                    var ti := -1
                    if parts.size() >= 2 and parts[1] != "":
                        ti = int(parts[1]) - 1
                    tri_idx.append([vi, ti])
                for i in range(1, tri_idx.size() - 1):
                    var corner_list := [tri_idx[0], tri_idx[i], tri_idx[i + 1]]
                    for c in corner_list:
                        var vi: int = c[0]
                        var ti: int = c[1]
                        if vi >= 0 and vi < verts.size():
                            if ti >= 0 and ti < uvs.size():
                                st.add_uv(uvs[ti])
                            st.add_vertex(verts[vi])
                    face_count += 1
    f.close()

    if face_count == 0 or max_y <= min_y:
        return false

    st.generate_normals()
    var mesh: ArrayMesh = st.commit()

    var s: float = MODEL_HEIGHT / (max_y - min_y)
    var foot_y: float = -min_y * s

    kael_pivot = Spatial.new()
    add_child(kael_pivot)

    var mi := MeshInstance.new()
    mi.mesh = mesh
    mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
    mi.rotation_degrees = Vector3(0.0, MODEL_YAW, 0.0)
    mi.scale = Vector3(s, s, s)
    mi.translation = Vector3(0.0, foot_y, 0.0)

    var cel := ShaderMaterial.new()
    cel.shader = CEL_SHADER
    cel.set_shader_param("tint", Color(1.0, 1.0, 1.0, 1.0))

    var tf := File.new()
    if tf.file_exists(tex_path) and tf.open(tex_path, File.READ) == OK:
        var bytes: PoolByteArray = tf.get_buffer(tf.get_len())
        tf.close()
        var img := Image.new()
        if img.load_jpg_from_buffer(bytes) == OK:
            var tex := ImageTexture.new()
            tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
            cel.set_shader_param("albedo_tex", tex)

    var ol := ShaderMaterial.new()
    ol.shader = OUTLINE_SHADER
    ol.set_shader_param("width", OUTLINE_WIDTH / s)
    cel.next_pass = ol

    mi.material_override = cel
    kael_pivot.add_child(mi)
    return true


func _input(event: InputEvent) -> void:
    if not alive:
        return
    if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENS)
        pitch = clamp(pitch - event.relative.y * MOUSE_SENS, -1.3, 1.2)
        arm.rotation.x = pitch


func _physics_process(delta: float) -> void:
    if not alive:
        _update_kael_pose(delta, 0.0, false)
        return

    fire_cd = max(fire_cd - delta, 0.0)
    recoil_t = max(recoil_t - delta, 0.0)

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

    var sprinting := Input.is_key_pressed(KEY_SHIFT)
    var spd: float = SPRINT_SPEED if sprinting else SPEED
    velocity.x = dir.x * spd
    velocity.z = dir.z * spd
    velocity = move_and_slide(velocity, Vector3.UP, true)

    _update_kael_pose(delta, dir.length(), sprinting)

    if chr != null:
        if dir.length() > 0.1:
            chr.play("run")
        else:
            chr.play("idle")

    if Input.is_key_pressed(KEY_R):
        start_reload()
    if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(BUTTON_LEFT):
        shoot()


func _update_kael_pose(delta: float, move_amt: float, sprinting: bool) -> void:
    if kael_pivot == null:
        return

    if not alive:
        death_t = min(death_t + delta * 3.2, 1.0)
        kael_pivot.rotation_degrees = Vector3(-88.0 * death_t, 0.0, 12.0 * death_t)
        kael_pivot.translation = Vector3(0.0, 0.15 * death_t, 0.0)
        kael_pivot.scale = Vector3.ONE
        return

    var target_pos := Vector3.ZERO
    var target_rot := Vector3.ZERO
    var target_scale := Vector3.ONE

    if not is_on_floor():
        pose_time += delta * 4.0
        target_rot.x = clamp(velocity.y * 1.4, -10.0, 10.0)
        target_scale = Vector3(0.96, 1.05, 0.96)
    elif move_amt > 0.1:
        var freq := 13.5 if sprinting else 9.5
        pose_time += delta * freq
        var bob := abs(sin(pose_time)) * (0.09 if sprinting else 0.055)
        var sway := sin(pose_time) * (5.5 if sprinting else 3.2)
        target_pos.y = bob
        target_rot.x = -9.0 if sprinting else -5.0
        target_rot.z = sway
        target_rot.y = cos(pose_time) * 3.0
    else:
        pose_time += delta * 2.2
        var breath := sin(pose_time)
        target_scale = Vector3(1.0 + breath * 0.012, 1.0 - breath * 0.01, 1.0 + breath * 0.012)
        target_pos.y = breath * 0.012

    if reloading:
        var reload_wave := sin((1.0 - reload_t / RELOAD_TIME) * PI)
        target_rot.x -= 12.0 * reload_wave
        target_rot.z -= 8.0 * reload_wave

    if recoil_t > 0.0:
        var kick := recoil_t / FIRE_DELAY
        target_rot.x += 7.0 * kick
        target_pos.z += 0.05 * kick

    var blend := min(delta * 14.0, 1.0)
    kael_pivot.translation = kael_pivot.translation.linear_interpolate(target_pos, blend)
    kael_pivot.rotation_degrees = kael_pivot.rotation_degrees.linear_interpolate(target_rot, blend)
    kael_pivot.scale = kael_pivot.scale.linear_interpolate(target_scale, blend)


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
    recoil_t = FIRE_DELAY
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
    if kael_pivot != null or chr != null:
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
