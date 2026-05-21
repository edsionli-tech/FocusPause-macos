import SwiftUI

/// 品牌弧形图标（高清图源来自 Asset `MenuBarIcon`，避免小图拉伸模糊）。
struct FocusPauseBrandMark: View {
    var size: CGFloat = 44
    /// 近似系统 App Icon 的连续圆角比例。
    var cornerRadiusFraction: CGFloat = 0.224

    var body: some View {
        Image("MenuBarIcon")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous))
            .accessibilityLabel("FocusPause")
    }
}
