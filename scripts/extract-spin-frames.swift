import AppKit
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 5,
      let frameCount = Int(CommandLine.arguments[3]),
      let frameSize = Int(CommandLine.arguments[4]),
      frameCount > 0,
      frameSize > 0 else {
  fatalError("Usage: swift extract-spin-frames.swift input.mp4 output-directory frame-count frame-size")
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let asset = AVURLAsset(url: input)
let duration = CMTimeGetSeconds(asset.duration)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: frameSize, height: frameSize)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

for index in 0..<frameCount {
  let time = CMTime(seconds: duration * Double(index) / Double(frameCount), preferredTimescale: 60000)
  let image = try generator.copyCGImage(at: time, actualTime: nil)
  let bitmap = NSBitmapImageRep(cgImage: image)
  let png = bitmap.representation(using: .png, properties: [:])!
  let name = String(format: "frame-%03d.png", index)
  try png.write(to: output.appendingPathComponent(name))
}

print("Extracted \(frameCount) frames from \(input.lastPathComponent)")
