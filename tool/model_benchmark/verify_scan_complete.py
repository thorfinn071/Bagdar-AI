"""Admit full-pixel envelopes and decisions; retain all earlier freezes."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import verify_visible_body as previous

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tool/blender'))
from scan_view_selection import choose_views

SCAN=ROOT/'test/fixtures/spatial_safety/blender-scan-coverage-v1'
COMPLETE=ROOT/'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1'
CANONICAL=ROOT/'test/fixtures/spatial_safety/blender-scan-watertight-height-v1'
EXACT=ROOT/'test/fixtures/spatial_safety/blender-scan-exact-height-v1'
OLD=previous.BODY
REPORT=ROOT/'docs/_baseline_logs/blender_scan_complete_replay_v1.json'
BASE_REPORT=ROOT/'docs/_baseline_logs/blender_scan_coverage_replay_v1.json'
RECEIPT=ROOT/'docs/_baseline_logs/blender_scan_complete_contract_v1.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def data(root,record,dtype='<f4'):
    path=(root/record['path']).resolve()
    assert path.is_relative_to(root.resolve()) and sha(path)==record['sha256']
    array=np.frombuffer(gzip.decompress(path.read_bytes()),dtype=dtype)
    assert array.size==320*240
    return array.reshape(240,320)


def check_sources(value):
    for path,expected in value['sources'].items():
        assert sha(ROOT/path)==expected, path


def base_admission():
    assert previous.build()==read(previous.RECEIPT)
    manifest=read(SCAN/'manifest.json')
    assert manifest['promotionAllowed'] is False
    assert manifest['priorVisibleManifestSha256']==sha(OLD/'manifest.json')
    check_sources(manifest)
    old=read(OLD/'manifest.json')
    assert len(manifest['layouts'])==12
    count=exact=0
    new_upper_pixels=0
    for layout in manifest['layouts']:
        reference=next(s for s in old['sequences'] if s['sceneId']==layout['sceneId'])
        assert len(layout['sameViewsNewBounds'])==10
        assert len(layout['coverageViewsNewBounds'])==12
        sample=layout['coverageViewsNewBounds'][0]
        plan=choose_views(sample['fx'],sample['fy'],320,240,sample['cameraOriginM'][2])
        assert layout['grid']==json.loads(json.dumps(plan))
        for group in ('sameViewsNewBounds','coverageViewsNewBounds'):
            for i,p in enumerate(layout[group]):
                assert p['width']==320 and p['height']==240
                rotation=np.array(p['cameraToWalkingRotation']).reshape(3,3)
                assert np.allclose(rotation.T@rotation,np.eye(3),atol=1e-5)
                assert abs(np.linalg.det(rotation)-1)<1e-5
                depth=data(SCAN,p['depth']); lower=data(SCAN,p['freeZLower'])
                upper=data(SCAN,p['surfaceZUpper']); valid=data(SCAN,p['validity'],'u1')==1
                yy,xx=np.mgrid[:240,:320]
                axis=depth/np.sqrt(1+((xx+.5-p['cx'])/p['fx'])**2+((yy+.5-p['cy'])/p['fy'])**2)
                assert (np.isfinite(depth[valid]) & (depth[valid]>0)).all()
                assert (np.isfinite(lower[valid]) & (lower[valid]>=0) & (lower[valid]<=axis[valid]+2e-5)).all()
                bounded=valid & np.isfinite(upper)
                assert (upper[bounded]>=axis[bounded]-2e-5).all()
                if group=='sameViewsNewBounds':
                    oldp=reference['staticScan'][i]
                    for key in ('depth','freeZLower','validity'):
                        assert gzip.decompress((SCAN/p[key]['path']).read_bytes())==gzip.decompress((OLD/oldp[key]['path']).read_bytes())
                    assert p['oldPacketUpperSha256']==oldp['surfaceZUpper']['sha256']
                    new_upper_pixels+=int((~np.isfinite(data(OLD,oldp['surfaceZUpper'])) & bounded).sum())
                    exact+=1
                count+=1
    assert count==264 and exact==120 and new_upper_pixels>0
    report=read(BASE_REPORT)
    assert report['passed'] is True and report['geometryGoalReached'] is False
    assert report['manifestSha256']==sha(SCAN/'manifest.json')
    assert report['evaluatorSha256']==sha(ROOT/'test/blender_scan_coverage_replay_test.dart')
    assert report['priorReportSha256']==sha(previous.REPORT)
    for mode in report['modes']:
        assert mode['summary']['hazardIncorrectlyClear']==0
        assert mode['summary']['hazardBlocked']==6 and mode['summary']['strictStaleRejected']==12
    return {'opticalPackets':count,'priorRangeLowerValidityExactViews':exact,'addedBoundedPixels':new_upper_pixels}


def build():
    base=base_admission()
    manifest=read(COMPLETE/'manifest.json')
    assert manifest['promotionAllowed'] is False
    assert manifest['priorManifestSha256']==sha(SCAN/'manifest.json')
    check_sources(manifest)
    for name in ('blender_scan_surface_bounds_v1.json','blender_scan_complete_bounds_v1.json','blender_scan_complete_negatives_v1.json'):
        proof=read(ROOT/'docs/_baseline_logs'/name)
        assert proof['passed'] is True
        check_sources(proof)
    prior=read(SCAN/'manifest.json')
    count=tighter=0
    assert len(manifest['layouts'])==12
    for layout in manifest['layouts']:
        old=next(l for l in prior['layouts'] if l['sceneId']==layout['sceneId'])
        assert len(layout['frames'])==12
        for record,p in zip(layout['frames'],old['coverageViewsNewBounds']):
            assert record['fourArraysExact'] is True and record['axisPacket']==p
            hlo=data(COMPLETE,record['heightLower']); hhi=data(COMPLETE,record['heightUpper'])
            first=data(COMPLETE,record['firstZLower']); lower=data(SCAN,p['freeZLower'])
            upper=data(SCAN,p['surfaceZUpper']); depth=data(SCAN,p['depth'])
            valid=data(SCAN,p['validity'],'u1')==1
            certified=np.isfinite(first)
            assert np.array_equal(certified,np.isfinite(hlo)) and np.array_equal(certified,np.isfinite(hhi))
            assert (valid[certified] & np.isfinite(upper[certified])).all()
            assert (hlo[certified]<=hhi[certified]).all()
            yy,xx=np.mgrid[:240,:320]
            a=(xx+.5-p['cx'])/p['fx']; b=(yy+.5-p['cy'])/p['fy']
            axis=depth/np.sqrt(1+a*a+b*b)
            r=np.array(p['cameraToWalkingRotation'])
            height=p['cameraOriginM'][2]+axis*(r[6]*a+r[7]*b+r[8])
            assert (first[certified]>=lower[certified]-2e-5).all()
            assert (first[certified]<=axis[certified]+2e-5).all()
            assert (first[certified]>=0).all()
            assert (hlo[certified]<=height[certified]+2e-5).all()
            assert (hhi[certified]>=height[certified]-2e-5).all()
            tighter+=int((certified & (first>lower+.001)).sum())
            count+=1
    assert count==144 and tighter>0
    supplement=read(CANONICAL/'manifest.json')
    assert supplement['promotionAllowed'] is False
    assert supplement['priorManifestSha256']==sha(COMPLETE/'manifest.json')
    check_sources(supplement)
    proof=read(ROOT/'docs/_baseline_logs/blender_scan_watertight_bounds_v1.json')
    assert proof['passed'] is True and proof['localizedSlabBottomRemoved'] is True
    assert proof['fractionalHeightRayWitnesses']>0 and proof['thinForegroundPixelsRetained']>0
    assert proof['hiddenGeometryExact'] is True
    check_sources(proof)
    canonical_count=recomputed=improved=0
    assert len(supplement['layouts'])==12
    for layout in supplement['layouts']:
        old=next(l for l in manifest['layouts'] if l['sceneId']==layout['sceneId'])
        assert len(layout['frames'])==12
        for record,packet in zip(layout['frames'],old['frames']):
            assert record['priorPacket']==packet
            hlo=data(CANONICAL,record['heightLower']);hhi=data(CANONICAL,record['heightUpper'])
            oldlo=data(COMPLETE,packet['heightLower']);oldhi=data(COMPLETE,packet['heightUpper'])
            first=data(COMPLETE,packet['firstZLower']);p=packet['axisPacket']
            yy,xx=np.mgrid[:240,:320]
            a=(xx+.5-p['cx'])/p['fx'];b=(yy+.5-p['cy'])/p['fy']
            depth=data(SCAN,p['depth']);axis=depth/np.sqrt(1+a*a+b*b)
            r=np.array(p['cameraToWalkingRotation'])
            height=p['cameraOriginM'][2]+axis*(r[6]*a+r[7]*b+r[8])
            finite=np.isfinite(hlo)
            assert np.array_equal(finite,np.isfinite(hhi))
            assert (hlo[finite]<=hhi[finite]).all()
            assert (hlo[finite]<=height[finite]+2e-5).all()
            assert (hhi[finite]>=height[finite]-2e-5).all()
            previous_floor=np.isfinite(oldlo)&np.isfinite(oldhi)&(oldlo>=-.05)&(oldhi<=.05)
            assert hlo[previous_floor].tobytes()==oldlo[previous_floor].tobytes()
            assert hhi[previous_floor].tobytes()==oldhi[previous_floor].tobytes()
            # A height interval alone cannot create absent free-Z authority.
            admitted=finite&np.isfinite(first)
            improved+=int((admitted&~previous_floor&(hlo>=-.05)&(hhi<=.05)).sum())
            recomputed+=record['recomputedPixels'];canonical_count+=1
    assert canonical_count==144 and improved>0
    exact_manifest=read(EXACT/'manifest.json')
    assert exact_manifest['promotionAllowed'] is False
    assert exact_manifest['priorManifestSha256']==sha(CANONICAL/'manifest.json')
    check_sources(exact_manifest)
    exact_proof=read(ROOT/'docs/_baseline_logs/blender_scan_exact_bounds_v1.json')
    assert exact_proof['passed'] is True and exact_proof['localizedSlabBottomRemoved'] is True
    assert exact_proof['fractionalHeightRayWitnesses']>0 and exact_proof['thinForegroundPixelsRetained']>0
    assert exact_proof['hiddenGeometryExact'] is True
    check_sources(exact_proof)
    exact_count=exact_recomputed=exact_improved=0
    assert len(exact_manifest['layouts'])==12
    for layout in exact_manifest['layouts']:
        canonical=next(l for l in supplement['layouts'] if l['sceneId']==layout['sceneId'])
        assert len(layout['frames'])==12
        for record,packet in zip(layout['frames'],canonical['frames']):
            assert record['priorPacket']==packet
            hlo=data(EXACT,record['heightLower']);hhi=data(EXACT,record['heightUpper'])
            oldlo=data(CANONICAL,packet['heightLower']);oldhi=data(CANONICAL,packet['heightUpper'])
            complete_packet=packet['priorPacket'];first=data(COMPLETE,complete_packet['firstZLower'])
            p=complete_packet['axisPacket'];yy,xx=np.mgrid[:240,:320]
            a=(xx+.5-p['cx'])/p['fx'];b=(yy+.5-p['cy'])/p['fy']
            depth=data(SCAN,p['depth']);axis=depth/np.sqrt(1+a*a+b*b)
            r=np.array(p['cameraToWalkingRotation'])
            height=p['cameraOriginM'][2]+axis*(r[6]*a+r[7]*b+r[8])
            finite=np.isfinite(hlo)
            assert np.array_equal(finite,np.isfinite(hhi))
            assert (hlo[finite]<=hhi[finite]).all()
            assert (hlo[finite]<=height[finite]+2e-5).all()
            assert (hhi[finite]>=height[finite]-2e-5).all()
            previous_floor=np.isfinite(oldlo)&np.isfinite(oldhi)&(oldlo>=-.05)&(oldhi<=.05)
            assert hlo[previous_floor].tobytes()==oldlo[previous_floor].tobytes()
            assert hhi[previous_floor].tobytes()==oldhi[previous_floor].tobytes()
            admitted=finite&np.isfinite(first)
            exact_improved+=int((admitted&~previous_floor&(hlo>=-.05)&(hhi<=.05)).sum())
            exact_recomputed+=record['recomputedPixels'];exact_count+=1
    assert exact_count==144 and exact_improved>0
    report=read(REPORT)
    assert report['passed'] is True and report['promotionAllowed'] is False and report['runtimeWired'] is False
    assert report['manifestSha256']==sha(EXACT/'manifest.json')
    assert report['canonicalHeightManifestSha256']==sha(CANONICAL/'manifest.json')
    assert report['completeEnvelopeManifestSha256']==sha(COMPLETE/'manifest.json')
    assert report['priorReportSha256']==sha(BASE_REPORT)
    assert report['evaluatorSha256']==sha(ROOT/'test/blender_scan_complete_replay_test.dart')
    assert report['summary']=={'passableMeasuredClear':6,'hazardBlocked':6,'hazardIncorrectlyClear':0,'strictStaleRejected':12}
    assert report['geometryGoalReached'] is True
    assert report['originalHeightSummary']=={'passableUnavailable':6,'hazardBlocked':6}
    assert len(report['scans'])==12
    for scan in report['scans']:
        assert scan['strictStatus']=='unavailable' and 'staleObservation' in scan['strictReasons']
        assert scan['originalHeightStatus']==('blocked' if scan['physicalHazard'] else 'unavailable')
        if scan['physicalHazard']:
            assert scan['diagnosticStatus']=='blocked'
        else:
            assert scan['diagnosticStatus']=='measuredClear' and scan['unknownBodyBoxes']==0
            assert all(s['state']=='measured' and s['bodyObservedFraction']==1 and s['floorObservedFraction']==1 for s in scan['sections'])
    sources=dict(read(previous.RECEIPT)['sources'])
    sources.update(read(SCAN/'manifest.json')['sources'])
    sources.update(manifest['sources'])
    sources.update(supplement['sources'])
    sources.update(exact_manifest['sources'])
    for p in ('lib/safety/perception/camera_height_envelope_passage_source.dart',
              'test/blender_scan_coverage_replay_test.dart','test/harness/blender_scan_coverage_fixture.dart',
              'test/blender_scan_complete_replay_test.dart','test/harness/blender_scan_complete_fixture.dart',
              'tool/model_benchmark/verify_scan_complete.py'):
        sources[p]=sha(ROOT/p)
    return {'schemaVersion':1,'passed':True,'promotionAllowed':False,'runtimeWired':False,
            'deviceRuntime':'not_run','scope':'known static synthetic geometry; strict stale rejection retained',
            'priorBodyReceiptSha256':sha(previous.RECEIPT),'scanManifestSha256':sha(SCAN/'manifest.json'),
            'completeManifestSha256':sha(COMPLETE/'manifest.json'),'baseReportSha256':sha(BASE_REPORT),
            'canonicalManifestSha256':sha(CANONICAL/'manifest.json'),
            'exactManifestSha256':sha(EXACT/'manifest.json'),
            'reportSha256':sha(REPORT),'sources':sources,'baseAdmission':base,
            'completeAdmission':{'heightFreeBoundPackets':count,'tighterFirstZPixels':tighter},
            'canonicalAdmission':{'heightPackets':canonical_count,'recomputedPixels':recomputed,
                                  'addedJointFloorProofPixels':improved},
            'exactAdmission':{'heightPackets':exact_count,'recomputedPixels':exact_recomputed,
                              'addedJointFloorProofPixels':exact_improved}}


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--write',action='store_true')
    parser.add_argument('--baseline-only',action='store_true')
    args=parser.parse_args()
    if args.baseline_only:
        print(json.dumps(base_admission(),indent=2))
    else:
        current=build()
        if args.write:
            if RECEIPT.exists(): raise ValueError('Complete scan receipt is write-once')
            RECEIPT.write_text(json.dumps(current,indent=2)+'\n',encoding='utf-8')
        else:
            assert current==read(RECEIPT),'Complete scan contract drift'
        print(json.dumps({k:v for k,v in current.items() if k!='sources'},indent=2))
