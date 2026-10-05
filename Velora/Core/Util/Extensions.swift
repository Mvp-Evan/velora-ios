import SwiftUI

// MARK: - Date

extension Date {
    /// 友好时间：刚刚 / 5 分钟前 / 今天 14:20 / 昨天 / 10-02
    var relativeText: String {
        let now = Date()
        let diff = now.timeIntervalSince(self)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(self) { f.dateFormat = "HH:mm"; return f.string(from: self) }
        if cal.isDateInYesterday(self) { f.dateFormat = "昨天 HH:mm"; return f.string(from: self) }
        if cal.isDate(self, equalTo: now, toGranularity: .year) { f.dateFormat = "MM-dd HH:mm" } else { f.dateFormat = "yyyy-MM-dd" }
        return f.string(from: self)
    }

    var fullText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: self)
    }

    var shortText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(self) ? "今天 HH:mm" : "MM月dd日 HH:mm"
        return f.string(from: self)
    }

    /// 倒计时文本：2天03:12:09 / 03:12:09 / 00:59
    func countdownText(to now: Date = Date()) -> String {
        let s = max(0, Int(timeIntervalSince(now).rounded(.down)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return String(format: "%d天%02d:%02d:%02d", d, h, m, sec) }
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    var remaining: TimeInterval { timeIntervalSinceNow }
}

// MARK: - String

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isPhone: Bool { count == 11 && hasPrefix("1") && allSatisfy(\.isNumber) }
}

// MARK: - Int formatting

extension Int {
    var compact: String {
        if self >= 10000 { return String(format: "%.1f万", Double(self) / 10000) }
        return "\(self)"
    }
}

// MARK: - View helpers

extension View {
    @ViewBuilder
    func `if`<T: View>(_ cond: Bool, transform: (Self) -> T) -> some View {
        if cond { transform(self) } else { self }
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// 简单触觉反馈
enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

/// 页面加载状态
enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
    var isLoading: Bool { self == .loading }
}
