"""Render the existing code-native rim light into a Terminal background GIF.

The original illustration is a fixed input, never regenerated or overwritten.
Only the original illustration's outer frame receives travelling lights.
No inner frame or additional corner ornaments are drawn.
Requires Python, Pillow and numpy. Run from any working directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "themes/windows-terminal/assets"


def build(source: Path, output: Path, report: Path, frames: int = 200) -> None:
    if frames < 8:
        raise ValueError("At least eight animation frames are required")
    if source.resolve() == output.resolve():
        raise ValueError("The original illustration must not be overwritten")
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    illustration = Image.open(source).convert("RGB")
    width, height = illustration.size
    original = np.asarray(illustration)

    # Follow the existing illustration's outside border, away from the old
    # inner frame. Do not add a second frame or superimposed corner ornaments.
    left, right = width * .007, width * .993
    top, bottom = height * .012, height * .961
    yy, xx = np.mgrid[:height, :width].astype(np.float32)
    dx = np.minimum(np.abs(xx - left), np.abs(xx - right))
    dy = np.minimum(np.abs(yy - top), np.abs(yy - bottom))
    edge_distance = np.minimum(dx, dy)
    band = ((edge_distance <= 7) & (xx >= left - 7) & (xx <= right + 7)
            & (yy >= top - 7) & (yy <= bottom + 7))
    inner_region = ((xx >= width * .025) & (xx <= width * .960)
                    & (yy >= height * .040) & (yy <= height * .940))
    if np.any(band & inner_region):
        raise AssertionError("Outer effect overlaps the previous inner frame area")
    base = illustration.quantize(colors=224, method=Image.Quantize.MEDIANCUT)
    palette = base.getpalette()
    for i in range(31):
        if i < 16:
            u = i / 15
            start, end = (110, 118, 79), (255, 247, 190)
        else:
            u = (i - 16) / 14
            start, end = (65, 115, 95), (181, 255, 227)
        palette[3 * (224 + i):3 * (225 + i)] = [round(a + (b - a) * u) for a, b in zip(start, end)]
    palette[765:768] = [0, 0, 0]
    base.putpalette(palette)
    base_indices = np.asarray(base)
    base_rgb = np.asarray(base.convert("RGB"))
    horizontal, vertical = right - left, bottom - top
    perimeter = 2 * (horizontal + vertical)
    along = np.where(
        dx < dy,
        np.where(xx > (left + right) / 2, horizontal + yy - top, perimeter - (yy - top)),
        np.where(yy > (top + bottom) / 2, horizontal + vertical + right - xx, xx - left),
    )
    # Every other pixel is copied from the same indexed artwork in every frame.
    band_y, band_x = np.nonzero(band)
    positions = along[band]
    distances = edge_distance[band]
    band_base = base_rgb[band].astype(np.float32)
    light_stroke = (.90 * np.exp(-(distances / 1.7) ** 2)
                    + .30 * np.exp(-(distances / 4.5) ** 2))
    gold = np.array([255, 247, 190], dtype=np.float32)
    jade = np.array([181, 255, 227], dtype=np.float32)
    pictures: list[Image.Image] = []
    max_changed = 0
    loop_delta = []
    previous = None
    first = None
    min_visible_pixels = width * height
    min_visible_peak = 255.0
    for index in range(frames):
        centre = index / frames * perimeter
        def packet(origin):
            signed = (positions - origin + perimeter / 2) % perimeter - perimeter / 2
            # Bright head with a longer wake; two contrasting packets make
            # movement visible without changing the centre or image opacity.
            envelope = np.where(signed >= 0, np.exp(-(signed / 95) ** 2), np.exp(-(-signed / 250) ** 2))
            return np.minimum(light_stroke * envelope, .97)
        alpha = packet(centre)
        beta = packet((centre + perimeter / 2) % perimeter)
        color = band_base * (1 - alpha[:, None]) + gold * alpha[:, None]
        color = np.rint(color * (1 - beta[:, None]) + jade * beta[:, None]).astype(np.uint8)
        # Quantize only the effect strip. Dithering cannot propagate changes
        # into the still mountains, crane, or the centre behind the text.
        strip = Image.fromarray(color[None, :, :], "RGB").quantize(palette=base, dither=Image.Dither.NONE)
        indices = base_indices.copy()
        # Zero/negligible light must leave the fixed artwork exactly intact.
        active = np.maximum(alpha, beta) > .004
        indices[band_y[active], band_x[active]] = np.asarray(strip)[0, active]
        changed = indices != base_indices
        if np.any(changed & ~band):
            raise AssertionError("Animation changed the protected illustration")
        max_changed = max(max_changed, int(changed.sum()))
        drawn = np.asarray(palette, dtype=np.uint8).reshape(256, 3)[indices]
        # Check visibility after the user's unchanged 50% background opacity,
        # rather than accepting merely different (but imperceptible) frames.
        visible_delta = np.max(np.abs(drawn.astype(np.int16) - base_rgb.astype(np.int16)), axis=2) * .5
        min_visible_pixels = min(min_visible_pixels, int((visible_delta > 30).sum()))
        min_visible_peak = min(min_visible_peak, float(visible_delta.max()))
        if previous is not None:
            loop_delta.append(int(np.count_nonzero(indices != previous)))
        if first is None:
            first = indices.copy()
        previous = indices
        frame = Image.fromarray(indices, "P")
        frame.putpalette(palette)
        pictures.append(frame)
    boundary_delta = int(np.count_nonzero(previous != first))
    output.parent.mkdir(parents=True, exist_ok=True)
    pictures[0].save(output, save_all=True, append_images=pictures[1:], duration=60,
                     loop=0, disposal=1, optimize=True, transparency=255)
    # Decode the actual GIF (including delta frame disposal) before accepting it.
    decoded = Image.open(output)
    if decoded.n_frames != frames or decoded.info.get("loop") != 0:
        raise AssertionError("GIF lost animation frames or infinite loop metadata")
    max_decode_change = 0
    hashes = set()
    for index in range(decoded.n_frames):
        decoded.seek(index)
        rgb = np.asarray(decoded.convert("RGB"))
        if not np.array_equal(rgb[~band], base_rgb[~band]):
            raise AssertionError(f"Decoded frame {index} changed the protected centre")
        max_decode_change = max(max_decode_change, int(np.count_nonzero(np.any(rgb != base_rgb, axis=2))))
        hashes.add(hashlib.sha256(rgb.tobytes()).hexdigest())
    if len(hashes) != frames:
        raise AssertionError("Duplicate or frozen animation frame")
    if min_visible_pixels < 1000 or min_visible_peak < 60:
        raise AssertionError("Outer light is too faint at the installed half opacity")
    rmse = float(np.sqrt(np.mean((original.astype(np.float32) - base_rgb.astype(np.float32)) ** 2)))
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
        raise AssertionError("Original illustration was modified")
    data = {
        "source": str(source.relative_to(ROOT)), "sourceSha256": source_hash,
        "output": str(output.relative_to(ROOT)), "width": width, "height": height,
        "frames": frames, "uniqueDecodedFrames": len(hashes), "frameDurationMs": 60,
        "loopDurationMs": frames * 60, "loopForever": True,
        "movingLightPackets": 2, "minimumVisiblePixelsAtHalfOpacity": min_visible_pixels,
        "innerFrameEnabled": False, "additionalCornerMotifsEnabled": False,
        "previousInnerFrameAreaFreeOfAddedEffects": True,
        "outerFrameNormalized": [.007, .012, .993, .961],
        "minimumPeakDeltaAtHalfOpacity": min_visible_peak,
        "effectBandPixels": 7, "protectedArtworkPixels": int((~band).sum()),
        "protectedArtworkStaticInEveryDecodedFrame": True,
        "maxAnimatedPixels": max_decode_change, "outputBytes": output.stat().st_size,
        "globalPalette": True, "sourceIllustrationUnmodified": True,
        "sourceToRenderedBaseRmse8Bit": round(rmse, 3),
        "sourceToRenderedBasePsnrDb": round(20 * math.log10(255 / max(rmse, .0001)), 2),
        "loopBoundaryChangedPixels": boundary_delta,
        "maximumAdjacentChangedPixels": max(loop_delta),
        "renderingLayer": "Windows Terminal background Image, below text",
        "terminalPixelShaderRequired": False,
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ASSETS / "ink-jade-ornate-v2.png")
    parser.add_argument("--output", type=Path, default=ASSETS / "ink-jade-background-v5.gif")
    parser.add_argument("--report", type=Path, default=ROOT / "artifacts/terminal-background/animation-validation.json")
    parser.add_argument("--frames", type=int, default=200)
    args = parser.parse_args()
    build(args.source.resolve(), args.output.resolve(), args.report.resolve(), args.frames)
