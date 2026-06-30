//  DateFormatters.swift
//  Ravns
//
//  Shared formatters — DateFormatter allocation is expensive, so reuse a single instance.

import Foundation

enum DateFormatters {
    /// "yyyy-MM-dd" — the date format used by settings, the cloud app_state row, and plan edits.
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
