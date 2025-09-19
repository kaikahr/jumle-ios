//
//  ActivityCalendar.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-27.
//
//
//
//  ActivityCalendar.swift
//  jumle
//
//  GitHub-style activity calendar for learning streaks.
//  - No leading/trailing blank columns (weeks are trimmed to the current year)
//  - Adaptive sizing: uses preferred dot size; if it won't fit, enables gentle horizontal scroll
//

import SwiftUI

struct ActivityCalendar: View {
    @EnvironmentObject private var streaks: StreakService

    // UI
    @State private var selectedDate: Date?
    private let rows: Int = 7
    private let spacing: CGFloat = 2
    private let preferredDot: CGFloat = 12   // bump to 14–16 if you want larger dots by default

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let weeks = weeksForCurrentYear()
                let totalSpacing = CGFloat(max(weeks.count - 1, 0)) * spacing
                let minDotToFit = weeks.isEmpty ? preferredDot : (geo.size.width - totalSpacing) / CGFloat(weeks.count)

                // If preferred size fits → render fixed grid.
                // If not → keep preferred size and allow horizontal scroll (so dots stay readable).
                let fits = preferredDot <= minDotToFit
                let dot = fits ? min(preferredDot, minDotToFit) : preferredDot

                Group {
                    if fits {
                        calendarColumns(weeks: weeks, dot: dot)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            calendarColumns(weeks: weeks, dot: dot)
                                .padding(.horizontal, 2)
                        }
                    }
                }
            }
            // exact height: 7 rows of dots + 6 gaps
            .frame(height: preferredDot * CGFloat(rows) + spacing * CGFloat(rows - 1))

            legend
                .padding(.horizontal, 6)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Grid builder

    @ViewBuilder
    private func calendarColumns(weeks: [Date], dot: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(weeks.indices, id: \.self) { wIdx in
                let weekStart = weeks[wIdx]
                VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { dayIndex in
                        let date = Calendar.current.date(byAdding: .day, value: dayIndex, to: weekStart)!
                        if isDateInCurrentYear(date) {
                            DayDot(
                                date: date,
                                activityLevel: streaks.getActivityLevel(for: date),
                                isSelected: selectedDate == date
                            )
                            .frame(width: dot, height: dot)
                            .onTapGesture { selectedDate = date }
                            .accessibilityLabel(Text(label(for: date)))
                        } else {
                            // keep column alignment without painting a visible square
                            Color.clear.frame(width: dot, height: dot)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                Rectangle().fill(Color(.systemGray5)).frame(width: 8, height: 8).cornerRadius(1)
                Rectangle().fill(Color.orange.opacity(0.5)).frame(width: 8, height: 8).cornerRadius(1)
                Rectangle().fill(Color.green).frame(width: 8, height: 8).cornerRadius(1)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    private func label(for date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    private func isDateInCurrentYear(_ date: Date) -> Bool {
        let cal = Calendar.current
        let curYear = cal.component(.year, from: Date())
        return cal.component(.year, from: date) == curYear
    }

    /// Weeks that actually intersect the current calendar year.
    /// This removes the left/right “white columns” you were seeing.
    private func weeksForCurrentYear() -> [Date] {
        let cal = Calendar.current

        // Jan 1 of current year
        let startOfYear = cal.dateInterval(of: .year, for: Date())!.start
        // Dec 31 (23:59…) of current year
        let endOfYear = cal.date(byAdding: DateComponents(year: 1, day: -1), to: startOfYear)!

        var weekStart = cal.dateInterval(of: .weekOfYear, for: startOfYear)!.start
        let lastWeekStart = cal.dateInterval(of: .weekOfYear, for: endOfYear)!.start

        var weeks: [Date] = []
        while weekStart <= lastWeekStart {
            weeks.append(weekStart)
            weekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
        }
        return weeks
    }
}

// MARK: - DayDot

struct DayDot: View {
    let date: Date
    let activityLevel: StreakService.ActivityLevel
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .fill(colorForLevel)
            .cornerRadius(2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1)
            )
    }

    private var colorForLevel: Color {
        switch activityLevel {
        case .none: return Color(.systemGray5)
        case .low:  return Color.orange.opacity(0.5)
        case .high: return Color.green
        }
    }
}
