
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

    
    tts = [e for e in events if e['event'] == 'tts_say']
    if tts:
        priorities = Counter(e['data']['priority'] for e in tts if 'priority' in e.get('data', {}))
        print(f"\n  --- TTS Alerts ---")
        print(f"  Total:      {len(tts)}")
        for p in ['critical', 'warning', 'info']:
            if p in priorities:
                print(f"    {p:10s}: {priorities[p]}")

        
        texts = Counter(e['data'].get('text', '?') for e in tts)
        print(f"  Top alerts:")
        for text, count in texts.most_common(5):
            short = text[:50] + ('...' if len(text) > 50 else '')
            print(f"    {count:3d}x  {short}")

    
    fps_list = [e for e in events if e['event'] == 'fp_marker']
    fns_list = [e for e in events if e['event'] == 'fn_marker']
    if fps_list or fns_list:
        print(f"\n  --- FP/FN Markers ---")
        print(f"  False Positives:  {len(fps_list)}")
        print(f"  False Negatives:  {len(fns_list)}")
        total_alerts = len(tts)
        if total_alerts > 0:
            print(f"  FP rate:          {len(fps_list)/total_alerts*100:.1f}%")

    
    hazards = [e for e in events if e['event'] == 'depth_hazard']
    if hazards:
        types = Counter(e['data']['type'] for e in hazards if 'type' in e.get('data', {}))
        print(f"\n  --- Depth Hazards ---")
        print(f"  Total:    {len(hazards)}")
        for t, c in types.most_common():
            print(f"    {t:22s}: {c}")

    
    ae = [e for e in events if e['event'] == 'ae_transition']
    if ae:
        ended = [e for e in ae if not e['data'].get('started', True)]
        frames = [e['data']['frames'] for e in ended if 'frames' in e.get('data', {})]
        print(f"\n  --- AE Transitions ---")
        print(f"  Count:        {len(ended)}")
        if frames:
            print(f"  Avg frames:   {sum(frames)/len(frames):.1f}")
            print(f"  Max frames:   {max(frames)}")

    
    weather = [e for e in events if e['event'] == 'weather_gate']
    if weather:
        trans = Counter(e['data']['transition'] for e in weather)
        print(f"\n  --- Weather Gate ---")
        for t, c in trans.items():
            print(f"    {t}: {c}")

    
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

    
    thermal = [e for e in events if e['event'] == 'thermal']
    if thermal:
        sevs = Counter(e['data']['severity'] for e in thermal)
        print(f"\n  --- Thermal ---")
        for s, c in sevs.items():
            print(f"    {s}: {c}")

    
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

    
    frozen = [e for e in events if e['event'] == 'frozen_frame']
    droplet = [e for e in events if e['event'] == 'droplet']
    quality = [e for e in events if e['event'] == 'camera_quality']
    stalls = [e for e in events if e['event'] == 'camera_stall']
    if frozen or droplet or quality or stalls:
        print(f"\n  --- Camera Health ---")
        print(f"  Frozen frame triggers: {len(frozen)}")
        print(f"  Droplet warnings:      {len(droplet)}")
        if quality:
            qtypes = Counter(e['data'].get('type', '?') for e in quality)
            for t, c in qtypes.items():
                print(f"  {t:21s}: {c}")
        if stalls:
            stall_starts = [e for e in stalls if e['data'].get('stalled')]
            stall_ends = [e for e in stalls if not e['data'].get('stalled')]
            durations = [e['data']['durationMs'] for e in stall_ends if 'durationMs' in e.get('data', {})]
            print(f"  Camera stalls:         {len(stall_starts)}")
            if durations:
                print(f"    P50/P95/Max ms:      {percentile(durations, 50):.0f} / {percentile(durations, 95):.0f} / {max(durations)}")

    
    model_loads = [e for e in events if e['event'] == 'model_load']
    if model_loads:
        print(f"\n  --- Model Load Times ---")
        for e in model_loads:
            d = e.get('data', {})
            status = 'OK' if d.get('success') else 'FAIL'
            extra = []
            if 'tier' in d: extra.append(f"tier={d['tier']}")
            if 'gpu' in d: extra.append(f"gpu={d['gpu']}")
            if 'threads' in d: extra.append(f"th={d['threads']}")
            if 'error' in d: extra.append(f"err={d['error'][:40]}")
            print(f"  {d.get('model','?'):8s} {d.get('loadMs',0):5d} ms  {status}  {' '.join(extra)}")

    
    cam_inits = [e for e in events if e['event'] == 'camera_init']
    if cam_inits:
        print(f"\n  --- Camera Init ---")
        for e in cam_inits:
            d = e.get('data', {})
            status = 'OK' if d.get('success') else 'FAIL'
            res = d.get('resolution', '?')
            err = d.get('error', '')
            print(f"  {d.get('initMs',0):5d} ms  {status}  {res}  {err}")

    
    bat = [e for e in events if e['event'] == 'battery_throttle']
    if bat:
        print(f"\n  --- Battery Throttle Transitions ---")
        for e in bat:
            d = e.get('data', {})
            ts = e.get('elapsed', 0) // 1000
            print(f"  @{ts:5d}s  -> {d.get('level','?'):10s}  bat={d.get('batteryPct','?')}%")

    
    mem = [e for e in events if e['event'] == 'memory_pressure']
    if mem:
        print(f"\n  --- Memory Pressure Transitions ---")
        for e in mem:
            d = e.get('data', {})
            ts = e.get('elapsed', 0) // 1000
            avail = d.get('availMb', '?')
            total = d.get('totalMb', '?')
            print(f"  @{ts:5d}s  -> {d.get('level','?'):10s}  avail={avail}/{total} MB")

    
    modes = [e for e in events if e['event'] == 'mode_switch']
    if modes:
        print(f"\n  --- Mode Switches ---")
        for e in modes:
            d = e.get('data', {})
            ts = e.get('elapsed', 0) // 1000
            print(f"  @{ts:5d}s  {d.get('from','?')} -> {d.get('mode','?')}")

    
    tts_evt = [e for e in events if e['event'] == 'tts_event']
    if tts_evt:
        types = Counter(e['data'].get('event', '?') for e in tts_evt)
        print(f"\n  --- TTS Events ---")
        for t, c in types.items():
            print(f"    {t:20s}: {c}")

    
    sos = [e for e in events if e['event'] == 'sos_trigger']
    if sos:
        print(f"\n  --- SOS Triggers ---")
        for e in sos:
            d = e.get('data', {})
            ts = e.get('elapsed', 0) // 1000
            res = d.get('result', 'started')
            print(f"  @{ts:5d}s  {d.get('source','?'):10s}  result={res}")

    
    midas = [e for e in events if e['event'] == 'midas_inference']
    if midas:
        ms = [e['data']['ms'] for e in midas if 'ms' in e.get('data', {})]
        pre = [e['data'].get('preprocessMs', 0) for e in midas]
        ana = [e['data'].get('analyzeMs', 0) for e in midas]
        print(f"\n  --- MiDaS Inference ---")
        print(f"  Frames:        {len(midas)}")
        if ms:
            print(f"  Inference P50/P95/Max: {percentile(ms, 50):.0f} / {percentile(ms, 95):.0f} / {max(ms)} ms")
        if pre:
            print(f"  Preprocess avg:        {sum(pre)/len(pre):.0f} ms")
        if ana:
            print(f"  Analyze avg:           {sum(ana)/len(ana):.0f} ms")

    
    errs = [e for e in events if e['event'] == 'error']
    if errs:
        print(f"\n  --- Errors ---")
        for e in errs:
            d = e.get('data', {})
            ts = e.get('elapsed', 0) // 1000
            print(f"  @{ts:5d}s  [{d.get('location','?')}]  {d.get('error','')[:80]}")

    
    throttler = [e for e in events if e['event'] == 'throttler']
    if throttler:
        det_ms = [e['data'].get('detectMs', 0) for e in throttler]
        midas_ms = [e['data'].get('midasMs', 0) for e in throttler]
        print(f"\n  --- Throttler ---")
        print(f"  Adjustments:   {len(throttler)}")
        if det_ms:
            print(f"  Detect interval P50/P95: {percentile(det_ms, 50):.0f} / {percentile(det_ms, 95):.0f} ms")
        if midas_ms:
            print(f"  MiDaS interval P50/P95:  {percentile(midas_ms, 50):.0f} / {percentile(midas_ms, 95):.0f} ms")

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
