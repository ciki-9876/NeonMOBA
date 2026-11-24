"""NEON DRIFT - procedural sound effects + synthwave loop (numpy only)."""
import numpy as np, wave, os, sys

SR = 32000
OUT = sys.argv[1] if len(sys.argv) > 1 else 'sfx'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t_(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, a=0.002, d=None, curve=3.0):
    t = np.arange(n) / SR
    att = np.clip(t / max(a, 1e-4), 0, 1)
    dur = n / SR
    dec = np.clip(1 - t / dur, 0, 1) ** curve
    return att * dec


def osc(freq, dur, kind='sq'):
    t = t_(dur)
    f = np.broadcast_to(freq, t.shape) if np.ndim(freq) else np.full(t.shape, freq)
    ph = np.cumsum(f) / SR
    if kind == 'sq':
        return np.sign(np.sin(2 * np.pi * ph)) * 0.6
    if kind == 'saw':
        return 2 * (ph % 1) - 1
    if kind == 'tri':
        return 2 * np.abs(2 * (ph % 1) - 1) - 1
    return np.sin(2 * np.pi * ph)


def lp(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def save(name, x, gain=0.9):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1
    x = x / peak * gain
    data = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())


def sweep(f0, f1, dur, curve=1.0):
    t = t_(dur) / dur
    return f0 + (f1 - f0) * t ** curve


# --- effects ---
d = 0.07; save('shoot', osc(sweep(1400, 500, d, 0.5), d, 'sq') * env(int(SR * d), curve=2), 0.5)
d = 0.06; save('hit', (osc(sweep(500, 200, d), d, 'sq') * 0.6 + noise(d) * 0.4) * env(int(SR * d)), 0.6)
d = 0.45
thump = osc(sweep(160, 35, d, 0.4), d, 'sin') * env(int(SR * d), curve=2)
crack = lp(noise(d), 2500) * env(int(SR * d), curve=4)
save('explode', thump * 0.9 + crack * 1.4, 0.85)
d = 1.2
thump = osc(sweep(110, 25, d, 0.3), d, 'sin') * env(int(SR * d), curve=1.6)
rumble = lp(noise(d), 900) * env(int(SR * d), curve=2)
save('boom', thump + rumble * 1.8, 0.95)
d = 0.09; save('pickup', (osc(1320, d, 'sin') + 0.3 * osc(2640, d, 'tri')) * env(int(SR * d), curve=2), 0.5)
# level up: rising arpeggio
notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
seg = []
for i, f in enumerate(notes):
    dd = 0.075 if i < len(notes) - 1 else 0.35
    seg.append((osc(f, dd, 'sq') * 0.5 + osc(f * 2, dd, 'tri') * 0.3) * env(int(SR * dd), curve=1.5))
save('levelup', np.concatenate(seg), 0.7)
d = 0.35; save('hurt', (osc(sweep(320, 50, d), d, 'saw') + lp(noise(d), 3000) * 0.6) * env(int(SR * d), curve=1.5), 0.85)
d = 0.22
whoosh = lp(noise(d), 4000) * np.sin(np.linspace(0, np.pi, int(SR * d))) ** 2
save('dash', whoosh + osc(sweep(200, 900, d), d, 'tri') * 0.15 * env(int(SR * d)), 0.6)
d = 0.05; save('select', osc(880, d, 'sq') * env(int(SR * d)), 0.5)
d = 0.12; save('zap', (osc(sweep(2400, 300, d), d, 'saw') + noise(d) * 0.5) * env(int(SR * d), curve=2), 0.45)
# boss warning siren
parts = []
for i in range(4):
    dd = 0.25
    f = 440 if i % 2 == 0 else 330
    parts.append(osc(f, dd, 'saw') * 0.6 * env(int(SR * dd), a=0.01, curve=0.6))
save('warning', lp(np.concatenate(parts), 3000), 0.75)

# --- synthwave loop: 120 bpm, 8 bars, Am F C G ---
BPM = 120
beat = 60 / BPM
bars = 8
total = int(SR * beat * 4 * bars)
mix = np.zeros(total)


def place(sig, start_s, gain=1.0):
    i = int(start_s * SR)
    j = min(total, i + len(sig))
    mix[i:j] += sig[:j - i] * gain


def midi(n):
    return 440 * 2 ** ((n - 69) / 12)


chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]  # Am F C G
roots = [45, 41, 48, 43]
for bar in range(bars):
    ch = chords[bar % 4]
    root = roots[bar % 4]
    t0 = bar * 4 * beat
    # bass 8ths (octave pump)
    for k in range(8):
        n = root - 12 + (12 if k % 2 else 0)
        dd = beat / 2
        s = osc(midi(n), dd, 'saw') * env(int(SR * dd), a=0.003, curve=1.2)
        place(lp(s, 700), t0 + k * dd, 0.55)
    # arp 16ths
    seq = ch + [ch[0] + 12] + ch[::-1] + [ch[0] + 12]
    for k in range(16):
        n = seq[k % len(seq)] + 12
        dd = beat / 4
        s = osc(midi(n), dd, 'sq') * env(int(SR * dd), a=0.002, curve=2.5)
        place(lp(s, 3500), t0 + k * dd, 0.16)
    # pad
    dd = beat * 4
    pad = sum(osc(midi(n), dd, 'saw') for n in ch) / 3
    pad = lp(pad, 1200) * np.minimum(1, np.linspace(0, 6, int(SR * dd))) * np.minimum(1, np.linspace(6, 0, int(SR * dd)))
    place(pad, t0, 0.18)
    # drums
    for b in range(4):
        kd = 0.25
        kick = osc(sweep(140, 40, kd, 0.3), kd, 'sin') * env(int(SR * kd), curve=2.5)
        place(kick, t0 + b * beat, 0.9)
        if b in (1, 3):
            sd = 0.2
            sn = lp(noise(sd), 6000) * env(int(SR * sd), curve=3) + osc(200, sd, 'tri') * env(int(SR * sd), curve=6) * 0.4
            place(sn, t0 + b * beat, 0.45)
        for h in range(2):
            hd = 0.04
            hat = (noise(hd) - lp(noise(hd), 6000)) * env(int(SR * hd), curve=2)
            place(hat, t0 + b * beat + h * beat / 2, 0.25)
save('music', mix, 0.8)
print('audio ok ->', OUT)
