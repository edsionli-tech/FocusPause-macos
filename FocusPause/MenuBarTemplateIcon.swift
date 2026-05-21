#if !targetEnvironment(macCatalyst)
import AppKit

/// 菜单栏图标：`MenuBarStatusTemplate`（模板 PNG：黑线透明底、`template-rendering-intent`），资源由 `scripts/prepare_menu_bar_icon.swift` 从参考图生成。
enum FocusPauseMenuBarTemplateIcon {
    static func nsImage(side: CGFloat = 18) -> NSImage {
        guard let base = NSImage(named: "MenuBarStatusTemplate"),
              let image = base.copy() as? NSImage else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        image.accessibilityDescription = "FocusPause"
        image.isTemplate = true
        // 仅在尺寸与资源不一致时再改 logical size，避免对已是 18×18/@2x 的位图二次插值变糊。
        if abs(image.size.width - side) > 0.25 || abs(image.size.height - side) > 0.25 {
            image.size = NSSize(width: side, height: side)
        }
        return image
    }
}
#endif
