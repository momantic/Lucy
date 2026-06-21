import Foundation
import Vision
import AppKit

// Usage:
// swift tools/ocr_screen_text.swift /tmp/lucy_linkedin_screen.png

if CommandLine.arguments.count < 2 {
    fputs("Usage: swift ocr_screen_text.swift /path/to/image.png\n", stderr)
    exit(1)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])

guard let nsImage = NSImage(contentsOf: imageURL),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Could not load image: \(imageURL.path)\n", stderr)
    exit(1)
}

let request = VNRecognizeTextRequest { request, error in
    if let error = error {
        fputs("OCR error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    let observations = request.results as? [VNRecognizedTextObservation] ?? []
    let lines = observations.compactMap { observation in
        observation.topCandidates(1).first?.string
    }

    print(lines.joined(separator: "\n"))
}

request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.recognitionLanguages = ["en-US"]

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    fputs("Failed to perform OCR: \(error.localizedDescription)\n", stderr)
    exit(1)
}
