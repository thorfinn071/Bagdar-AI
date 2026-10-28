"""Standalone scientific plots of whole-cell synthetic optical evidence."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch
import numpy as np

VIEWS = ['original', 'chest-level', 'waist-level', 'waist-down', 'ideal-wide-control']
NAMES = ['Original: 1.42 m / 12 deg down', 'Chest: 1.42 m / level',
         'Waist: 0.975 m / level', 'Waist: 0.975 m / 25 deg down',
         'Ideal optics control: 2.5 mm lens*']
COLORS = ['#218875', '#6e83bd', '#dbad58', '#ba5364']


def render(directory):
    report = json.loads((directory / 'comparison.json').read_text())
    rows = [next(r for r in report['frames'] if r['viewId'] == v and r['caseId'] == 'clear-final')
            for v in VIEWS]
    fig, axes = plt.subplots(5, 2, figsize=(12.8, 12.2),
                             gridspec_kw={'width_ratios': [4, 1]})
    fig.subplots_adjust(top=.93, bottom=.11, left=.065, right=.95,
                        hspace=.60, wspace=.07)
    cmap = ListedColormap(COLORS)
    for k, row in enumerate(rows):
        coverage = row['coverage']
        nx, ny, nz = coverage['nx'], coverage['ny'], coverage['nz']
        volume = np.zeros((nz, ny, nx), dtype=int)
        for ix, iy, iz, status in coverage['bodyCells']:
            volume[iz, iy, ix] = (0 if status == 'observed' else 1 if status == 'outsideFrustum'
                                  else 3 if status in ('blocked', 'conflicting') else 2)
        # A cross-section counts as observed only when EVERY lateral cell is.
        view = np.zeros((nz, ny), dtype=int)
        view[np.any(volume == 2, axis=2)] = 2
        view[np.any(volume == 1, axis=2)] = 1
        view[np.any(volume == 3, axis=2)] = 3
        axes[k, 0].imshow(view, origin='lower', interpolation='nearest', aspect='auto',
                          extent=[.2, 3.5, .05, 1.9], cmap=cmap, vmin=0, vmax=3)
        axes[k, 0].set_title(
            NAMES[k] + f"   |   Unknown body: {coverage['unknownBodyBoxes']}/{nx*ny*nz}",
            loc='left', fontsize=10, weight='bold')
        axes[k, 0].set_ylabel('Height (m)')
        axes[k, 0].set_yticks([.05, .5, 1., 1.5, 1.9])
        axes[k, 0].set_xticks([.2, .5, 1, 1.5, 2, 2.5, 3, 3.5])
        floor = np.zeros((ny, nx), dtype=int)
        for ix, iy, status in coverage['floorCells']:
            floor[iy, ix] = (0 if status == 'observed' else 1 if status == 'outsideFrustum'
                             else 3 if status in ('blocked', 'conflicting') else 2)
        axes[k, 1].imshow(floor, origin='lower', interpolation='nearest', aspect='auto',
                          extent=[-.45, .45, .2, 3.5], cmap=cmap, vmin=0, vmax=3)
        axes[k, 1].set_title('Floor (top view)', fontsize=10)
        axes[k, 1].set_yticks([.2, 1, 2, 3.5])
        axes[k, 1].set_xticks([-.45, 0, .45])
        axes[k, 1].yaxis.tick_right()
    axes[-1, 0].set_xlabel('Distance ahead (m)')
    axes[-1, 1].set_xlabel('Lateral position (m)')
    fig.suptitle('Whole-cell coverage of the same clear corridor', fontsize=17, weight='bold')
    fig.legend(handles=[Patch(color=c, label=l) for c, l in zip(COLORS,
        ['Certified by source', 'Outside field of view', 'Depth / pixel proof missing', 'Blocked'])],
        loc='lower center', bbox_to_anchor=(.5, .047), ncol=4, frameon=False)
    fig.text(.02, .013,
             'Body map shows worst status across the complete 0.9 m width. '
             '* Ideal optics is not a phone configuration.\n'
             'Synthetic first-return metric bounds; raw MiDaS stays relative. '
             'Test clock +2 ms; processing latency and Android behavior are not measured.', fontsize=9)
    for suffix in ('png', 'svg'):
        fig.savefig(directory / f'coverage-map.{suffix}', dpi=170, bbox_inches='tight')
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(11, 4.5), layout='constrained')
    outside = [r['coverage']['unknownBodyCauses'].get('outsideFrustum', 0) for r in rows]
    other = [r['coverage']['unknownBodyBoxes'] - n for r, n in zip(rows, outside)]
    x = np.arange(5)
    ax.barh(x, outside, color=COLORS[1], label='Outside field of view')
    ax.barh(x, other, left=outside, color=COLORS[2], label='Depth / pixel proof missing')
    for index, row in enumerate(rows):
        total = row['coverage']['unknownBodyBoxes']
        ax.text(total + 12, index, str(total), va='center')
    ax.set_yticks(x, NAMES)
    ax.invert_yaxis()
    ax.set_xlabel('Uncertified body cells (1716 total; complete-cell tests)')
    ax.set_title('Moving the camera trades blind zones; it does not certify the whole corridor',
                 fontsize=13, weight='bold')
    ax.set_xlim(0, max(outside[i] + other[i] for i in range(5)) + 100)
    ax.legend(frameon=False, loc='lower right')
    ax.grid(axis='x', alpha=.15)
    for suffix in ('png', 'svg'):
        fig.savefig(directory / f'coverage-comparison.{suffix}', dpi=170, bbox_inches='tight')
    plt.close(fig)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    args = parser.parse_args()
    render(Path(args.directory).resolve())
