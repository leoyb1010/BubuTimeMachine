import Foundation

// Synthetic simulator material only. Emits JSON as hex for simctl defaults -data;
// cfprefsd owns the actual preference write. Never copies a real family snapshot.
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fatalError("Usage: swift WatchReadingFixture.swift ILLUSTRATION_PATH [empty|missing|long]") }
let illustration = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
guard illustration.count <= 30_000 else { fatalError("Use a synthetic thumbnail below 30KB, not a full-size image") }
let mode = arguments.count > 2 ? arguments[2] : "normal"
let notes = ["第一次自己搭好了高高的积木，转过来笑着说：爸爸快看！", "公园里的小鸟飞起来了，她也张开手臂，假装自己是一只小鸟。", "醒来以后抱着小熊，说要带它一起去看月亮。"]
let longNote = String(repeating: "她认真地给小熊讲今天的故事，讲到开心的地方还会笑。", count: 8)
let memories: [[String: Any]] = mode == "empty" ? [] : notes.enumerated().map { index, note in
    ["id": "synthetic-watch-\(index)", "dateText": ["10月3日", "9月24日", "9月15日"][index],
     "note": mode == "long" && index == 0 ? longNote : note,
     "ageText": "1岁9个月", "isOnThisDay": index == 1, "moodEmoji": "🌷",
     "photoFileName": mode == "missing" ? "not-yet-received.png" : "watch-demo-\(index).png"]
}
let recent = memories.map { memory -> [String: Any] in
    ["id": memory["id"]!, "dateText": memory["dateText"]!, "note": memory["note"]!,
     "moodEmoji": "🌷", "photoFileName": memory["photoFileName"]!]
}
var snapshot: [String: Any] = ["childName": "小布", "birthday": "2025-01-01T00:00:00Z",
    "roleRaw": "爸爸", "achievedMilestones": 12, "totalMilestones": 36,
    "recent": recent, "memories": memories, "photoCards": memories, "updatedAt": ISO8601DateFormatter().string(from: .now)]
if mode != "empty" { snapshot["avatarData"] = illustration.base64EncodedString() }
let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
print(data.map { String(format: "%02x", $0) }.joined())
