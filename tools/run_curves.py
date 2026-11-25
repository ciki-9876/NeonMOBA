#!/usr/bin/env python3
"""Calibration batches for player abilities (stage 1 gate). Runs sim/sim_cli.gd for each experiment
and prints win rate + the metric each ability is supposed to move.
usage: python3 tools/run_curves.py [games_per_config] [godot_binary]   (run from the project root)"""
import subprocess, sys, re, json, os, tempfile
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60
GODOT = sys.argv[2] if len(sys.argv) > 2 else 'godot'
CHUNK = 40   # games per godot process (keeps each call short)

def run(args, games=N):
    rows = []
    for start in range(0, games, CHUNK):
        n = min(CHUNK, games - start)
        out = tempfile.mktemp(suffix='.jsonl')
        cmd = [GODOT, '--headless', '--script', 'res://sim/sim_cli.gd', '--', '--quiet', '--mirror',
               '--games', str(n), '--seed', str(1000 + start), '--out', out] + args
        subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        rows += [json.loads(l) for l in open(out)]
        os.remove(out)
    return rows

def stats(rows, team):
    agg = {}
    for r in rows:
        for h in r['heroes']:
            if h['team'] == team:
                for k, v in h['stats'].items():
                    agg[k] = agg.get(k, 0.0) + v
    g = max(len(rows), 1)
    return {
        'shot_acc': 100 * agg.get('shot_hit', 0) / max(agg.get('shot_fired', 0), 1),
        'dodge': 100 * agg.get('dodge_try', 0) / max(agg.get('dodge_seen', 0), 1),
        'tele_taken': agg.get('tele_taken', 0) / g,
        'dmg': agg.get('dmg_hero', 0) / g,
        'taken': agg.get('dmg_taken', 0) / g,
        'core': agg.get('core_time', 0) / g,
        'focus': 100 * agg.get('focus_dmg', 0) / max(agg.get('dmg_hero', 0), 1),
    }

def winrate(rows):
    w = sum(1 for r in rows if r['winner'] == 0)
    l = sum(1 for r in rows if r['winner'] == 1)
    return 100.0 * w / max(w + l, 1), w, l

def report(name, args):
    rows = run(args)
    wr, w, l = winrate(rows)
    sa, sb = stats(rows, 0), stats(rows, 1)
    rounds = sum(r['rounds_played'] for r in rows) / max(len(rows), 1)
    print(f"{name:<34} A win {wr:5.1f}% ({w}:{l})  rounds/map {rounds:.1f} | "
          f"shot_acc {sa['shot_acc']:.0f}/{sb['shot_acc']:.0f}  dodge {sa['dodge']:.0f}/{sb['dodge']:.0f}  "
          f"tele_taken {sa['tele_taken']:.1f}/{sb['tele_taken']:.1f}  core {sa['core']:.0f}/{sb['core']:.0f}s  "
          f"focus {sa['focus']:.0f}/{sb['focus']:.0f}%  dmg {sa['dmg']:.0f}/{sb['dmg']:.0f}", flush=True)
    return wr

if __name__ == '__main__':
    which = sys.argv[3] if len(sys.argv) > 3 else 'all'
    if which in ('all', 'gap'):
        print('== overall ability gap (all 6 abilities, team A = 11 + gap, team B = 11)')
        for gap in [0, 2, 5, 8]:   # mirrored lineups: only the players differ
            report(f'gap +{gap}', ['--attr_a', str(11 + gap), '--attr_b', '11'])
    if which in ('all', 'single'):
        print('== single ability 18 vs 11 (others 11)')
        for k in ['reaction', 'mechanics', 'awareness', 'decision', 'teamwork', 'composure']:
            report(f'{k} 18', ['--set_a', f'{k}=18'])
    if which in ('all', 'prof'):
        print('== proficiency (team A heroes at 10 = 生疏 / 40 = 熟悉 / 95 = 大师 vs 60 = 精通)')
        for p in [10, 40, 95]:
            report(f'prof {p}', ['--prof_a', str(p)])
