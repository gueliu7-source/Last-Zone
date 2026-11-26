extends Reference
# "Cérebro" compartilhado dos bots: observa como o jogador se move durante os tiroteios
# e guarda isso em arquivo (user://brain.cfg) para os bots ficarem mais espertos a cada partida.

const FILE := "user://brain.cfg"

var samples := 0            # quantas observações já foram feitas (em todas as partidas)
var strafe_bias := 0.0      # -1 = jogador costuma desviar para a esquerda, +1 = direita
var moving_frac := 0.7      # 0 = fica parado/acampando, 1 = está sempre em movimento
var sprint_frac := 0.3
var obs_t := 0.0


func load_data() -> void:
    var cf := ConfigFile.new()
    if cf.load(FILE) != OK:
        return
    samples = int(cf.get_value("brain", "samples", 0))
    strafe_bias = float(cf.get_value("brain", "strafe_bias", 0.0))
    moving_frac = float(cf.get_value("brain", "moving_frac", 0.7))
    sprint_frac = float(cf.get_value("brain", "sprint_frac", 0.3))


func save_data() -> void:
    var cf := ConfigFile.new()
    cf.set_value("brain", "samples", samples)
    cf.set_value("brain", "strafe_bias", strafe_bias)
    cf.set_value("brain", "moving_frac", moving_frac)
    cf.set_value("brain", "sprint_frac", sprint_frac)
    cf.save(FILE)


# 0.30 (novato) até 0.80 (bem treinado)
func skill() -> float:
    return clamp(0.30 + min(float(samples), 600.0) / 600.0 * 0.5, 0.3, 0.8)


# Distância que os bots preferem manter: chegam mais perto de quem fica parado.
func pref_distance() -> float:
    return lerp(11.0, 18.0, clamp(moving_frac, 0.0, 1.0))


# Chamado a cada ~0.25 s com os bots que estão em combate com o jogador.
func observe(player, fighters: Array, delta: float) -> void:
    obs_t -= delta
    if obs_t > 0.0:
        return
    obs_t = 0.25
    if fighters.empty() or not player.alive:
        return
    var v: Vector3 = player.velocity
    v.y = 0.0
    var spd: float = v.length()
    var moving: float = 0.0
    if spd > 1.0:
        moving = 1.0
    moving_frac += (moving - moving_frac) * 0.03
    var sp: float = 0.0
    if spd > 8.5:
        sp = 1.0
    sprint_frac += (sp - sprint_frac) * 0.03
    if spd > 1.0:
        var nearest = fighters[0]
        var nd: float = 1e9
        for b in fighters:
            var d: float = b.global_transform.origin.distance_to(player.global_transform.origin)
            if d < nd:
                nd = d
                nearest = b
        var f: Vector3 = player.global_transform.origin - nearest.global_transform.origin
        f.y = 0.0
        f = f.normalized()
        var right: Vector3 = f.cross(Vector3.UP)
        var lat: float = clamp(v.dot(right) / 7.0, -1.0, 1.0)
        strafe_bias += (lat - strafe_bias) * 0.08
    samples += 1
