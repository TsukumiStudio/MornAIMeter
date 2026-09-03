import AppKit
import Foundation

/// 枠の開始からいまが何%の位置か (elapsed) と、使用率との差 (difference = used - elapsed)。
struct WindowPosition: Equatable {
    let elapsed: Double
    let difference: Double
}

/// worker/src/index.js の fmtRemain / fmtReset と同じ趣旨の残り時間整形 (純粋関数、単体テスト対象)。
enum UsageFormat {
    /// 「あと1日2時間3分」のように、日→時間→分の順で0でない桁だけ足していく。分は常に表示する。
    static func remain(_ diff: TimeInterval) -> String {
        let totalMinutes = max(0, Int(floor(diff / 60)))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        var s = "あと"
        if days > 0 { s += "\(days)日" }
        if hours > 0 { s += "\(hours)時間" }
        s += "\(minutes)分"
        return s
    }

    /// リセット時刻が未来なら残り時間、過去なら windowSeconds ぶん進めた次回の目安を返す。
    static func resetText(resetsAt: Date?, windowSeconds: Double, now: Date = Date()) -> String {
        guard let resetsAt else { return "リセット時刻不明" }
        let diff = resetsAt.timeIntervalSince(now)
        if diff > 0 {
            return remain(diff) + "でリセット"
        }
        guard windowSeconds > 0 else { return "リセット済み" }
        let elapsedSteps = floor(-diff / windowSeconds) + 1
        let nextDiff = diff + elapsedSteps * windowSeconds
        return "次回まで" + remain(nextDiff)
    }

    /// メニューバーのゲージ横に出す使用率表示。未取得・失敗時は "--"。
    static func percentText(_ percent: Double?) -> String {
        percent.map { String(format: "%.0f%%", $0) } ?? "--"
    }

    /// worker/src/index.js の windowPosition (637〜646行) の移植。
    /// resets_at が過去なら windowSeconds ぶん進めて現在の枠に合わせ、elapsed% と difference を返す。
    static func windowPosition(resetsAt: Date?, windowSeconds: Double, usedPercent: Double?, now: Date = Date()) -> WindowPosition? {
        guard let usedPercent, let resetsAt, windowSeconds > 0 else { return nil }
        let raw = resetsAt.timeIntervalSince1970
        let step = windowSeconds
        let nowSec = now.timeIntervalSince1970
        let reset = raw > nowSec ? raw : raw + (floor((nowSec - raw) / step) + 1) * step
        let elapsed = min(max((nowSec - (reset - step)) / step * 100, 0), 100)
        return WindowPosition(elapsed: elapsed, difference: usedPercent - elapsed)
    }

    /// worker/src/index.js の paceLabel (649〜651行) の移植。
    static func paceLabel(_ difference: Double) -> String {
        abs(difference) < 1
            ? "ほぼ均等ペース"
            : "均等より " + String(format: "%.0f", abs(difference)) + "pt" + (difference > 0 ? "先行" : "余裕")
    }
}

/// メニューバーの label に出す円グラフ画像 (GaugeCircleParams を横並びで描く)。非テンプレート画像。輪郭は白、扇形は明るいグレー (固定色)、経過率の線はオレンジ。
enum GaugeImage {
    static let diameter: CGFloat = 16
    static let spacing: CGFloat = 4

    /// n 個の円を横並びに描いた NSImage を作る。1個 = 輪郭1pt の円 + 使用率ぶんの扇形 (12時から時計回り) + 経過率の位置の線 (1.5pt)。
    static func make(params: [GaugeCircleParams]) -> NSImage {
        let count = params.count
        let width = count > 0 ? CGFloat(count) * diameter + CGFloat(count - 1) * spacing : diameter
        let size = NSSize(width: width, height: diameter)
        let image = NSImage(size: size, flipped: false) { _ in
            for (index, p) in params.enumerated() {
                let x = CGFloat(index) * (diameter + spacing)
                draw(p, in: NSRect(x: x, y: 0, width: diameter, height: diameter))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(_ p: GaugeCircleParams, in rect: NSRect) {
        let lineWidth: CGFloat = 1
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 - lineWidth / 2

        let outline = NSBezierPath(ovalIn: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        outline.lineWidth = lineWidth
        NSColor.white.setStroke()
        outline.stroke()

        if let used = p.usedFraction, used > 0 {
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: radius, startAngle: angle(for: 0), endAngle: angle(for: used), clockwise: true)
            path.close()
            NSColor(white: 0.7, alpha: 1).setFill()
            path.fill()
        }

        if let elapsed = p.elapsedFraction {
            let a = angle(for: elapsed) * .pi / 180
            let end = NSPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            let line = NSBezierPath()
            line.move(to: center)
            line.line(to: end)

            NSColor.systemOrange.setStroke()
            line.lineWidth = 2
            line.stroke()
        }
    }

    /// fraction (0〜1, 12時位置から時計回り) を NSBezierPath の角度 (度, 0°=3時位置, 反時計回りが正) に変換する。
    private static func angle(for fraction: Double) -> CGFloat {
        CGFloat(90 - fraction * 360)
    }
}
