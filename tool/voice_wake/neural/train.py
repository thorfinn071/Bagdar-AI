"""Train once on train/dev only, export builtin TFLite and freeze a dev-only policy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time

os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
import numpy as np
import tensorflow as tf

from corpus import audit, read_pcm, sha256
from features import prepare_window, augment, log_mel

ROOT = Path(__file__).parent
def configure(seed):
    tf.config.threading.set_intra_op_parallelism_threads(4)
    tf.config.threading.set_inter_op_parallelism_threads(1)
    tf.keras.utils.set_random_seed(seed)
    tf.config.experimental.enable_op_determinism()

def make_model():
    inputs = tf.keras.Input((198, 40, 1), name='log_mel')
    x = tf.keras.layers.Conv2D(16, (5, 3), strides=(2, 2), padding='same', activation='relu')(inputs)
    x = tf.keras.layers.SeparableConv2D(32, (5, 3), strides=(2, 2), padding='same', activation='relu')(x)
    x = tf.keras.layers.SeparableConv2D(64, (5, 3), strides=(2, 2), padding='same', activation='relu')(x)
    x = tf.keras.layers.AveragePooling2D((1, 5))(x)
    x = tf.keras.layers.Flatten()(x)
    x = tf.keras.layers.Dense(32, activation='relu', kernel_regularizer=tf.keras.regularizers.l2(.001))(x)
    x = tf.keras.layers.Dropout(.2)(x)
    return tf.keras.Model(inputs, tf.keras.layers.Dense(1, activation='sigmoid', name='wake_score')(x))

def load_records(manifest, records):
    prepared = []
    for record in records:
        signal, _ = read_pcm(manifest.parent / record['wav'], expected_rate=16000)
        window, eligible = prepare_window(signal)
        prepared.append((record, signal, window, eligible))
    return prepared

def build_training(prepared, count, seed):
    rng = np.random.default_rng(seed)
    pools = {label: [item for item in prepared if item[0]['target'] == bool(label) and item[3]] for label in [0, 1]}
    if not all(pools.values()):
        raise ValueError('missing eligible training class')
    # Keep hard synthetic negatives represented despite many easy public digits.
    hard_negatives = [item for item in pools[0] if item[0]['origin'] == 'synthetic_piper']
    features, labels, parents = [], [], []
    batch = []
    attempts = 0
    for label in [0, 1]:
        accepted = 0
        while accepted < count:
            attempts += 1
            if attempts > count * 30:
                raise ValueError('augmentation cannot produce enough eligible samples')
            pool = hard_negatives if label == 0 and accepted % 2 == 0 else pools[label]
            record, signal, _, _ = pool[int(rng.integers(len(pool)))]
            sample_seed = int(rng.integers(2**31))
            sample_rng = np.random.default_rng(sample_seed)
            window, eligible = prepare_window(augment(signal, sample_rng), jitter=int(sample_rng.integers(-1600, 1601)))
            if not eligible:
                continue
            batch.append(window); labels.append(label)
            parents.append({'sourceId': record['id'], 'seed': sample_seed, 'target': bool(label)})
            accepted += 1
            if len(batch) == 64:
                features.append(log_mel(np.stack(batch)).numpy()); batch = []
    if batch:
        features.append(log_mel(np.stack(batch)).numpy())
    return np.concatenate(features), np.array(labels, np.float32), parents

def choose_threshold(records, scores, eligible, grid):
    if any(record['split'] != 'dev' for record in records):
        raise ValueError('threshold selection must use dev only')
    rows = []
    for threshold in grid:
        per_language = {}
        for language in ['ru', 'kk', 'en']:
            positions = [i for i, record in enumerate(records) if record['language'] == language]
            positive = [i for i in positions if records[i]['target']]
            negative = [i for i in positions if not records[i]['target']]
            hits = sum(bool(eligible[i] and scores[i] >= threshold) for i in positive)
            false = sum(bool(eligible[i] and scores[i] >= threshold) for i in negative)
            per_language[language] = {'positives': len(positive), 'hits': hits, 'negatives': len(negative), 'falseActivations': false}
        feasible = all(v['positives'] > 0 and v['hits'] / v['positives'] >= .9 and v['falseActivations'] == 0 for v in per_language.values())
        rows.append({'threshold': threshold, 'feasible': feasible, 'languages': per_language})
    feasible = [row for row in rows if row['feasible']]
    return {'threshold': feasible[0]['threshold'] if feasible else .9,
            'selectionFeasible': bool(feasible), 'selectionSplit': 'dev',
            'selectionRule': 'lowest_grid_threshold_with_zero_dev_false_and_90pct_recall_each_language_else_fixed_diagnostic_0.9',
            'gridResults': rows}

class RawModule(tf.Module):
    def __init__(self, model):
        super().__init__(); self.model = model
    @tf.function(input_signature=[tf.TensorSpec([1, 32000], tf.float32, name='canonical_waveform')])
    def infer(self, waveform):
        return {'wake_score': self.model(log_mel(waveform), training=False)}

def export(model, destination):
    from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2
    wrapper = RawModule(model)
    # Keras 3 variables captured by a tf.Module are not reliably initialized by
    # this converter path. Freeze learned weights as constants, and reject all
    # resource-variable operations instead of shipping a constant-0.5 classifier.
    frozen = convert_variables_to_constants_v2(wrapper.infer.get_concrete_function())
    converter = tf.lite.TFLiteConverter.from_concrete_functions([frozen])
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    data = converter.convert()
    destination.write_bytes(data)
    interpreter = tf.lite.Interpreter(model_path=str(destination), num_threads=1)
    interpreter.allocate_tensors()
    operations = sorted({op['op_name'] for op in interpreter._get_ops_details()})
    if any('Flex' in name or name in ['CUSTOM', 'VAR_HANDLE', 'READ_VARIABLE'] for name in operations):
        raise ValueError('export requires custom/Flex operators or uninitialized variables')
    return interpreter, operations

def score(interpreter, windows):
    input_index = interpreter.get_input_details()[0]['index']
    output_index = interpreter.get_output_details()[0]['index']
    values, timings = [], []
    for window in windows:
        interpreter.set_tensor(input_index, window[None].astype(np.float32))
        before = time.perf_counter(); interpreter.invoke(); timings.append((time.perf_counter() - before) * 1000)
        value = float(interpreter.get_tensor(output_index).reshape(-1)[0])
        if not np.isfinite(value) or not 0 <= value <= 1:
            raise ValueError('invalid model output')
        values.append(value)
    return np.array(values), timings

def train(manifest, output, resume_export=False):
    protocol = json.loads((ROOT / 'protocol.json').read_text(encoding='utf-8'))
    configure(protocol['seed'])
    metadata = audit(manifest)
    if metadata['protocolSha256'] != sha256(ROOT / 'protocol.json'):
        raise ValueError('corpus/protocol mismatch')
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'frozen-policy.json').exists():
        raise ValueError('candidate already frozen; do not retrain after holdout inspection')
    records = metadata['recordings']
    training = [record for record in records if record['split'] == 'train']
    dev_records = [record for record in records if record['split'] == 'dev']
    # No test/legacy waveform is loaded for feature extraction or model selection.
    dev = load_records(manifest, dev_records)
    dev_windows = np.stack([item[2] for item in dev])
    dev_eligible = np.array([item[3] for item in dev])
    dev_x = log_mel(dev_windows).numpy()
    dev_y = np.array([record['target'] for record in dev_records], np.float32)
    if resume_export:
        report = json.loads((output / 'training.json').read_text())
        if report['corpusSha256'] != sha256(manifest) or report['protocolSha256'] != sha256(ROOT / 'protocol.json'):
            raise ValueError('cannot resume export with changed data')
        model = tf.keras.models.load_model(output / 'classifier.keras')
    else:
        if (output / 'classifier.keras').exists():
            raise ValueError('checkpoint exists; use --resume-export without changing learned weights')
        prepared = load_records(manifest, training)
        x, y, parents = build_training(prepared, protocol['trainingExamplesPerClass'], protocol['seed'])
        (output / 'augmentation-parents.json').write_text(json.dumps(parents, indent=2), encoding='utf-8')
        model = make_model()
        model.compile(optimizer=tf.keras.optimizers.Adam(protocol['learningRate']), loss='binary_crossentropy', metrics=['accuracy'])
        options = tf.data.Options(); options.threading.private_threadpool_size = 1
        dataset = tf.data.Dataset.from_tensor_slices((x, y)).shuffle(len(y), seed=protocol['seed']).batch(protocol['batchSize']).with_options(options)
        dev_dataset = tf.data.Dataset.from_tensor_slices((dev_x, dev_y)).batch(protocol['batchSize']).with_options(options)
        start = time.perf_counter()
        history = model.fit(dataset, epochs=protocol['epochs'], validation_data=dev_dataset,
            callbacks=[tf.keras.callbacks.EarlyStopping(monitor='val_loss', patience=5, restore_best_weights=True)], verbose=2)
        model.save(output / 'classifier.keras')
        report = dict(schema=1, corpusSha256=sha256(manifest), protocolSha256=sha256(ROOT / 'protocol.json'),
            seed=protocol['seed'], parameters=model.count_params(), trainingExamples=len(y),
            eligibleTrainSources=sum(item[3] for item in prepared), trainSources=len(prepared), devSources=len(dev),
            trainerSha256=sha256(ROOT / 'train.py'), featuresSha256=sha256(ROOT / 'features.py'),
            wallSeconds=time.perf_counter() - start, history=history.history, selectionSplit='dev', testFeaturesRead=False)
        (output / 'training.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    interpreter, operations = export(model, output / 'bagdar-kws-f32.tflite')
    tflite_scores, timings = score(interpreter, dev_windows)
    tf_scores = model(dev_x, training=False).numpy().reshape(-1)
    maximum_error = float(np.max(np.abs(tf_scores - tflite_scores)))
    if maximum_error > .0005:
        raise ValueError(f'export parity failed: {maximum_error}')
    policy = choose_threshold(dev_records, tflite_scores, dev_eligible, protocol['thresholdGrid'])
    policy.update(schema=1, experimentId=protocol['experimentId'], modelSha256=sha256(output / 'bagdar-kws-f32.tflite'),
        checkpointSha256=sha256(output / 'classifier.keras'), exporterSha256=sha256(ROOT / 'train.py'),
        corpusSha256=sha256(manifest), protocolSha256=sha256(ROOT / 'protocol.json'),
        modelFile='bagdar-kws-f32.tflite', sourceEvidence=protocol['corpusEvidence'],
        preprocessing='reference_energy_gate_rms_normalization_centered_pcm_then_embedded_stft_logmel_cnn',
        sampleRate=16000, inputShape=[1, 32000], inputDtype='float32', outputShape=[1, 1],
        promotionAllowed=False, automaticCommandWired=False, androidAcceptance='not_run', humanPositiveEvidence='not_available')
    parity = {'maximumScoreAbsoluteError': maximum_error, 'devCases': len(dev), 'operations': operations,
        'decisionDisagreements': int(np.sum((tf_scores >= policy['threshold']) != (tflite_scores >= policy['threshold']))),
        'desktopInvocationMsP50': float(np.quantile(timings, .5)), 'desktopInvocationMsP95': float(np.quantile(timings, .95))}
    if parity['decisionDisagreements']:
        raise ValueError('export changes threshold decisions on dev')
    (output / 'parity.json').write_text(json.dumps(parity, indent=2), encoding='utf-8')
    (output / 'frozen-policy.json').write_text(json.dumps(policy, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'frozen': True, 'modelBytes': (output / 'bagdar-kws-f32.tflite').stat().st_size,
        'parameters': report['parameters'], 'selectionFeasible': policy['selectionFeasible'], 'threshold': policy['threshold'], 'parity': parity}, indent=2), flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--resume-export', action='store_true')
    args = parser.parse_args(); train(args.manifest, args.output, args.resume_export)
