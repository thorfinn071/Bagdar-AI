"""Summarize a frozen candidate without relabelling unknown as success."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(root, report):
    result = json.loads((root/'observer.json').read_text())
    manifest = json.loads((root/'manifest.json').read_text())
    baseline = json.loads((root/'baseline.json').read_text())
    if result['promotionAllowed'] is not False or manifest['promotionAllowed'] is not False:
        raise ValueError('Research policy changed')
    if (result['corpusManifestSha256'] != digest(root/'manifest.json') or
            result['baselineSha256'] != digest(root/'baseline.json') or
            result['protocolSha256'] != digest(root/'protocol.json') or
            result['candidateSourceSha256'] != digest(root/'candidate-frozen.dart.txt') or
            result['candidateSourceSha256'] != manifest['candidateSourceSha256']):
        raise ValueError('Foreign experiment/source identity')
    reference = {r['id']: r for r in manifest['images']}
    baseline_by_id = {r['id']: r for r in baseline['images']}
    rows = result['images']
    if (not rows or len(reference) != len(manifest['images']) or
            len(rows) != len(reference) or len({r['id'] for r in rows}) != len(reference)):
        raise ValueError('Missing or duplicate image')
    allowed = {'noiseDominated', 'insufficientStructure', 'blurSuspected', 'structured', 'unknown'}
    for r in rows:
        source = reference[r['id']]
        if any(r[k] != v for k, v in source.items()): raise ValueError('Changed image metadata')
        if any(r[k] != v for k, v in baseline_by_id[r['id']].items()): raise ValueError('Changed baseline')
        path = (root/source['asset']['path']).resolve()
        if not path.is_relative_to(root.resolve()) or digest(path) != source['asset']['sha256']:
            raise ValueError('Changed or unsafe pixels')
        o = r['observer']
        if o['evidence'] not in allowed or o['promotionAllowed'] is not False:
            raise ValueError('Invalid observation')
        if any(v is not None and (not isinstance(v, (int, float)) or not math.isfinite(v))
               for v in (o['residualProxy'], o['structureFraction'], o['edgeConcentration'], o['clippedFraction'])):
            raise ValueError('Nonfinite observation')
    groups, bases, phases, sizes = defaultdict(list), defaultdict(dict), defaultdict(list), defaultdict(list)
    for r in rows:
        if r['split'] != 'diagnostic':
            groups[(r['split'], r['condition'])].append(r)
            bases[r['baseId']][r['condition']] = r
        if r['family'] == 'phase-checker': phases[r['baseId']].append(r)
        sizes[(r['width'], r['height'])].append(r['observerElapsedUs'])
    conditions = [{'split': split, 'condition': c, 'images': len(items),
                   'baselineAccepted': sum(not r['rejected'] for r in items),
                   'evidenceStates': dict(Counter(r['observer']['evidence'] for r in items))}
                  for (split, c), items in groups.items()]
    pairs = []
    for base, items in bases.items():
        for condition in ('defocus-6-white-8', 'defocus-6-correlated-8', 'defocus-6-shot-64'):
            a, b = items['defocus-6'], items[condition]
            pairs.append({'baseId': base, 'split': a['split'], 'condition': condition,
                          'baselineRejectedBlurAcceptedNoisy': a['rejected'] and not b['rejected'],
                          'blurEvidence': a['observer']['evidence'], 'noisyEvidence': b['observer']['evidence']})
    def quantile(values, p): return sorted(values)[math.ceil(len(values)*p)-1] if values else None
    timing = [{'width': w, 'height': h, 'samples': len(v), 'p50Us': quantile(v, .5),
               'p95Us': quantile(v, .95), 'maximumUs': max(v)} for (w, h), v in sizes.items()]
    phase = [{'baseId': base, 'phases': len(items),
              'baselineAccepted': sum(not r['rejected'] for r in items),
              'states': dict(Counter(r['observer']['evidence'] for r in items))} for base, items in phases.items()]
    sparse = [{'id': r['id'], 'baselineRejected': r['rejected'], 'observer': r['observer']}
              for r in rows if r['family'].startswith('sparse-') and r['condition'] == 'sharp']
    summary = {'schemaVersion': 1, 'promotionAllowed': False, 'images': len(rows),
               'observerSha256': digest(root/'observer.json'),
               'candidateSourceSha256': result['candidateSourceSha256'],
               'corpusManifestSha256': result['corpusManifestSha256'],
               'conditions': conditions, 'pairs': pairs, 'phaseProbes': phase,
               'sharpSparseControls': sparse, 'desktopTiming': timing,
               'timingScope': result['timingScope'],
               'physicalDeviceValidation': 'not_run', 'modelAccuracy': 'not_measured'}
    target = root/'observer-summary.json'
    if target.exists() or report.exists(): raise FileExistsError('Preserve existing summaries')
    target.write_text(json.dumps(summary, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    lines = ['# Image-quality observer v1 evaluation', '',
             f"{len(rows)} new diagnostic images; frozen candidate `{result['candidateSourceSha256']}`.",
             'These states describe optical evidence; none is an admission or navigation decision.', '',
             '| Split | Condition | Images | Existing filter admits | Candidate states |',
             '|---|---|---:|---:|---|']
    for r in conditions:
        states = ', '.join(f'{k}={v}' for k, v in r['evidenceStates'].items())
        lines.append(f"| {r['split']} | {r['condition']} | {r['images']} | {r['baselineAccepted']} | {states} |")
    lines += ['', '## Paired noise masking', '',
              '| Split | Added noise after defocus | Pairs | Existing blur rejection flips to admission | Candidate structured on noisy blur | Candidate unknown |',
              '|---|---|---:|---:|---:|---:|']
    for split in ('development', 'holdout'):
        for c in ('defocus-6-white-8', 'defocus-6-correlated-8', 'defocus-6-shot-64'):
            items = [r for r in pairs if r['split'] == split and r['condition'] == c]
            lines.append(f"| {split} | {c} | {len(items)} | {sum(r['baselineRejectedBlurAcceptedNoisy'] for r in items)} | "
                         f"{sum(r['noisyEvidence'] == 'structured' for r in items)} | {sum(r['noisyEvidence'] == 'unknown' for r in items)} |")
    lines += ['', '## Phase and sparse controls', '']
    for r in phase: lines.append(f"- {r['baseId']}: {r['states']}; baseline admits {r['baselineAccepted']}/{r['phases']}.")
    for family in ('sparse-polylines', 'sparse-arcs'):
        items = [r for r in rows if r['family'] == family and r['condition'] == 'sharp']
        lines.append(f"- Sharp {family}: {dict(Counter(r['observer']['evidence'] for r in items))}; "
                     f"existing filter rejects {sum(r['rejected'] for r in items)}/{len(items)}.")
    lines += ['', '## Computational cost', '', result['timingScope'], '']
    for r in timing: lines.append(f"- {r['width']}x{r['height']}: p50 {r['p50Us']} us; p95 {r['p95Us']} us; maximum {r['maximumUs']} us ({r['samples']} images).")
    lines += ['', '## Limits and decision', '',
              'The residual proxy can confuse texture and noise; correlated noise and directional blur need separate interpretation. '
              'Unknown, insufficient structure and noise-dominated states are not correct blur classifications or navigation successes. '
              'Sharp sparse controls are not proof of useful camera information. No overall accuracy is calculated.', '',
              'Candidate remains research-only; production admission unchanged. No live observer cost, calibrated sensor model, '
              'real camera, audio, TalkBack or walking validation. No holdout tuning was performed.', '',
              'Research background on structure confounding noise estimates: '
              '[Colom and Buades](https://www.ipol.im/pub/art/2013/90/). The candidate does not implement that estimator.', '']
    report.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({'images': len(rows), 'desktopTiming': timing,
                      'phaseProbes': phase, 'promotionAllowed': False}, indent=2))
    return summary


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('root', type=Path); p.add_argument('report', type=Path)
    a = p.parse_args(); summarize(a.root, a.report)
