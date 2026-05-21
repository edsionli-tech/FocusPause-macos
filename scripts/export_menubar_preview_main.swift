import AppKit

/// 从与用户菜单栏一致的源 PNG（默认 `previews/menu_bar_icon_source.png`）缩放导出高清预览。
@main
enum ExportMenuBarPreview {
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("用法: ExportMenuBarPreview <输出.png路径> [边长px 默认1024] [源PNG路径]\n", stderr)
            exit(1)
        }

        let outPath = CommandLine.arguments[1]
        let side: CGFloat = {
            guard CommandLine.arguments.count >= 3, let v = Double(CommandLine.arguments[2]), v > 8 else {
                return 1024
            }
            return CGFloat(v)
        }()

        let cwd = FileManager.default.currentDirectoryPath
        let srcPath = CommandLine.arguments.count >= 4
            ? CommandLine.arguments[3]
            : (cwd as NSString).appendingPathComponent("previews/menu_bar_icon_source.png")

        guard let src = NSImage(contentsOf: URL(fileURLWithPath: srcPath)) else {
            fputs("无法读取源图: \(srcPath)\n", stderr)
            exit(1)
        }

        let px = max(1, Int(round(side)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px,
            pixelsHigh: px,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fputs("导出失败：无法创建位图\n", stderr)
            exit(1)
        }

        rep.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            fputs("导出失败：图形上下文\n", stderr)
            exit(1)
        }
        ctx.imageInterpolation = .high
        ctx.shouldAntialias = true
        NSGraphicsContext.current = ctx

        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: rep.size)).fill()

        let sz = src.size
        src.draw(
            in: CGRect(origin: .zero, size: rep.size),
            from: CGRect(origin: .zero, size: sz),
            operation: .sourceOver,
            fraction: 1.0
        )

        guard let data = rep.representation(using: .png, properties: [:]) else {
            fputs("导出失败：无法生成 PNG\n", stderr)
            exit(1)
        }

        let url = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url)
            print(url.path)
        } catch {
            fputs("写入失败: \(error)\n", stderr)
            exit(1)
        }
    }
}
