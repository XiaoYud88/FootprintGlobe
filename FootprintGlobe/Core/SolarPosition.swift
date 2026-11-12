import Foundation

/// 太阳位置（够用的天文近似，误差 < 0.5°，用来画晨昏线完全足够）。
///
/// 不做完整 NOAA 迭代，只保留三个量：
/// - 赤纬（declination）：太阳直射点纬度，随季节在 ±23.44° 之间移动
/// - 时差（equation of time）：真太阳时与平太阳时的差，最大 ±16 分钟
/// - 直射点经度：由 UTC 时刻 + 时差反推
enum SolarPosition {
    /// 太阳直射点（经纬度）。经度用 -180…180。
    static func subsolarPoint(at date: Date) -> GeoCoord {
        let rad = 2 * Double.pi
        let days = dayOfYear(date)
        let hour = utcHour(date)
        // 分数年（单位：弧度）
        let gamma = rad / 365.0 * (days - 1 + (hour - 12) / 24)

        // 赤纬
        let decl = 0.006918
            - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.001480 * sin(3 * gamma)

        // 时差（分钟）
        let minutes = 229.18 * (0.000075
            + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))

        var lon = -15.0 * (hour + minutes / 60.0 - 12.0)
        lon = ((lon + 180).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) - 180

        return GeoCoord(lon: lon, lat: decl * 180 / .pi)
    }

    /// 某点在给定时刻的太阳高度角余弦（> 0 是白天）。
    static func sunCosine(at point: GeoCoord, sun: GeoCoord) -> Double {
        let lat1 = point.lat * .pi / 180
        let lat2 = sun.lat * .pi / 180
        let dLon = (point.lon - sun.lon) * .pi / 180
        return sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(dLon)
    }

    static func isDaylight(at point: GeoCoord, sun: GeoCoord) -> Bool {
        sunCosine(at: point, sun: sun) > 0
    }

    /// 月相（0 = 新月，0.5 = 满月，1 = 下一个新月），用简化的朔望月推算。
    static func moonPhase(at date: Date) -> Double {
        let synodic = 29.530_588_67
        // 2000-01-06 18:14 UTC 是一次新月
        let reference = Date(timeIntervalSince1970: 947_182_440)
        let days = date.timeIntervalSince(reference) / 86_400
        let phase = days.truncatingRemainder(dividingBy: synodic) / synodic
        return phase < 0 ? phase + 1 : phase
    }

    /// 今晚月亮「亮面比例」，0…1，画月亮用。
    static func moonIllumination(at date: Date) -> Double {
        let phase = moonPhase(at: date)
        return (1 - cos(2 * .pi * phase)) / 2
    }

    // MARK: - 辅助

    private static func dayOfYear(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0))
        return Double(day) + seconds / 86_400 - 1
    }

    private static func utcHour(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(comps.hour ?? 0)
            + Double(comps.minute ?? 0) / 60
            + Double(comps.second ?? 0) / 3600
    }
}
