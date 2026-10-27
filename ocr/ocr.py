#!/usr/bin/env python3
"""OCR using the macOS Vision framework via pyobjc.

Requires (one-time):
    pip install pyobjc-framework-Vision pyobjc-framework-Quartz

Usage:
    python3 ocr.py [options] <image...>
    python3 ocr.py [options] -          # read image bytes from stdin

Options:
    --fast             Use fast (less accurate) recognition.
    --langs <list>     Comma-separated recognition languages (default: zh-Hans,en-US).
    --no-correct       Disable language correction.
    --min-conf <0..1>  Drop results below this confidence.
    --json             Emit JSON with text, confidence and normalized boxes.
"""
import argparse
import json
import sys


def read_bytes(path):
    if path == "-":
        return sys.stdin.buffer.read()
    with open(path, "rb") as fh:
        return fh.read()


def recognize(data, langs, use_fast, correct, min_conf):
    """Run Vision OCR and return a list of text fragments with boxes."""
    import Vision
    from Foundation import NSData

    nsdata = NSData.dataWithBytes_length_(data, len(data))
    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(
        Vision.VNRequestTextRecognitionLevelFast
        if use_fast
        else Vision.VNRequestTextRecognitionLevelAccurate
    )
    request.setRecognitionLanguages_(langs)
    request.setUsesLanguageCorrection_(correct)

    handler = Vision.VNImageRequestHandler.alloc().initWithData_options_(nsdata, None)
    ok, error = handler.performRequests_error_([request], None)
    if not ok:
        raise RuntimeError(error or "OCR failed")

    fragments = []
    for obs in request.results() or []:
        candidates = obs.topCandidates_(1)
        if not candidates:
            continue
        cand = candidates[0]
        if cand.confidence() < min_conf:
            continue
        box = obs.boundingBox()
        fragments.append({
            "text": cand.string(),
            "confidence": float(cand.confidence()),
            "box": (box.origin.x, box.origin.y, box.size.width, box.size.height),
        })
    return fragments


def median(values):
    if not values:
        return 0.0
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2 == 0:
        return (ordered[mid - 1] + ordered[mid]) / 2.0
    return ordered[mid]


def group_lines(fragments):
    """Group fragments into full lines, top-to-bottom then left-to-right."""
    if not fragments:
        return []

    heights = [f["box"][3] for f in fragments]
    tolerance = max(median(heights) * 0.4, 0.01)

    def mid_y(f):
        x, y, w, h = f["box"]
        return y + h / 2.0

    fragments.sort(key=lambda f: (-mid_y(f), f["box"][0]))

    rows = []
    for frag in fragments:
        if rows and abs(mid_y(frag) - mid_y(rows[-1][-1])) <= tolerance:
            rows[-1].append(frag)
        else:
            rows.append([frag])

    lines = []
    for row in rows:
        row.sort(key=lambda f: f["box"][0])
        text = " ".join(f["text"] for f in row)
        conf = sum(f["confidence"] for f in row) / len(row)
        xs = [f["box"][0] for f in row]
        ys = [f["box"][1] for f in row]
        rights = [f["box"][0] + f["box"][2] for f in row]
        tops = [f["box"][1] + f["box"][3] for f in row]
        box = (min(xs), min(ys), max(rights) - min(xs), max(tops) - min(ys))
        lines.append({"text": text, "confidence": conf, "box": box})
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--fast", action="store_true")
    parser.add_argument("--langs", default="zh-Hans,en-US")
    parser.add_argument("--no-correct", action="store_true")
    parser.add_argument("--min-conf", type=float, default=0.0)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args(argv)

    langs = [s.strip() for s in args.langs.split(",") if s.strip()]
    results = []
    for path in args.paths:
        data = read_bytes(path)
        if not data:
            print(f"no data for {path}", file=sys.stderr)
            continue
        try:
            fragments = recognize(
                data,
                langs,
                use_fast=args.fast,
                correct=not args.no_correct,
                min_conf=args.min_conf,
            )
        except Exception as exc:  # noqa: BLE001
            print(f"OCR failed for {path}: {exc}", file=sys.stderr)
            continue
        results.append({"file": path, "lines": group_lines(fragments)})

    if args.json:
        payload = results[0] if len(results) == 1 else results
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    for i, r in enumerate(results):
        if len(results) > 1:
            if i:
                print()
            print(f"--- {r['file']} ---")
        for line in r["lines"]:
            print(line["text"])


if __name__ == "__main__":
    main()
