#!/usr/bin/env python3
"""
Bagdar Alpha-Test Session Analyzer
-----------------------------------
Reads .jsonl field logs and prints key metrics.

Usage:
    python analyze_session.py <session_file.jsonl>
    python analyze_session.py logs/           # all sessions in dir
"""

import json
import sys
import os
from collections import Counter
from pathlib import Path


def load_events(path: str) -> list[dict]:
    events = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return events


def percentile(values: list, pct: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    idx = int(len(s) * pct / 100)
    return s[min(idx, len(s) - 1)]


def analyze(events: list[dict], filename: str):
    if not events:
        print(f"  [empty session]")
        return

    print(f"\n{'='*60}")
    print(f"  SESSION: {filename}")
    print(f"{'='*60}")

    # --- session metadata ---
    starts = [e for e in events if e['event'] == 'session_start']
    ends = [e for e in events if e['event'] == 'session_end']
    if starts:
        d = starts[0].get('data', {})
        print(f"  Device:     {d.get('device', '?')}")
        print(f"  Android:    {d.get('android', '?')}")
        print(f"  DepthTier:  {d.get('depthTier', '?')}")
        print(f"  Language:   {d.get('language', '?')}")
        print(f"  GuideDog:   {d.get('guideDog', False)}")
        print(f"  Battery:    {d.get('batteryPct', '?')}%")
    if ends:
        d = ends[0].get('data', {})
        dur = d.get('durationSec', 0)
        print(f"  Duration:   {dur // 60}m {dur % 60}s")
        print(f"  Events:     {d.get('totalEvents', len(events))}")

    # --- detection stats ---
    dets = [e for e in events if e['event'] == 'detection']
    if len(dets) >= 2:
        total_ms = dets[-1]['ts'] - dets[0]['ts']
        fps = len(dets) / (total_ms / 1000) if total_ms > 0 else 0
        infer_times = [e['data']['inferMs'] for e in dets if 'inferMs' in e.get('data', {})]
        track_counts = [e['data']['tracks'] for e in dets if 'tracks' in e.get('data', {})]
        print(f"\n  --- Detection ---")
        print(f"  Frames:       {len(dets)}")
        print(f"  Avg FPS:      {fps:.1f}")
        if infer_times:
            print(f"  Inference P50: {percentile(infer_times, 50):.0f} ms")
            print(f"  Inference P95: {percentile(infer_times, 95):.0f} ms")
        if track_counts:
            print(f"  Avg tracks:   {sum(track_counts)/len(track_counts):.1f}")
            print(f"  Max tracks:   {max(track_counts)}")

    # --- TTS stats ---
    tts = [e for e in events if e['event'] == 'tts_say']
    if tts:
        priorities = Counter(e['data']['priority'] for e in tts if 'priority' in e.get('data', {}))
        print(f"\n  --- TTS Alerts ---")
        print(f"  Total:      {len(tts)}")
        for p in ['critical', 'warning', 'info']:
            if p in priorities:
                print(f"    {p:10s}: {priorities[p]}")

        # top 5 most frequent texts
        texts = Counter(e['data'].get('text', '?') for e in tts)
        print(f"  Top alerts:")
        for text, count in texts.most_common(5):
            short = text[:50] + ('...' if len(text) > 50 else '')
            print(f"    {count:3d}x  {short}")

    # --- FP / FN markers ---
    fps_list = [e for e in events if e['event'] == 'fp_marker']
    fns_list = [e for e in events if e['event'] == 'fn_marker']
    if fps_list or fns_list:
        print(f"\n  --- FP/FN Markers ---")
        print(f"  False Positives:  {len(fps_list)}")
        print(f"  False Negatives:  {len(fns_list)}")
        total_alerts = len(tts)
        if total_alerts > 0:
            print(f"  FP rate:          {len(fps_list)/total_alerts*100:.1f}%")

    # --- depth hazards ---
    hazards = [e for e in events if e['event'] == 'depth_hazard']
    if hazards:
        types = Counter(e['data']['type'] for e in hazards if 'type' in e.get('data', {}))
        print(f"\n  --- Depth Hazards ---")
        print(f"  Total:    {len(hazards)}")
        for t, c in types.most_common():
            print(f"    {t:22s}: {c}")

    # --- AE transitions ---
    ae = [e for e in events if e['event'] == 'ae_transition']
    if ae:
        ended = [e for e in ae if not e['data'].get('started', True)]
        frames = [e['data']['frames'] for e in ended if 'frames' in e.get('data', {})]
        print(f"\n  --- AE Transitions ---")
        print(f"  Count:        {len(ended)}")
        if frames:
            print(f"  Avg frames:   {sum(frames)/len(frames):.1f}")
            print(f"  Max frames:   {max(frames)}")

    # --- weather gate ---
    weather = [e for e in events if e['event'] == 'weather_gate']
    if weather:
        trans = Counter(e['data']['transition'] for e in weather)
        print(f"\n  --- Weather Gate ---")
        for t, c in trans.items():
            print(f"    {t}: {c}")

    # --- indoor gate ---
    indoor = [e for e in events if e['event'] == 'indoor_gate']
    if indoor:
        trans = Counter(e['data']['transition'] for e in indoor)
        print(f"\n  --- Indoor Gate ---")
        for t, c in trans.items():
            print(f"    {t}: {c}")
        for e in indoor:
            ts = e.get('elapsed', 0)
            print(f"    @{ts//1000}s: {e['data']['transition']}"
                  f" (gps={e['data'].get('gpsAcc', '?')}m)")

    # --- thermal ---
    thermal = [e for e in events if e['event'] == 'thermal']
    if thermal:
        sevs = Counter(e['data']['severity'] for e in thermal)
        print(f"\n  --- Thermal ---")
        for s, c in sevs.items():
            print(f"    {s}: {c}")

    # --- lifecycle ---
    lifecycle = [e for e in events if e['event'] == 'lifecycle']
    if lifecycle:
        actions = Counter(e['data']['action'] for e in lifecycle)
        resumes = [e for e in lifecycle if e['data']['action'] == 'resumed']
        warm = sum(1 for e in resumes if e['data'].get('resumeType') == 'warm')
        cold = sum(1 for e in resumes if e['data'].get('resumeType') == 'cold')
        print(f"\n  --- Lifecycle ---")
        print(f"  Pauses:     {actions.get('paused', 0)}")
        print(f"  Warm resume: {warm}")
        print(f"  Cold reinit: {cold}")

    # --- frozen / droplet ---
    frozen = [e for e in events if e['event'] == 'frozen_frame']
    droplet = [e for e in events if e['event'] == 'droplet']
    if frozen or droplet:
        print(f"\n  --- Camera Health ---")
        print(f"  Frozen frame triggers: {len(frozen)}")
        print(f"  Droplet warnings:      {len(droplet)}")

    print()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    target = sys.argv[1]

    if os.path.isdir(target):
        files = sorted(Path(target).glob('*.jsonl'))
        if not files:
            print(f"No .jsonl files found in {target}")
            sys.exit(1)
        for f in files:
            events = load_events(str(f))
            analyze(events, f.name)
    else:
        events = load_events(target)
        analyze(events, os.path.basename(target))

    print("Done.")


if __name__ == '__main__':
    main()
