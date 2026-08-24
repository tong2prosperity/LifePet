import Foundation

enum ShadowFriendPresentationValues {
    static func stateSentence(_ stateID: String) -> String {
        switch stateID {
        case "sleeping": "正在睡觉"
        case "waking": "刚刚醒来"
        case "energetic": "有精神，正在活动"
        case "tired": "有点累，正在休息"
        default: "状态平稳"
        }
    }

    static func relativeUpdate(_ snapshot: ShadowSnapshotDTO?, now: Date = .now) -> String {
        guard let snapshot else { return "还没有收到状态" }
        let interval = max(0, now.timeIntervalSince(snapshot.syncedAt))
        if interval < 60 { return "刚刚更新" }
        if interval < 60 * 60 { return "\(max(1, Int(interval / 60))) 分钟前更新" }
        if interval < 24 * 60 * 60 { return "\(max(1, Int(interval / 3600))) 小时前更新" }
        return "\(max(1, Int(interval / 86_400))) 天前更新"
    }

    static func inviteExpiry(_ date: Date, now: Date = .now) -> String {
        guard date > now else { return "邀请已过期" }
        let hours = max(1, Int(ceil(date.timeIntervalSince(now) / 3600)))
        return hours >= 24 ? "\(Int(ceil(Double(hours) / 24))) 天后失效" : "\(hours) 小时后失效"
    }

    static func connectedDate(_ date: Date?) -> String {
        guard let date else { return "已连接" }
        return "\(date.formatted(.dateTime.year().month().day()))连接"
    }
}
