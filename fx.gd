extends Reference
# Utilidades compartilhadas: materiais leves e rastro de bala.


static func make_mat(color: Color, unshaded: bool = false) -> SpatialMaterial:
    var m := SpatialMaterial.new()
    m.albedo_color = color
    m.flags_vertex_lighting = true
    m.flags_unshaded = unshaded
    return m


static func tracer(scene: Node, a: Vector3, b: Vector3, color: Color = Color(1.0, 0.9, 0.4)) -> void:
    var dist: float = a.distance_to(b)
    if dist < 0.2:
        return
    var mi := MeshInstance.new()
    var cm := CubeMesh.new()
    cm.size = Vector3(0.05, 0.05, dist)
    mi.mesh = cm
    mi.material_override = make_mat(color, true)
    mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
    scene.add_child(mi)
    mi.translation = (a + b) / 2.0
    var dir: Vector3 = (b - a).normalized()
    var up: Vector3 = Vector3.UP
    if abs(dir.y) > 0.99:
        up = Vector3.RIGHT
    mi.look_at(b, up)
    scene.get_tree().create_timer(0.06).connect("timeout", mi, "queue_free")
