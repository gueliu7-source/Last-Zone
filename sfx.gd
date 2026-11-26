extends Reference
# Sons gerados por código (nenhum arquivo de áudio). Tudo é calculado uma vez ao abrir o jogo.

const RATE := 22050


static func _buf(sec: float) -> PoolRealArray:
    var a := PoolRealArray()
    a.resize(int(sec * RATE))
    return a


static func _to_stream(f: PoolRealArray, loop: bool) -> AudioStreamSample:
    var bytes := PoolByteArray()
    bytes.resize(f.size() * 2)
    for i in range(f.size()):
        var iv: int = int(clamp(f[i], -1.0, 1.0) * 30000.0)
        if iv < 0:
            iv += 65536
        bytes[i * 2] = iv & 255
        bytes[i * 2 + 1] = (iv >> 8) & 255
    var s := AudioStreamSample.new()
    s.format = AudioStreamSample.FORMAT_16_BITS
    s.mix_rate = RATE
    s.stereo = false
    s.data = bytes
    if loop:
        s.loop_mode = AudioStreamSample.LOOP_FORWARD
        s.loop_begin = 0
        s.loop_end = f.size()
    return s


# Ruído filtrado (passa-baixa). Duas passadas deixam o começo e o fim do loop combinando.
static func _lp_noise(rng: RandomNumberGenerator, n: int, k: float) -> PoolRealArray:
    var out := PoolRealArray()
    out.resize(n)
    var y: float = 0.0
    for pass_i in range(2):
        for i in range(n):
            y += (rng.randf_range(-1.0, 1.0) - y) * k
            if pass_i == 1:
                out[i] = y
    return out


