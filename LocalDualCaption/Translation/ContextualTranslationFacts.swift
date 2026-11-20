import Foundation

/// Weekday identities for rejecting changed facts in generated translations.
enum ContextualTranslationFacts {
    private static let names: [String: [String]] = [
        "en": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
        "de": ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"],
        "es": ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"],
        "fr": ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"],
        "it": ["lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica"],
        "pt": ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"],
        "ja": ["月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日", "日曜日"],
        "ko": ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"],
        "zh": ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    ]

    static func detectedWeekdays(in text: String) -> Set<Int> {
        var result: Set<Int> = []
        for (language, days) in names {
            for (day, name) in days.enumerated() {
                let terms: [String]
                if language == "zh" {
                    let suffixes = day == 6 ? ["日", "天"] : [["一", "二", "三", "四", "五", "六"][day]]
                    terms = suffixes.flatMap { suffix in ["周", "週", "星期", "礼拜", "禮拜"].map { $0 + suffix } }
                } else if language == "ja" { terms = [name, String(name.dropLast())] }
                else { terms = [name] }
                var pattern = terms.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
                if !["zh", "ja", "ko"].contains(language) { pattern = "(?<!\\p{L})(?:" + pattern + ")(?!\\p{L})" }
                let expression = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                if expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil { result.insert(day) }
            }
        }
        return result
    }

}
