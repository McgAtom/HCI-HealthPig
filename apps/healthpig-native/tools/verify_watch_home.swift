import AppKit
import Foundation
import Vision

// Verify rendered app content, not merely a successful process launch or a clock face.
guard CommandLine.arguments.count == 2,
      let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))),
      let image = bitmap.cgImage else { exit(2) }
let request = VNRecognizeTextRequest()
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.recognitionLevel = .accurate
try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    .joined().replacingOccurrences(of: " ", with: "")
let visible = text.contains("养猪") && text.contains("走走猪猪")
print(visible ? "PASS: Watch home is rendered" : "FAIL: Watch home is not visible (black screen, clock face, or another page)")
exit(visible ? 0 : 1)
