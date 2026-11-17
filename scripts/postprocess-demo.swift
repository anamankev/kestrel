import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

// usage: swift postprocess.swift <in.mp4> <out.mp4> <out.gif> <gifStart> <gifSeconds> [rotateDegrees] [trimStart]
let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let outMP4 = URL(fileURLWithPath: args[2])
let outGIF = URL(fileURLWithPath: args[3])
let gifStart = Double(args[4])!
let gifSeconds = Double(args[5])!

let asset = AVURLAsset(url: input)
let sema = DispatchSemaphore(value: 0)
let rotateDegrees = Double(args.count > 6 ? args[6] : "90")!
let trimStart = Double(args.count > 7 ? args[7] : "5")!

/// The simulator records its native portrait frame; rotate into the landscape UI.
func rotated() async throws -> AVMutableVideoComposition {
    let track = try await asset.loadTracks(withMediaType: .video)[0]
    let size = try await track.load(.naturalSize)
    let duration = try await asset.load(.duration)
    let c = AVMutableVideoComposition()
    c.renderSize = CGSize(width: size.height, height: size.width)
    c.frameDuration = CMTime(value: 1, timescale: 30)
    let ins = AVMutableVideoCompositionInstruction()
    ins.timeRange = CMTimeRange(start: .zero, duration: duration)
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    let t: CGAffineTransform = rotateDegrees > 0
        ? CGAffineTransform(translationX: size.height, y: 0).rotated(by: .pi / 2)
        : CGAffineTransform(translationX: 0, y: size.width).rotated(by: -.pi / 2)
    layer.setTransform(t, at: .zero)
    ins.layerInstructions = [layer]
    c.instructions = [ins]
    return c
}

Task {
    let comp = try await rotated()
    // 1. Full-length 1080p H.264 for LinkedIn / README link.
    try? FileManager.default.removeItem(at: outMP4)
    let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080)!
    export.videoComposition = comp
    let total = try await asset.load(.duration)
    export.timeRange = CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 600), end: total)
    do {
        try await export.export(to: outMP4, as: .mp4)
        print("mp4 ok")
    } catch { print("mp4 failed: \(error)") }

    // 2. GIF preview: 10 fps, 900 px wide.
    let gen = AVAssetImageGenerator(asset: asset)
    gen.videoComposition = comp
    gen.maximumSize = CGSize(width: 900, height: 900)
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    let fps = 10.0
    let count = Int(gifSeconds * fps)
    try? FileManager.default.removeItem(at: outGIF)
    guard let dest = CGImageDestinationCreateWithURL(outGIF as CFURL, UTType.gif.identifier as CFString, count, nil) else { print("gif dest failed"); sema.signal(); return }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
    for i in 0..<count {
        let t = CMTime(seconds: gifStart + Double(i) / fps, preferredTimescale: 600)
        if let img = try? await gen.image(at: t).image { CGImageDestinationAddImage(dest, img, frameProps) }
    }
    print(CGImageDestinationFinalize(dest) ? "gif ok" : "gif failed")
    sema.signal()
}
sema.wait()
