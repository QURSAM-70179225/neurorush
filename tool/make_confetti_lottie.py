#!/usr/bin/env python3
"""Generates assets/lottie/confetti.json: a Bodymovin/Lottie confetti burst.

Pieces burst upward from the bottom centre, then flutter down while spinning
and fading. Deterministic (seeded) so the file is reproducible.
"""
import json
import math
import random
from pathlib import Path

W, H, FPS, FRAMES, PIECES = 400, 700, 60, 150, 70
COLORS = [(108, 77, 255), (255, 77, 157), (34, 199, 238), (255, 176, 32), (46, 211, 160)]
EASE_OUT = {"o": {"x": [0.2], "y": [0.8]}, "i": {"x": [0.4], "y": [1]}}
EASE_IN = {"o": {"x": [0.5], "y": [0]}, "i": {"x": [0.8], "y": [1]}}
LINEAR = {"o": {"x": [0], "y": [0]}, "i": {"x": [1], "y": [1]}}


def kf(t, value, ease=None):
    """A keyframe. Every keyframe but the last needs easing handles, so
    linear easing is the default; [finish] strips it from the final one."""
    k = {"t": t, "s": value}
    k.update(ease or LINEAR)
    return k


def finish(frames):
    last = dict(frames[-1])
    last.pop("i", None)
    last.pop("o", None)
    return frames[:-1] + [last]


def piece(i, rnd):
    angle = math.radians(rnd.uniform(-75, 75) - 90)  # mostly upward
    speed = rnd.uniform(260, 520)
    x0, y0 = W / 2 + rnd.uniform(-30, 30), H - 60
    peak_t = rnd.randint(28, 42)
    px = x0 + math.cos(angle) * speed
    py = max(30, y0 + math.sin(angle) * speed)
    end_x = px + rnd.uniform(-60, 60)
    end_y = H + 40
    start = rnd.randint(0, 8)
    rgb = [c / 255 for c in rnd.choice(COLORS)] + [1]
    w, h = rnd.choice([(10, 16), (8, 8), (6, 18), (12, 12)])
    spin = rnd.choice([-1, 1]) * rnd.uniform(360, 900)
    return {
        "ddd": 0,
        "ind": i + 1,
        "ty": 4,
        "nm": f"piece{i}",
        "sr": 1,
        "ip": start,
        "op": FRAMES,
        "st": 0,
        "bm": 0,
        "ks": {
            "o": {"a": 1, "k": finish([kf(start, [100]), kf(FRAMES - 25, [100]), kf(FRAMES, [0])])},
            "r": {"a": 1, "k": finish([kf(start, [0]), kf(FRAMES, [spin])])},
            "p": {"a": 1, "k": finish([
                kf(start, [x0, y0, 0], EASE_OUT),
                kf(start + peak_t, [px, py, 0], EASE_IN),
                kf(FRAMES, [end_x, end_y, 0]),
            ])},
            "a": {"a": 0, "k": [0, 0, 0]},
            # Flutter-style "flutter": squash the piece vertically as it spins.
            "s": {"a": 1, "k": finish([kf(start, [100, 100, 100]), kf(start + 20, [100, 30, 100]), kf(start + 40, [100, 100, 100]),
                                        kf(start + 60, [100, 30, 100]), kf(FRAMES, [100, 100, 100])])},
        },
        "ao": 0,
        "shapes": [{
            "ty": "gr",
            "nm": "rect",
            "it": [
                {"ty": "rc", "nm": "r", "d": 1, "s": {"a": 0, "k": [w, h]}, "p": {"a": 0, "k": [0, 0]}, "r": {"a": 0, "k": 2}},
                {"ty": "fl", "nm": "f", "c": {"a": 0, "k": rgb}, "o": {"a": 0, "k": 100}, "r": 1},
                {"ty": "tr", "p": {"a": 0, "k": [0, 0]}, "a": {"a": 0, "k": [0, 0]}, "s": {"a": 0, "k": [100, 100]},
                 "r": {"a": 0, "k": 0}, "o": {"a": 0, "k": 100}, "sk": {"a": 0, "k": 0}, "sa": {"a": 0, "k": 0}},
            ],
        }],
    }


def main():
    rnd = random.Random(42)
    data = {
        "v": "5.7.4", "fr": FPS, "ip": 0, "op": FRAMES, "w": W, "h": H, "nm": "NeuroRush confetti", "ddd": 0,
        "assets": [], "layers": [piece(i, rnd) for i in range(PIECES)],
    }
    out = Path(__file__).resolve().parent.parent / "assets" / "lottie" / "confetti.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, separators=(",", ":")))
    print(f"Wrote {out} ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
