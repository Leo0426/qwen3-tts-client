// 生成应用图标：紫罗兰渐变圆角方形 + 白色声波
// 用法: swift assets/icon/generate-icon.swift（在仓库根目录运行）
// 产物: assets/icon/AppIcon.iconset/*.png → 再由 iconutil 合成 AppIcon.icns
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 声波柱高度（相对主体高度的比例），左右对称呼应语音波形
let barHeights: [CGFloat] = [0.22, 0.40, 0.62, 0.88, 0.52, 0.74, 0.36, 0.58, 0.26]

func drawIcon(canvas: CGFloat) -> CGImage {
    let scale = canvas / 1024.0
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas),
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // 主体：macOS 图标栅格（1024 画布内 824pt 圆角方形，圆角 185）
    let bodySize = 824 * scale
    let bodyOrigin = (canvas - bodySize) / 2
    let bodyRect = CGRect(x: bodyOrigin, y: bodyOrigin, width: bodySize, height: bodySize)
    let bodyPath = CGPath(
        roundedRect: bodyRect,
        cornerWidth: 185 * scale, cornerHeight: 185 * scale,
        transform: nil
    )

    // 底部投影（烘焙进图标，与系统图标一致的轻投影）
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -12 * scale),
        blur: 36 * scale,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30)
    )
    context.addPath(bodyPath)
    context.setFillColor(CGColor(red: 0.35, green: 0.25, blue: 0.75, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // 渐变填充：violet-400 → violet-900
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.655, green: 0.478, blue: 0.980, alpha: 1), // #A77AFA
            CGColor(red: 0.306, green: 0.114, blue: 0.674, alpha: 1), // #4E1DAC
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
        options: []
    )
    // 顶部一层极淡高光，避免大面积渐变发闷
    let gloss = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gloss,
        start: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.midX, y: bodyRect.midY),
        options: []
    )
    context.restoreGState()

    // 白色声波柱（胶囊形，居中）
    let barWidth = 46 * scale
    let barGap = 32 * scale
    let totalWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barGap
    var x = (canvas - totalWidth) / 2
    let maxBarHeight = bodySize * 0.52
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    for height in barHeights {
        let barHeightPx = maxBarHeight * height
        let barRect = CGRect(
            x: x, y: (canvas - barHeightPx) / 2,
            width: barWidth, height: barHeightPx
        )
        let capsule = CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
            transform: nil
        )
        context.addPath(capsule)
        context.fillPath()
        x += barWidth + barGap
    }

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let iconsetURL = URL(fileURLWithPath: "assets/icon/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    let image = drawIcon(canvas: entry.size)
    writePNG(image, to: iconsetURL.appendingPathComponent("\(entry.name).png"))
}
print("iconset 已生成: \(iconsetURL.path)")