static func build_all() -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = 12345
    var bank := {}

    # --- tiro
    var a := _buf(0.30)
    var lp: float = 0.0
    var ph: float = 0.0
    for i in range(a.size()):
        var t: float = float(i) / RATE
        lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.5
        ph += TAU * (45.0 + 140.0 * exp(-t * 9.0)) / RATE
        a[i] = (lp * exp(-t * 28.0) * 1.2 + sin(ph) * exp(-t * 14.0) * 0.9 + lp * exp(-t * 9.0) * 0.25) * 0.6
    bank["shot"] = _to_stream(a, false)

    # --- acerto no inimigo (tique)
    a = _buf(0.08)
    for i in range(a.size()):
        var t: float = float(i) / RATE
        a[i] = sin(TAU * 1500.0 * t) * exp(-t * 55.0) * 0.6 + sin(TAU * 2300.0 * t) * exp(-t * 70.0) * 0.35
    bank["hit"] = _to_stream(a, false)

    # --- dano no jogador
    a = _buf(0.25)
    ph = 0.0
    lp = 0.0
    for i in range(a.size()):
        var t: float = float(i) / RATE
        lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
        ph += TAU * (70.0 + 100.0 * exp(-t * 12.0)) / RATE
        a[i] = sin(ph) * exp(-t * 11.0) * 0.9 + lp * exp(-t * 20.0) * 0.5
    bank["hurt"] = _to_stream(a, false)

    # --- passo
    a = _buf(0.12)
    lp = 0.0
    for i in range(a.size()):
        var t: float = float(i) / RATE
        lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.15
        a[i] = lp * exp(-t * 35.0) * 2.2
    bank["step"] = _to_stream(a, false)

    # --- recarregar (dois cliques)
    a = _buf(0.6)
    for i in range(a.size()):
        var t: float = float(i) / RATE
        var v: float = 0.0
        var l1: float = t
        if l1 < 0.08:
            v += (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 1900.0 * l1) * 0.4) * exp(-l1 * 90.0)
        var l2: float = t - 0.34
        if l2 >= 0.0 and l2 < 0.1:
            v += (rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * 1100.0 * l2) * 0.5) * exp(-l2 * 70.0)
        a[i] = v
    bank["reload"] = _to_stream(a, false)

    # --- item coletado
    a = _buf(0.25)
    for i in range(a.size()):
        var t: float = float(i) / RATE
        var f: float = 660.0
        var loc: float = t
        if t >= 0.1:
            f = 990.0
            loc = t - 0.1
        a[i] = sin(TAU * f * t) * exp(-loc * 12.0) * 0.55
    bank["pickup"] = _to_stream(a, false)

    # --- pouso
    a = _buf(0.4)
    ph = 0.0
    lp = 0.0
    for i in range(a.size()):
        var t: float = float(i) / RATE
        lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
        ph += TAU * (40.0 + 50.0 * exp(-t * 10.0)) / RATE
        a[i] = sin(ph) * exp(-t * 9.0) * 1.0 + lp * exp(-t * 22.0) * 0.7
    bank["land"] = _to_stream(a, false)

    # --- paraquedas abrindo
    a = _buf(0.6)
    lp = 0.0
    for i in range(a.size()):
        var t: float = float(i) / RATE
        lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
        var env: float = min(t / 0.06, 1.0) * exp(-max(t - 0.06, 0.0) * 6.0)
        a[i] = lp * env * 2.0 + sin(TAU * 70.0 * t) * exp(-t * 9.0) * 0.5
    bank["chute"] = _to_stream(a, false)

    # --- aviso da zona
    a = _buf(0.7)
    for i in range(a.size()):
        var t: float = float(i) / RATE
        var v: float = 0.0
        if t < 0.18:
            v = sin(TAU * 740.0 * t) * min(t * 150.0, 1.0) * min((0.18 - t) * 150.0, 1.0)
        elif t >= 0.28 and t < 0.46:
            var u: float = t - 0.28
            v = sin(TAU * 740.0 * t) * min(u * 150.0, 1.0) * min((0.18 - u) * 150.0, 1.0)
        a[i] = v * 0.5
    bank["zone"] = _to_stream(a, false)

    # --- derrota (descendo)
    a = _buf(1.0)
    ph = 0.0
    for i in range(a.size()):
        var t: float = float(i) / RATE
        ph += TAU * (330.0 - 220.0 * t) / RATE
        a[i] = (sin(ph) + 0.4 * sin(ph * 2.0)) * exp(-t * 2.2) * 0.5
    bank["lose"] = _to_stream(a, false)

    # --- vitória (arpejo)
    a = _buf(1.0)
    var notes := [523.0, 659.0, 784.0, 1047.0]
    for i in range(a.size()):
        var t: float = float(i) / RATE
        var v: float = 0.0
        for k in range(4):
            var l: float = t - float(k) * 0.16
            if l >= 0.0:
                var dur: float = 0.5
                if k == 3:
                    dur = 1.0
                v += sin(TAU * notes[k] * t) * exp(-l * (3.0 / dur) * 2.0) * 0.28
        a[i] = v
    bank["win"] = _to_stream(a, false)

    # --- vento (loop de 2 s)
    var n: int = int(2.0 * RATE)
    var w := _lp_noise(rng, n, 0.07)
    for i in range(n):
        var t: float = float(i) / RATE
        w[i] = w[i] * 2.2 * (0.75 + 0.25 * sin(TAU * t / 2.0))
    bank["wind"] = _to_stream(w, true)

    # --- motor do avião (loop de 1 s; frequências inteiras = emenda perfeita)
    n = RATE
    var e := _lp_noise(rng, n, 0.1)
    for i in range(n):
        var t: float = float(i) / RATE
        var tone: float = sin(TAU * 58.0 * t) * 0.5 + sin(TAU * 116.0 * t) * 0.3 + sin(TAU * 174.0 * t) * 0.15
        e[i] = (tone + e[i] * 2.5) * (1.0 + 0.25 * sin(TAU * 9.0 * t)) * 0.42
    bank["engine"] = _to_stream(e, true)

    return bank
