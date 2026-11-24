"""NEON DRIFT v2 — extra SFX for skills, enemies and UI (numpy only)."""
import numpy as np, wave, os, sys

SR = 32000
OUT = sys.argv[1] if len(sys.argv) > 1 else 'sfx'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)


def T(d): return np.arange(int(SR * d)) / SR
def N(d): return rng.uniform(-1, 1, int(SR * d))
def env(n, a=0.003, curve=3.0):
    t = np.arange(n) / SR
    return np.clip(t / max(a, 1e-4), 0, 1) * np.clip(1 - t / (n / SR), 0, 1) ** curve
def osc(f, d, kind='sin'):
    t = T(d); f = np.full(t.shape, f) if np.ndim(f) == 0 else f
    ph = np.cumsum(f) / SR
    if kind == 'saw': return 2 * (ph % 1) - 1
    if kind == 'sq': return np.sign(np.sin(2 * np.pi * ph))
    if kind == 'tri': return 2 * np.abs(2 * (ph % 1) - 1) - 1
    return np.sin(2 * np.pi * ph)
def lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR); y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y
def hp(x, fc): return x - lp(x, fc)
def sweep(a, b, d, c=1.0): return a + (b - a) * (T(d) / d) ** c
def E(d, **k): return env(int(SR * d), **k)
def save(name, x, gain=0.9):
    x = np.asarray(x, float); x = x / (np.max(np.abs(x)) or 1) * gain
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())


d = 0.12; save('attack', osc(sweep(1600, 700, d, .5), d, 'tri') * E(d, curve=3) + hp(N(d), 4000) * E(d, curve=8) * 0.3, 0.45)
d = 0.1; save('ahit', lp(N(d), 3000) * E(d, curve=5) + osc(sweep(400, 150, d), d) * E(d, curve=4), 0.5)
d = 0.55; save('lance', (osc(sweep(2200, 500, d, .4), d, 'saw') * 0.5 + osc(sweep(1100, 250, d, .4), d, 'sq') * 0.3) * E(d, a=0.005, curve=2) + hp(N(d), 3000) * E(d, curve=4) * 0.4, 0.8)
d = 0.45
blink = hp(N(d), 1500) * np.sin(np.linspace(0, np.pi, int(SR * d))) ** 3 * 0.6 + osc(sweep(300, 1800, d, 2), d, 'tri') * E(d, a=0.2, curve=1) * 0.5
save('blink', blink, 0.7)
d = 0.7; save('nova', (osc(sweep(900, 80, d, .3), d, 'saw') * 0.6 + hp(N(d), 2000) * 0.7) * E(d, curve=2.5) + osc(sweep(120, 40, d), d) * E(d, curve=2), 0.9)
d = 0.35; save('chain', cat := np.concatenate([hp(N(0.03), 3000) * E(0.03, curve=2) for _ in range(6)] + [np.zeros(int(SR * 0.17))]) * 1.0 + osc(sweep(2600, 900, d), d, 'saw')[: int(SR * 0.35)] * E(d, curve=3) * 0.4, 0.6)
d = 3.0
t = T(d)
hum = (osc(sweep(60, 140, d, 1.5), d, 'saw') + osc(sweep(61, 142, d, 1.5), d, 'saw')) * 0.5
hum = lp(hum, 700) * np.minimum(1, t / 0.3) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t)) + lp(N(d), 400) * 0.3 * np.minimum(1, t / 1.5)
save('singularity', hum * np.minimum(1, (d - t) / 0.1), 0.8)
d = 1.4; save('collapse', (osc(sweep(90, 22, d, .3), d) * E(d, curve=1.6) * 1.2 + lp(N(d), 1400) * E(d, curve=2.2) + hp(N(d), 5000) * E(d, curve=8) * 0.6), 0.95)
d = 0.6; save('learn', np.concatenate([osc(f, .12, 'tri') * E(.12, curve=2) for f in (659, 880)] + [osc(1318, .36, 'tri') * E(.36, curve=1.5)]), 0.5)
d = 0.18; save('deny', (osc(180, d, 'sq') * 0.6 + osc(186, d, 'sq') * 0.6) * E(d, a=0.005, curve=1), 0.35)
d = 0.5; save('slam', osc(sweep(80, 30, d, .3), d) * E(d, curve=2) * 1.4 + lp(N(d), 900) * E(d, curve=3), 0.95)
d = 1.1; save('whistle', osc(sweep(1800, 500, d, 1.4), d) * np.minimum(1, T(d) / 0.1) * 0.5, 0.35)
d = 0.8; save('silence', (osc(sweep(500, 300, d), d, 'saw') * osc(sweep(503, 296, d), d, 'saw')) * E(d, a=0.05, curve=1.5) + lp(N(d), 1200) * E(d, curve=3) * 0.3, 0.6)
d = 0.6; save('mend', sum(osc(f * (1 + 0.5 * T(d)), d, 'tri') * E(d, a=0.04, curve=2) for f in (784, 988, 1175)), 0.4)
d = 0.4; save('fuse', hp(N(d), 2500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 14 * T(d)))) * E(d, a=0.01, curve=0.5), 0.4)
d = 0.8; save('rune', sum(osc(f, d, 'tri') * E(d, a=0.02, curve=1.6) for f in (523, 784, 1046, 1568)), 0.55)
d = 2.2; save('boss', (osc(sweep(55, 45, d), d, 'saw') + osc(sweep(82, 68, d), d, 'saw')) * lp(np.ones(int(SR * d)), 5) * E(d, a=0.3, curve=1.2), 0.85)
print('audio2 ok ->', OUT)
