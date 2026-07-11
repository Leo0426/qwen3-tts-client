import Foundation

/// 官方预置音色。数据驱动：官方新增 speaker 时只改这张表。
public struct Voice: Identifiable, Hashable, Sendable {
    /// 传给模型的 speaker 标识
    public let id: String
    public let displayName: String
    public let detail: String

    public init(id: String, displayName: String, detail: String) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
    }

    public static let presets: [Voice] = [
        Voice(id: "Vivian", displayName: "Vivian", detail: "女声 · 明亮"),
        Voice(id: "Serena", displayName: "Serena", detail: "女声 · 温暖"),
        Voice(id: "Uncle_Fu", displayName: "Uncle Fu", detail: "男声 · 沉稳"),
        Voice(id: "Dylan", displayName: "Dylan", detail: "男声 · 北京腔"),
        Voice(id: "Eric", displayName: "Eric", detail: "男声 · 四川话"),
        Voice(id: "Ryan", displayName: "Ryan", detail: "男声 · 活力"),
        Voice(id: "Aiden", displayName: "Aiden", detail: "男声 · 平和"),
        Voice(id: "Ono_Anna", displayName: "Ono Anna", detail: "女声 · 日语"),
        Voice(id: "Sohee", displayName: "Sohee", detail: "女声 · 韩语"),
    ]

    public static let `default` = presets[0]
}
