import Foundation
import Vision
import CoreGraphics
import ImageIO

// MARK: - Types

struct Fragment {
    let text: String
    let confidence: Float
    let box: CGRect
}

struct Line {
    let text: String
    let box: CGRect
    let confidence: Float
}

struct Options {
    var useFast = false
    var languages = ["zh-Hans", "en-US"]
    var languageCorrection = true
    var minConfidence: Float = 0.0
    var jsonOutput = false
    var maxDimension = 0
}

// MARK: - Usage

func usage() {
    let text = """
    Usage: ocr [options] <image...> | ocr [options] -

    Recognize text in images using the macOS Vision framework.

    Options:
      --fast             Use fast (less accurate) recognition.
      --langs <list>     Comma-separated recognition languages
                         (default: zh-Hans,en-US).
      --no-correct       Disable language correction.
      --min-conf <0..1>  Drop results below this confidence.
      --json             Emit JSON: text, confidence and pixel boxes.
      --max-dim <px>     Downscale so the long edge is at most this many px.
      -h, --help         Show this help.

    Pass "-" as the image path to read image bytes from stdin.
    """
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
}

// MARK: - Argument parsing

func parseArgs(_ args: [String]) -> (Options, [String])? {
    var opts = Options()
    var paths: [String] = []
    var i = 1
    while i < args.count {
        let a = args[i]
        switch a {
        case "-h", "--help":
            return nil
        case "--fast":
            opts.useFast = true
        case "--no-correct":
            opts.languageCorrection = false
        case "--json":
            opts.jsonOutput = true
        case "--langs":
            i += 1
            guard i < args.count else { return nil }
            opts.languages = args[i].split(separator: ",").map { String($0) }
        case "--min-conf":
            i += 1
            guard i < args.count, let v = Float(args[i]) else { return nil }
            opts.minConfidence = v
        case "--max-dim":
            i += 1
            guard i < args.count, let v = Int(args[i]) else { return nil }
            opts.maxDimension = v
        case "-":
            paths.append(a)
        default:
            if a.hasPrefix("-") {
                FileHandle.standardError.write(("unknown option: \(a)\n").data(using: .utf8)!)
                return nil
            }
            paths.append(a)
        }
        i += 1
    }
    return (opts, paths)
}

// MARK: - Image loading

/// Load a CGImage from a file path or stdin ("-"), applying EXIF orientation
/// and optionally downscaling so the long edge does not exceed maxDimension.
func loadCGImage(fromPath path: String, maxDimension: Int) -> CGImage? {
    let source: CGImageSource
    if path == "-" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty,
              let s = CGImageSourceCreateWithData(data as CFData, nil) else {
            FileHandle.standardError.write("stdin did not contain a readable image\n".data(using: .utf8)!)
            return nil
        }
        source = s
    } else {
        let url = URL(fileURLWithPath: path)
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            FileHandle.standardError.write("cannot open image: \(path)\n".data(using: .utf8)!)
            return nil
        }
        source = s
    }

    var options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true, // apply EXIF orientation
        kCGImageSourceShouldCacheImmediately: true,
    ]
    if maxDimension > 0 {
        options[kCGImageSourceThumbnailMaxPixelSize] = maxDimension
    }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

// MARK: - Recognition

func recognize(cgImage: CGImage, opts: Options) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = opts.useFast ? .fast : .accurate
    request.recognitionLanguages = opts.languages
    request.usesLanguageCorrection = opts.languageCorrection

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])
    return request.results ?? []
}

// MARK: - Line grouping

func median(_ values: [CGFloat]) -> CGFloat {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
    return sorted[mid]
}

/// Group Vision fragments into full lines, top-to-bottom and left-to-right.
func groupLines(_ observations: [VNRecognizedTextObservation], minConfidence: Float) -> [Line] {
    var fragments: [Fragment] = []
    for obs in observations {
        guard let c = obs.topCandidates(1).first, c.confidence >= minConfidence else { continue }
        fragments.append(Fragment(text: c.string, confidence: c.confidence, box: obs.boundingBox))
    }
    guard !fragments.isEmpty else { return [] }

    let medianHeight = median(fragments.map { $0.box.height })
    let tolerance = max(medianHeight * 0.4, 0.01)

    let sorted = fragments.sorted { a, b in
        if abs(a.box.midY - b.box.midY) > tolerance {
            return a.box.midY > b.box.midY
        }
        return a.box.minX < b.box.minX
    }

    var rows: [[Fragment]] = []
    for fragment in sorted {
        if let lastMid = rows.last?.last?.box.midY, abs(fragment.box.midY - lastMid) <= tolerance {
            rows[rows.count - 1].append(fragment)
        } else {
            rows.append([fragment])
        }
    }

    return rows.map { row in
        let ordered = row.sorted { $0.box.minX < $1.box.minX }
        let text = ordered.map { $0.text }.joined(separator: " ")
        let minX = ordered.map { $0.box.minX }.min() ?? 0
        let maxX = ordered.map { $0.box.maxX }.max() ?? 0
        let minY = ordered.map { $0.box.minY }.min() ?? 0
        let maxY = ordered.map { $0.box.maxY }.max() ?? 0
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let confidence = ordered.map { $0.confidence }.reduce(0, +) / Float(ordered.count)
        return Line(text: text, box: box, confidence: confidence)
    }
}

// MARK: - Output

/// Convert a Vision normalized box (origin bottom-left) to pixel box (origin top-left).
func pixelBox(_ box: CGRect, width: Int, height: Int) -> [String: Any] {
    let x = box.origin.x * CGFloat(width)
    let y = (1 - box.origin.y - box.size.height) * CGFloat(height)
    let w = box.size.width * CGFloat(width)
    let h = box.size.height * CGFloat(height)
    return ["x": x, "y": y, "width": w, "height": h]
}

func emitJSON(results: [(path: String, width: Int, height: Int, lines: [Line])]) {
    let items: [[String: Any]] = results.map { r in
        let lineObjs: [[String: Any]] = r.lines.map { line in
            [
                "text": line.text,
                "confidence": line.confidence,
                "box": pixelBox(line.box, width: r.width, height: r.height),
            ]
        }
        return ["file": r.path, "width": r.width, "height": r.height, "lines": lineObjs]
    }
    let payload: Any = items.count == 1 ? items[0] : items
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
        print(string)
    }
}

// MARK: - Main

func run() -> Int32 {
    let args = CommandLine.arguments
    if args.count <= 1 {
        usage()
        return 2
    }
    if args.contains("-h") || args.contains("--help") {
        usage()
        return 0
    }
    guard let (opts, paths) = parseArgs(args), !paths.isEmpty else {
        usage()
        return 2
    }

    var results: [(path: String, width: Int, height: Int, lines: [Line])] = []
    var hadError = false

    for path in paths {
        guard let cgImage = loadCGImage(fromPath: path, maxDimension: opts.maxDimension) else {
            hadError = true
            continue
        }
        do {
            let observations = try recognize(cgImage: cgImage, opts: opts)
            let lines = groupLines(observations, minConfidence: opts.minConfidence)
            results.append((path: path, width: cgImage.width, height: cgImage.height, lines: lines))
        } catch {
            FileHandle.standardError.write("OCR failed for \(path): \(error)\n".data(using: .utf8)!)
            hadError = true
        }
    }

    if opts.jsonOutput {
        emitJSON(results: results)
    } else {
        for (index, result) in results.enumerated() {
            if results.count > 1 {
                if index > 0 { print("") }
                print("--- \(result.path) ---")
            }
            for line in result.lines {
                print(line.text)
            }
        }
    }

    return hadError ? 1 : 0
}

exit(run())
