import Foundation

/// Factories that map HealthKit values onto upload-ready samples. This is the
/// seam where the existing `HealthDataService` pipeline plugs into the economy:
/// when an observer/anchored query yields new samples, build `HealthSampleDTO`s
/// here and hand them to `EconomyService.sync`.
///
/// `dedupKey` rules (sample-level idempotency):
///   - a stable platform sample UUID (`HKSample.uuid`) → "HK-<uuid>"
///   - an aggregate bucket (e.g. hourly steps) → a derived, deterministic key
///     from metric + time range, so re-uploading the same bucket never
///     double-counts.
extension HealthSampleDTO {
    static func steps(_ count: Double, start: Date, end: Date, uuid: String? = nil) -> HealthSampleDTO {
        HealthSampleDTO(metric: "steps", value: count, unit: "count",
                        startTs: start, endTs: end,
                        externalSampleId: uuid,
                        dedupKey: dedupKey(metric: "steps", uuid: uuid, start: start, end: end))
    }

    static func sleep(seconds: Double, start: Date, end: Date, uuid: String? = nil) -> HealthSampleDTO {
        HealthSampleDTO(metric: "sleep", value: seconds, unit: "sec",
                        startTs: start, endTs: end,
                        externalSampleId: uuid,
                        dedupKey: dedupKey(metric: "sleep", uuid: uuid, start: start, end: end))
    }

    static func workout(minutes: Double, start: Date, end: Date, uuid: String) -> HealthSampleDTO {
        HealthSampleDTO(metric: "workout", value: minutes, unit: "min",
                        startTs: start, endTs: end,
                        externalSampleId: uuid,
                        dedupKey: "HK-\(uuid)")
    }

    /// Deterministic dedup key. Prefers the platform UUID; otherwise derives one
    /// from the metric + bucket bounds (stable across re-uploads of the same
    /// range). Kept within the server's 80-char column.
    private static func dedupKey(metric: String, uuid: String?, start: Date, end: Date) -> String {
        if let uuid { return "HK-\(uuid)" }
        let s = Int64(start.timeIntervalSince1970)
        let e = Int64(end.timeIntervalSince1970)
        return "\(metric)|\(s)|\(e)"
    }
}
