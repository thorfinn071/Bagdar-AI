"""Local, preregistered human collection. No microphone, model inference or uploads.

Consent, labels, novelty and anonymous identity remain supplier assertions.
SHA-256 binds selected bytes; it does not authenticate a person or capture origin.
"""
import argparse
from array import array
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import sys
import tempfile
import wave

PROTOCOL = Path(__file__).with_name('human_protocol.json')
SPLITS = ('train', 'dev', 'test')
CATEGORIES = ('near_word', 'keyword_in_context', 'ordinary_command')
IDENTITY = re.compile(r'[a-z0-9][a-z0-9_-]{0,95}\Z')
DIGEST = re.compile(r'[0-9a-f]{64}\Z')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8') as target:
        target.write(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def selected_path(root, relative):
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise ValueError('expected relative selected audio path')
    selected = (root / relative).resolve()
    if not selected.is_relative_to(root.resolve()):
        raise ValueError('audio escapes selected root')
    return selected


def audio_info(path):
    """Validate the container, retain difficult but valid signals for later evaluation."""
    try:
        with wave.open(str(path), 'rb') as audio:
            frames = audio.getnframes()
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (1, 2, 16000, 'NONE'):
                raise ValueError('expected mono PCM16 WAV at 16000 Hz')
            if not 0 < frames <= 8 * 16000:
                raise ValueError('expected nonempty single utterance of at most 8 seconds')
            raw = audio.readframes(frames)
            if len(raw) != frames * 2:
                raise ValueError('truncated WAV data')
    except (wave.Error, EOFError) as error:
        raise ValueError('invalid WAV container') from error
    samples = array('h', raw)
    if sys.byteorder != 'little':
        samples.byteswap()
    rms = math.sqrt(sum(float(v) * v for v in samples) / frames) / 32768
    clipped = sum(abs(v) >= 32760 for v in samples) / frames
    warnings = []
    if rms < .003:
        warnings.append('low_energy_review_do_not_drop_by_model_score')
    if clipped > .01:
        warnings.append('clipping_review_do_not_drop_by_model_score')
    return dict(audioSeconds=frames / 16000, rms=rms, clippedFraction=clipped, reviewWarnings=warnings)


def tasks_for(plan, speaker):
    protocol = plan['protocol']
    phrases = protocol['phrases'][speaker['language']]
    tasks = []
    for session_index, session in enumerate(protocol['sessions']):
        prompts = [(phrases['positive'], True, 'isolated_address')] * protocol['positiveTakesPerSession']
        for category in CATEGORIES:
            prompts += [(text, False, category) for text in phrases[category][session_index * 2:session_index * 2 + 2]]
        for number, (text, target, category) in enumerate(prompts, 1):
            identity = f"{speaker['id']}-{session['id']}-{number:02}"
            tasks.append(dict(id=identity, promptId=f"{speaker['language']}-{session['id']}-{number:02}",
                speakerId=speaker['id'], language=speaker['language'], split=speaker['split'],
                sessionId=session['id'], environment=session['environment'], text=text, target=target, category=category))
    return tasks


def init_collection(output, exclude_manifests, protocol_path=PROTOCOL):
    if output.exists():
        raise ValueError('collection destination already exists; never overwrite a plan')
    protocol = read_json(protocol_path)
    if not exclude_manifests:
        raise ValueError('at least one previously inspected corpus manifest is required')
    exclusions, hashes, groups = [], set(), set()
    for path in exclude_manifests:
        old = read_json(path)
        if old.get('schema') != 1 or not old.get('recordings'):
            raise ValueError('invalid previously inspected manifest')
        for record in old['recordings']:
            if not DIGEST.fullmatch(record['sha256']):
                raise ValueError('invalid excluded audio digest')
            hashes.add(record['sha256'])
            groups.add(record['speakerGroup'])
        exclusions.append(dict(path=str(path.resolve()), sha256=digest(path)))
    participants = []
    for language in protocol['languages']:
        for split in SPLITS:
            for _ in range(protocol['speakersPerLanguage'][split]):
                participants.append(dict(id=f'h{len(participants) + 1:03}', language=language, split=split))
    plan = dict(schema=1, experimentId=protocol['experimentId'], protocol=protocol,
        protocolSha256=digest(protocol_path), participants=participants,
        excludedManifests=exclusions, excludedAudioSha256=sorted(hashes), excludedSpeakerGroups=sorted(groups),
        originAuthenticated=False, promotionAllowed=False, automaticCommandWired=False)
    output.mkdir(parents=True)
    path = output / 'collection-plan.json'
    write_json(path, plan)
    plan_hash = digest(path)
    (output / 'plan-sha256.txt').write_text(plan_hash + '\n', encoding='ascii')
    roster = ['# Назначения до записи', '',
        'Один человек — один анонимный номер. Имена и контакты хранить отдельно.', '',
        '| Номер | Язык | Часть | Сессии |', '| --- | --- | --- | --- |']
    for speaker in participants:
        roster.append(f"| {speaker['id']} | {speaker['language']} | {speaker['split']} | s1, s2 |")
    (output / 'roster.md').write_text('\n'.join(roster) + '\n', encoding='utf-8')
    cards = ['# Карточки заданий', '',
        'Каждая строка — отдельный WAV. Человек стоит или сидит на месте.',
        'Произносить естественно. Не обрезать отрицание или контекст.',
        'До записи получить согласие и сверить назначенный номер по roster.md.', '',
        'Сессия s1: тихая комната. Сессия s2: другая обычная комната или другое время.',
        'Пример имени: h001-s1-01.wav. Подставьте назначенный номер участника.']
    for language in protocol['languages']:
        example = next(p for p in participants if p['language'] == language)
        for session in protocol['sessions']:
            cards += ['', f"## {language.upper()}, {session['id']}", '',
                '| Номер фразы | Задание | Метка по протоколу |', '| --- | --- | --- |']
            for task in tasks_for(plan, example):
                if task['sessionId'] == session['id']:
                    label = 'обращение' if task['target'] else 'отрицательная фраза'
                    cards.append(f"| {task['id'].split('-')[-1]} | {task['text']} | {label} |")
    (output / 'participant-cards.md').write_text('\n'.join(cards) + '\n', encoding='utf-8')
    guide = Path(__file__).with_name('HUMAN_COLLECTION.md').read_text(encoding='utf-8')
    (output / 'START_HERE.md').write_text(guide.replace('output/kws-human-pilot', output.parent.as_posix()), encoding='utf-8')
    for speaker in participants:
        tasks = tasks_for(plan, speaker)
        for session in protocol['sessions']:
            selected = [task for task in tasks if task['sessionId'] == session['id']]
            template = dict(schema=1, collectionPlanSha256=plan_hash,
                captureId=f"{plan['experimentId']}-{speaker['id']}-{session['id']}",
                consentConfirmed=False, humanRecordingConfirmed=False, speakerNoveltyConfirmed=False,
                deviceId='', recordings=[dict(id=task['id'], wav=f"wav/{task['id']}.wav",
                    speakerId=task['speakerId'], sessionId=task['sessionId'], language=task['language'],
                    promptId=task['promptId'], target=task['target'], textPrompt=task['text'],
                    transcript='', groundTruthConfirmed=False, sha256='') for task in selected])
            write_json(output / 'templates' / speaker['id'] / session['id'] / 'manifest.json', template)
    return path, plan_hash


def load_plan(path, expected_sha256):
    if not DIGEST.fullmatch(expected_sha256) or digest(path) != expected_sha256:
        raise ValueError('selected collection plan SHA-256 mismatch')
    plan = read_json(path)
    if (plan.get('schema') != 1 or plan.get('promotionAllowed') is not False or
            plan.get('automaticCommandWired') is not False):
        raise ValueError('invalid collection plan')
    people = plan['participants']
    if len({p['id'] for p in people}) != len(people):
        raise ValueError('duplicate participant identity across splits')
    for person in people:
        if (not IDENTITY.fullmatch(person['id']) or person['language'] not in ('ru', 'kk', 'en') or
                person['split'] not in SPLITS):
            raise ValueError('invalid preregistered participant')
    return plan


def task_index(plan):
    return {task['id']: task for person in plan['participants'] for task in tasks_for(plan, person)}


def checked_record(record, task, path, plan):
    for field in ('id', 'speakerId', 'sessionId', 'language', 'promptId', 'target'):
        if type(record.get(field)) is not type(task[field]) or record[field] != task[field]:
            raise ValueError(f'recording differs from preregistered {field}')
    if record.get('groundTruthConfirmed') is not True:
        raise ValueError('ground truth must be explicitly confirmed after listening')
    value = record.get('sha256', '')
    if not DIGEST.fullmatch(value) or digest(path) != value:
        raise ValueError('selected recording SHA-256 mismatch')
    if value in plan['excludedAudioSha256'] or 'human-' + task['speakerId'] in plan['excludedSpeakerGroups']:
        raise ValueError('previously inspected audio or speaker cannot enter the fresh collection')
    info = audio_info(path)
    return dict(id=task['id'], wav=f"wav/{task['id']}.wav", target=task['target'],
        language=task['language'], speakerId=task['speakerId'], speakerGroup='human-' + task['speakerId'],
        split=task['split'], sessionId=task['sessionId'], promptId=task['promptId'], category=task['category'],
        environment=task['environment'], origin='human_consented', consentConfirmed=True,
        groundTruthConfirmed=True, sha256=value, **info)


def load_records(plan, plan_hash, data_root):
    tasks = task_index(plan)
    records, ids, hashes, captures = [], set(), set(), set()
    batches = data_root / 'batches'
    if not batches.exists():
        return records
    for batch in sorted(batches.iterdir()):
        if not batch.is_dir() or batch.is_symlink():
            raise ValueError('unexpected collection batch entry')
        metadata = read_json(batch / 'manifest.json')
        capture = metadata.get('captureId')
        if (metadata.get('schema') != 1 or metadata.get('collectionPlanSha256') != plan_hash or
                capture != batch.name or capture in captures):
            raise ValueError('batch capture identity or collection plan mismatch')
        captures.add(capture)
        for field in ('consentConfirmed', 'humanRecordingConfirmed', 'speakerNoveltyConfirmed'):
            if metadata.get(field) is not True:
                raise ValueError(f'batch {field} assertion required')
        if not isinstance(metadata.get('deviceId'), str) or not metadata['deviceId'].strip():
            raise ValueError('anonymous device ID required')
        if not metadata.get('recordings'):
            raise ValueError('empty imported batch')
        for record in metadata['recordings']:
            task = tasks.get(record.get('id'))
            if task is None:
                raise ValueError('unknown collection recording')
            path = selected_path(batch, record['wav'])
            checked = checked_record(record, task, path, plan)
            for field in ('split', 'speakerGroup', 'origin', 'category', 'environment', 'consentConfirmed'):
                if record.get(field) != checked[field]:
                    raise ValueError(f'imported recording {field} changed')
            if record['id'] in ids or record['sha256'] in hashes:
                raise ValueError('duplicate recording identity or audio across collection batches')
            ids.add(record['id']); hashes.add(record['sha256'])
            records.append(dict(checked, captureId=capture, deviceId=metadata['deviceId'], _source=path))
    return records


def import_batch(plan_path, plan_hash, source_manifest, recording_root, data_root, expected_capture_id):
    plan = load_plan(plan_path, plan_hash)
    existing = load_records(plan, plan_hash, data_root)
    source = read_json(source_manifest)
    if (not IDENTITY.fullmatch(expected_capture_id) or source.get('captureId') != expected_capture_id or
            source.get('collectionPlanSha256') != plan_hash or source.get('schema') != 1):
        raise ValueError('selected capture ID or collection plan mismatch')
    for field in ('consentConfirmed', 'humanRecordingConfirmed', 'speakerNoveltyConfirmed'):
        if source.get(field) is not True:
            raise ValueError(f'explicit {field} assertion required')
    if not isinstance(source.get('deviceId'), str) or not source['deviceId'].strip():
        raise ValueError('anonymous device ID required')
    destination = data_root / 'batches' / expected_capture_id
    if destination.exists():
        raise ValueError('capture destination exists; never overwrite imported data')
    tasks = task_index(plan)
    ids = {r['id'] for r in existing}; hashes = {r['sha256'] for r in existing}
    imported, originals = [], []
    for record in source['recordings']:
        task = tasks.get(record.get('id'))
        if task is None:
            raise ValueError('unknown preregistered recording')
        if not isinstance(record.get('transcript'), str) or not record['transcript'].strip():
            raise ValueError('human reviewed transcript required')
        original = selected_path(recording_root, record['wav'])
        checked = checked_record(record, task, original, plan)
        if checked['id'] in ids or checked['sha256'] in hashes:
            raise ValueError('duplicate recording identity or audio')
        ids.add(checked['id']); hashes.add(checked['sha256'])
        imported.append(checked); originals.append(original)
    if not imported:
        raise ValueError('empty selected capture batch')
    if len({(r['speakerId'], r['sessionId']) for r in imported}) != 1:
        raise ValueError('one selected capture must contain one participant session')
    metadata = dict(schema=1, collectionPlanSha256=plan_hash, captureId=expected_capture_id,
        sourceManifestSha256=digest(source_manifest), consentConfirmed=True, humanRecordingConfirmed=True,
        speakerNoveltyConfirmed=True, deviceId=source['deviceId'].strip(), originAuthenticated=False,
        evidence='human_origin_consent_identity_and_labels_asserted_by_supplier', recordings=imported)
    # All source and existing data are checked before any destination is created.
    data_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.import-', dir=data_root) as temporary:
        staged = Path(temporary) / 'batch'
        staged.mkdir()
        for record, original in zip(imported, originals):
            target = staged / record['wav']; target.parent.mkdir(exist_ok=True)
            shutil.copyfile(original, target)
            if digest(target) != record['sha256']:
                raise ValueError('recording changed while copying')
        write_json(staged / 'manifest.json', metadata)
        destination.parent.mkdir(exist_ok=True)
        staged.rename(destination)
    return destination / 'manifest.json'


def audit_collection(plan_path, plan_hash, data_root):
    plan = load_plan(plan_path, plan_hash)
    tasks = task_index(plan)
    records = load_records(plan, plan_hash, data_root)
    seen = {r['id'] for r in records}
    coverage = {}
    for split in SPLITS:
        coverage[split] = {}
        for language in plan['protocol']['languages']:
            expected = [t for t in tasks.values() if t['split'] == split and t['language'] == language]
            accepted = [r for r in records if r['split'] == split and r['language'] == language]
            coverage[split][language] = dict(expectedClips=len(expected), importedClips=len(accepted),
                expectedSpeakers=len({t['speakerId'] for t in expected}),
                importedSpeakers=len({r['speakerId'] for r in accepted}),
                positiveClips=sum(r['target'] for r in accepted), negativeClips=sum(not r['target'] for r in accepted),
                negativeCategories=dict(Counter(r['category'] for r in accepted if not r['target'])),
                missingClips=sum(t['id'] not in seen for t in expected))
    def complete(splits):
        return all(v['missingClips'] == 0 for s in splits for v in coverage[s].values())
    return dict(schema=1, experimentId=plan['experimentId'], collectionPlanSha256=plan_hash,
        scope='data_coverage_and_integrity_not_model_or_device_acceptance', coverage=coverage,
        expectedClips=len(tasks), importedClips=len(records), humanPositiveClips=sum(r['target'] for r in records),
        signalReviewWarningClips=sum(bool(r['reviewWarnings']) for r in records),
        collectionStatus='not_run' if not records else 'complete_supplier_asserted' if complete(SPLITS) else 'partial',
        readyForModelDevelopment=complete(('train', 'dev')), completeFreshCollection=complete(SPLITS),
        originAuthenticated=False, humanModelEvaluation='not_run', modelTraining='not_run',
        continuousListening='not_run', androidValidation='not_run', promotionAllowed=False, automaticCommandWired=False)


def export_corpus(plan_path, plan_hash, data_root, output, role, candidate_policy=None, development_manifest=None):
    if role not in ('development', 'holdout'):
        raise ValueError('unknown corpus export role')
    plan = load_plan(plan_path, plan_hash)
    status = audit_collection(plan_path, plan_hash, data_root)
    if output.exists():
        raise ValueError('export destination exists; never overwrite a frozen corpus')
    if not status['readyForModelDevelopment']:
        raise ValueError('complete train/dev collection required before export')
    release = None
    if role == 'holdout':
        if not status['completeFreshCollection'] or candidate_policy is None or development_manifest is None:
            raise ValueError('complete fresh collection and frozen candidate/development manifest required')
        policy = read_json(candidate_policy)
        development = read_json(development_manifest)
        model_path = selected_path(candidate_policy.parent, policy['modelFile'])
        threshold = policy.get('threshold')
        if (development.get('collectionPlanSha256') != plan_hash or development.get('role') != 'development' or
                policy.get('experimentId') != plan['experimentId'] or
                policy.get('corpusSha256') != digest(development_manifest) or policy.get('modelSha256') != digest(model_path) or
                policy.get('selectionSplit') != 'dev' or policy.get('selectionFeasible') is not True or
                policy.get('promotionAllowed') is not False or type(threshold) not in (float, int) or
                not math.isfinite(threshold) or not 0 <= threshold <= 1):
            raise ValueError('frozen candidate must bind this development corpus, model and feasible dev policy')
        # Recreate the expected development rows to reject a hash-bound but wrongly mixed manifest.
        expected = {r['id']: r['sha256'] for r in load_records(plan, plan_hash, data_root) if r['split'] != 'test'}
        actual = development.get('recordings', [])
        if (len(actual) != len(expected) or {r['id']: r['sha256'] for r in actual} != expected or
                any(r['split'] != task_index(plan)[r['id']]['split'] for r in actual)):
            raise ValueError('development corpus must contain only the planned train/dev records')
        for record in actual:
            checked = checked_record(record, task_index(plan)[record['id']],
                selected_path(development_manifest.parent, record['wav']), plan)
            if any(record.get(field) != checked[field] for field in ('speakerGroup', 'origin', 'consentConfirmed')):
                raise ValueError('frozen development recording metadata mismatch')
        release = dict(frozenPolicySha256=digest(candidate_policy), modelSha256=policy['modelSha256'],
            developmentManifestSha256=digest(development_manifest), threshold=threshold,
            holdoutIsConsumedForThisCandidateOnEvaluation=True, blindedExternalEvaluation=False)
    chosen = [r for r in load_records(plan, plan_hash, data_root)
        if (r['split'] == 'test') == (role == 'holdout')]
    with tempfile.TemporaryDirectory(prefix='bagdar-export-') as temporary:
        staged = Path(temporary) / 'corpus'; staged.mkdir()
        exported = []
        for record in chosen:
            row = {k: v for k, v in record.items() if k != '_source'}
            target = staged / row['wav']; target.parent.mkdir(exist_ok=True)
            shutil.copyfile(record['_source'], target)
            if digest(target) != row['sha256']:
                raise ValueError('recording changed during export')
            exported.append(row)
        write_json(staged / 'manifest.json', dict(schema=1, experimentId=plan['experimentId'],
            collectionPlanSha256=plan_hash, role=role, release=release,
            evidence='human_origin_consent_identity_and_labels_asserted_by_supplier',
            originAuthenticated=False, promotionAllowed=False, recordings=exported))
        output.parent.mkdir(parents=True, exist_ok=True)
        # copytree refuses existing destinations; rename is not guaranteed across volumes.
        shutil.copytree(staged, output)
    return output / 'manifest.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    init = commands.add_parser('init')
    init.add_argument('--output', type=Path, required=True)
    init.add_argument('--exclude-manifest', type=Path, action='append', required=True)
    for command in ('import', 'audit', 'export'):
        item = commands.add_parser(command)
        item.add_argument('--plan', type=Path, required=True)
        item.add_argument('--expected-plan-sha256', required=True)
        item.add_argument('--data-root', type=Path, required=True)
        if command == 'import':
            item.add_argument('--manifest', type=Path, required=True)
            item.add_argument('--recording-root', type=Path, required=True)
            item.add_argument('--expected-capture-id', required=True)
        if command == 'audit':
            item.add_argument('--report', type=Path, required=True)
        if command == 'export':
            item.add_argument('--output', type=Path, required=True)
            item.add_argument('--role', choices=('development', 'holdout'), required=True)
            item.add_argument('--candidate-policy', type=Path)
            item.add_argument('--development-manifest', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'init':
            path, plan_hash = init_collection(args.output, args.exclude_manifest)
            print(json.dumps(dict(plan=str(path), planSha256=plan_hash, collectionStatus='not_run')))
        elif args.command == 'import':
            print(import_batch(args.plan, args.expected_plan_sha256, args.manifest,
                args.recording_root, args.data_root, args.expected_capture_id))
        elif args.command == 'audit':
            result = audit_collection(args.plan, args.expected_plan_sha256, args.data_root)
            write_json(args.report, result)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0 if result['completeFreshCollection'] else 2
        else:
            print(export_corpus(args.plan, args.expected_plan_sha256, args.data_root, args.output,
                args.role, args.candidate_policy, args.development_manifest))
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f'Collection refused: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
