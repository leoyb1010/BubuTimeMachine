import Foundation

extension String {
    /// 去首尾空白与换行。全工程共享（HealthRecordSheet 内的 private trimmed 为历史遗留）。
    var bubuTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
