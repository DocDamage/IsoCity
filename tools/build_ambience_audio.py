"""Build IsoCity's original ambient loops without external recordings."""
from array import array
from pathlib import Path
import json
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050
SECONDS = 8
LENGTH = RATE * SECONDS
BLEND = RATE // 5
KINDS = ('traffic', 'fountain', 'birds', 'shop', 'interior',
         'school', 'arcade', 'workshop', 'market', 'harbor')


def swell(time, start, duration):
    progress = (time - start) / duration
    return math.sin(math.pi * progress) ** 2 if 0 < progress < 1 else 0


def strike(time, onsets, frequencies, damping):
    value = 0.0
    for start in onsets:
        age = time - start
        if 0 <= age < 1.1:
            shape = min(1, age * 500) * math.exp(-age * damping)
            value += shape * sum(math.sin(math.tau * age * hz) / (index + 1)
                                 for index, hz in enumerate(frequencies))
    return value


def voices(time, noise, *, school):
    value = .12 * noise
    for voice in range(4 if school else 6):
        frequency = (140 if school else 97) + voice * 19
        envelope = max(0, math.sin(time * (2.45 + .49 * voice) + voice * 1.6)) ** 2
        phase = math.tau * frequency * time + .33 * math.sin(time * (9 + voice))
        value += .026 * envelope * (math.sin(phase) + .28 * math.sin(phase * 2.3))
    return value


def synthesize(kind):
    rng = random.Random(19871 + KINDS.index(kind))
    events = []
    if kind == 'birds':
        for i in range(11):
            start = 0.25 + i * 0.67 + rng.random() * 0.2
            events.append((start, rng.uniform(0.14, 0.34), rng.uniform(1900, 3600), rng.uniform(-900, 1300)))
    values = array('d')
    slow = medium = 0.0
    for index in range(LENGTH + BLEND):
        t = index / RATE
        noise = rng.uniform(-1, 1)
        slow += 0.012 * (noise - slow)
        medium += 0.13 * (noise - medium)
        if kind == 'traffic':
            passing = 0.23 + 0.77 * math.sin(math.pi * t / 4.7) ** 6
            engine = math.sin(2 * math.pi * (61 * t + 0.6 * math.sin(t * 0.7)))
            value = passing * (0.11 * engine + 0.045 * math.sin(2 * math.pi * 123 * t) + 0.7 * slow + 0.13 * medium)
        elif kind == 'fountain':
            splash = 0.7 + 0.15 * math.sin(t * 3.1) + 0.1 * math.sin(t * 11.9)
            value = splash * (0.4 * medium + 0.12 * noise) + 0.4 * slow
        elif kind == 'birds':
            value = 0.025 * slow
            for start, duration, frequency, bend in events:
                u = (t - start) / duration
                if 0 < u < 1:
                    envelope = math.sin(math.pi * u) ** 2
                    phase = 2 * math.pi * (frequency * duration * u + 0.5 * bend * duration * u * u)
                    value += 0.32 * envelope * math.sin(phase + 0.45 * math.sin(u * 24))
        elif kind == 'shop':
            # Filtered, overlapping formants suggest indistinct conversation;
            # these are oscillators, not speech samples or recognizable words.
            value = 0.1 * slow
            for voice in range(4):
                syllable = max(0, math.sin(t * (3.2 + voice * 0.41) + voice * 2.1)) ** 2
                frequency = 105 + voice * 28
                formant = math.sin(2 * math.pi * frequency * t + 0.4 * math.sin(t * 9))
                formant += 0.3 * math.sin(2 * math.pi * frequency * 2.7 * t)
                value += 0.035 * syllable * formant
            bell = math.exp(-max(0, t - 4.3) * 9) if 4.3 <= t <= 5.1 else 0
            value += 0.025 * bell * (math.sin(t * 2 * math.pi * 1648) + 0.3 * math.sin(t * 2 * math.pi * 2472))
        elif kind == 'interior':
            value = 0.16 * slow + 0.01 * medium + 0.018 * math.sin(2 * math.pi * 90 * t) + 0.006 * math.sin(2 * math.pi * 180 * t)
        elif kind in ('school', 'market'):
            value = voices(t, slow, school=kind == 'school')
            if kind == 'school':
                page = swell(t, 1.6, .55) + swell(t, 5.5, .46)
                value += page * (.10 * medium + .015 * noise)
                value += strike(t, (2.4, 6.6), (372, 708), 16) * .045
            else:
                value += strike(t, (1.3, 3.9, 6.7), (184, 390, 678), 9) * .06
        elif kind == 'arcade':
            value = .08 * slow
            for start, notes in ((.45, (330, 440, 587)), (2.6, (392, 523)), (5.0, (587, 440, 698)), (7.1, (494, 660))):
                for note_index, frequency in enumerate(notes):
                    age = t - start - .14 * note_index
                    if 0 <= age <= .12:
                        carrier = math.sin(math.tau * frequency * age)
                        value += .085 * swell(age, 0, .12) * (carrier + .19 * math.sin(math.tau * 3 * frequency * age))
        elif kind == 'workshop':
            value = .17 * slow + .018 * math.sin(math.tau * 78 * t)
            value += .13 * strike(t, (.72, 1.12, 2.83, 3.25, 4.9, 6.1, 6.52), (539, 918, 1401, 2019), 6)
            value += swell(t, 3.9, .65) * medium * .22
        else:  # Harbor wash and dock creak, without a boat motor.
            wash = .24 + .72 * math.sin(math.pi * t / 2.65) ** 6
            value = wash * (.56 * slow + .32 * medium + .05 * noise)
            for start in (2.0, 5.9):
                creak = swell(t, start, .6)
                age = t - start
                value += .07 * creak * math.sin(math.tau * (177 * age + 47 * age * age))
        values.append(value)
    for index in range(BLEND):
        alpha = index / BLEND
        values[index] = values[index] * alpha + values[LENGTH + index] * (1 - alpha)
    values = values[:LENGTH]
    mean = sum(values) / LENGTH
    values = array('d', (value - mean for value in values))
    rms = math.sqrt(sum(value * value for value in values) / LENGTH)
    peak = max(abs(value) for value in values)
    target = 0.035 if kind == 'birds' else 0.07
    scale = min(target / rms, 0.65 / peak)
    pcm = [round(value * scale * 32767) for value in values]
    return struct.pack('<' + 'h' * len(pcm), *pcm), {
        'seconds': SECONDS, 'sample_rate': RATE, 'channels': 1,
        'rms': round(rms * scale, 6), 'peak': round(peak * scale, 6),
        'loop_seam_step': abs(pcm[0] - pcm[-1]) / 32768,
    }


def main():
    destination = ROOT / 'assets' / 'audio'
    destination.mkdir(parents=True, exist_ok=True)
    manifest = {'source': 'Original procedural synthesis; no third-party recordings or samples.', 'loops': {}}
    for kind in KINDS:
        data, metrics = synthesize(kind)
        with wave.open(str(destination / f'{kind}.wav'), 'wb') as output:
            output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
            output.writeframes(data)
        manifest['loops'][kind] = metrics
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
