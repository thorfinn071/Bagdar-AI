"""Plot source coverage, keeping actual planner decisions in the caption."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np


def render(directory):
    replay = json.loads((directory/'replay.json').read_text())
    profile = json.loads((directory/'elapsed-no-nn.json').read_text())
    fig, axes = plt.subplots(2, 2, figsize=(11, 6.5))
    fig.subplots_adjust(left=.07, right=.98, top=.86, bottom=.19, hspace=.45, wspace=.15)
    for row, ident in enumerate(['clear-first', 'clear-final']):
        before = next(g for g in profile['geometry'] if g['id']==ident and g['mode']=='single')
        after = next(g for g in profile['geometry'] if g['id']==ident and g['mode']=='rig')
        for col, key in enumerate(['bodyObservedFraction', 'floorObservedFraction']):
            ax = axes[row,col]
            x = [(s['forwardStartM']+s['forwardEndM'])/2 for s in after['sections']]
            ax.step(x, [100*s[key] for s in before['sections']], where='mid', color='#6e83bd', lw=2, label='Original camera')
            ax.step(x, [100*s[key] for s in after['sections']], where='mid', color='#218875', lw=2.5, label='12 simultaneous depth views')
            ax.set_ylim(-3,108)
            ax.set_xlim(.2,3.5)
            ax.set_title(('Start' if row==0 else 'End') + ' of known approach: ' + ('body' if col==0 else 'floor'), fontsize=11)
            ax.set_ylabel('Certified coverage (%)')
            ax.grid(alpha=.2)
            if row==1:
                ax.set_xlabel('Distance ahead (m)')
    fig.suptitle('Synchronized observations cover the complete tested corridor', fontsize=15, weight='bold')
    handles, labels = axes[0,0].get_legend_handles_labels()
    fig.legend(handles,labels,loc='lower center',bbox_to_anchor=(.5,.09),ncol=2,frameon=False)
    summary = replay['summary']
    fig.text(.02,.025,
        f"Actual shadow runtime: original {summary['controlStops']}/2 stops; rig {summary['rigStops']}/2 stops, "
        f"{summary['rigContinues']}/2 continues. Hazards: {summary['hazardStops']}/5 stops.\n"
        'Ideal synthetic static rig plus primary RGB camera; metric envelopes come from renderer. '
        'No phone, temporal recovery or capture-to-command measurement.',fontsize=9)
    for suffix in ['png','svg']:
        fig.savefig(directory/f'coverage-transfer.{suffix}',dpi=170,bbox_inches='tight')
    plt.close(fig)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('directory')
    args=parser.parse_args()
    render(Path(args.directory).resolve())
