import AppKit
import CoreGraphics

/// 将「亮色线条 + 深色底」的参考 PNG 转为菜单栏用的模板 PNG（黑线 + 透明底）。
enum MenuBarIconRasterPrep {

    static func convertWhiteOnDarkToTemplate(sourceURL: URL, outputURL: URL) throws {
        let img = NSImage(contentsOf: sourceURL)!
        img.size = img.size
        var proposed = CGRect(origin: .zero, size: img.size)
        guard let cgImage = img.cgImage(forProposedRect: &proposed, context: nil, hints: [
            .interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)
        ]) else {
            throw NSError(domain: "MenuBarIconPrep", code: 1)
        }

        let w = cgImage.width
        let h = cgImage.height
        let rowBytes = w * 4
        var data = [UInt8](repeating: 0, count: rowBytes * h)

        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "MenuBarIconPrep", code: 2)
        }

        // 不使用 Y 轴翻转：翻转会导致相对参考稿上下颠倒；默认位图上下文与 PNG 绘制方向一致即可。
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        for y in 0..<h {
            for x in 0..<w {
                let o = y * rowBytes + x * 4
                let r = Int(data[o])
                let g = Int(data[o + 1])
                let b = Int(data[o + 2])
                let lum = (r + g + b) / 3
                // 深色背景 → 透明；亮线 → 黑色不透明模板（中等亮度按阈值过渡到边缘抗锯齿）
                if lum >= 185 {
                    data[o] = 0
                    data[o + 1] = 0
                    data[o + 2] = 0
                    data[o + 3] = 255
                } else if lum > 55 {
                    let a = UInt8(min(255, (lum - 55) * 255 / (185 - 55)))
                    data[o] = 0
                    data[o + 1] = 0
                    data[o + 2] = 0
                    data[o + 3] = a
                } else {
                    data[o] = 0
                    data[o + 1] = 0
                    data[o + 2] = 0
                    data[o + 3] = 0
                }
            }
        }

        guard let outCtx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
              let outCg = outCtx.makeImage() else {
            throw NSError(domain: "MenuBarIconPrep", code: 3)
        }

        let outImg = NSImage(cgImage: outCg, size: NSSize(width: w, height: h))
        guard let tiff = outImg.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MenuBarIconPrep", code: 4)
        }
        try png.write(to: outputURL)
    }
}

@main
enum PrepareMenuBarIconMain {
    static func main() {
        guard CommandLine.arguments.count >= 3 else {
            fputs("用法: prepare_menu_bar_icon <输入.png> <输出模板.png>\n", stderr)
            exit(1)
        }
        let src = URL(fileURLWithPath: CommandLine.arguments[1])
        let dst = URL(fileURLWithPath: CommandLine.arguments[2])
        do {
            try MenuBarIconRasterPrep.convertWhiteOnDarkToTemplate(sourceURL: src, outputURL: dst)
            print(dst.path)
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }
}
