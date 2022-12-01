import Foundation
import Yosemite

protocol AnalyticsHubTimeRangeData {
    var currentDateStart: Date? { get }
    var currentDateEnd: Date? { get }
    var previousDateStart: Date? { get }
    var previousDateEnd: Date? { get }

    init(referenceDate: Date, currentCalendar: Calendar)
}

private extension AnalyticsHubTimeRangeData {
    var currentTimeRange: AnalyticsHubTimeRange? {
        generateTimeRangeFrom(startDate: currentDateStart, endDate: currentDateEnd)
    }

    var previousTimeRange: AnalyticsHubTimeRange? {
        generateTimeRangeFrom(startDate: previousDateStart, endDate: previousDateEnd)
    }

    private func generateTimeRangeFrom(startDate: Date?, endDate: Date?) -> AnalyticsHubTimeRange? {
        if let startDate = startDate,
           let endDate = endDate {
            return AnalyticsHubTimeRange(start: startDate, end: endDate)
        } else {
            return nil
        }
    }
}

/// Main source of time ranges of the Analytics Hub, responsible for providing the current and previous dates
/// for a given Date and range Type alongside their UI descriptions
///
public class AnalyticsHubTimeRangeSelection {
    private let currentTimeRange: AnalyticsHubTimeRange?
    private let previousTimeRange: AnalyticsHubTimeRange?
    private let currentRangeDescription: String?
    private let previousRangeDescription: String?
    let rangeSelectionDescription: String

    //TODO: abandon usage of the ISO 8601 Calendar and build one based on the Site calendar configuration
    init(selectionType: SelectionType,
         currentDate: Date = Date(),
         currentCalendar: Calendar = Calendar(identifier: .iso8601)) {
        self.rangeSelectionDescription = selectionType.description

        var selectionData: AnalyticsHubTimeRangeData
        switch selectionType {
        case .today:
            selectionData = AnalyticsHubDayRangeData(referenceDate: currentDate, currentCalendar: currentCalendar)
        case .weekToDate:
            selectionData = AnalyticsHubWeekRangeData(referenceDate: currentDate, currentCalendar: currentCalendar)
        case .monthToDate:
            selectionData = AnalyticsHubMonthRangeData(referenceDate: currentDate, currentCalendar: currentCalendar)
        case .yearToDate:
            selectionData = AnalyticsHubYearRangeData(referenceDate: currentDate, currentCalendar: currentCalendar)
        }

        let currentTimeRange = selectionData.currentTimeRange
        let previousTimeRange = selectionData.previousTimeRange

        self.currentTimeRange = currentTimeRange
        self.previousTimeRange = previousTimeRange
        self.currentRangeDescription = currentTimeRange?.generateDescription(referenceCalendar: currentCalendar)
        self.previousRangeDescription = previousTimeRange?.generateDescription(referenceCalendar: currentCalendar)

    }

    /// Unwrap the generated selected `AnalyticsHubTimeRange` based on the `selectedTimeRange`
    /// provided during initialization.
    /// - throws an `.selectedRangeGenerationFailed` error if the unwrap fails.
    func unwrapCurrentTimeRange() throws -> AnalyticsHubTimeRange {
        guard let currentTimeRange = currentTimeRange else {
            throw TimeRangeGeneratorError.selectedRangeGenerationFailed
        }
        return currentTimeRange
    }

    /// Unwrap the generated previous `AnalyticsHubTimeRange`relative to the selected one
    /// based on the `selectedTimeRange` provided during initialization.
    /// - throws a `.previousRangeGenerationFailed` error if the unwrap fails.
    func unwrapPreviousTimeRange() throws -> AnalyticsHubTimeRange {
        guard let previousTimeRange = previousTimeRange else {
            throw TimeRangeGeneratorError.previousRangeGenerationFailed
        }
        return previousTimeRange
    }

    /// Generates a date description of the previous time range set internally.
    /// - Returns the Time range in a UI friendly format. If the previous time range is not available,
    /// then returns an presentable error message.
    func generateCurrentRangeDescription() -> String {
        guard let currentTimeRangeDescription = currentRangeDescription else {
            return Localization.noCurrentPeriodAvailable
        }
        return currentTimeRangeDescription
    }

    /// Generates a date description of the previous time range set internally.
    /// - Returns the Time range in a UI friendly format. If the previous time range is not available,
    /// then returns an presentable error message.
    func generatePreviousRangeDescription() -> String {
        guard let previousTimeRangeDescription = previousRangeDescription else {
            return Localization.noPreviousPeriodAvailable
        }
        return previousTimeRangeDescription
    }
}

// MARK: - Time Range Selection Type
extension AnalyticsHubTimeRangeSelection {
    enum SelectionType: CaseIterable {
        case today
        case weekToDate
        case monthToDate
        case yearToDate

        var description: String {
            get {
                switch self {
                case .today:
                    return Localization.today
                case .weekToDate:
                    return Localization.weekToDate
                case .monthToDate:
                    return Localization.monthToDate
                case .yearToDate:
                    return Localization.yearToDate
                }
            }
        }

        static func from(_ statsTimeRange: StatsTimeRangeV4) -> SelectionType {
            switch statsTimeRange {
            case .today:
                return .today
            case .thisWeek:
                return .weekToDate
            case .thisMonth:
                return .monthToDate
            case .thisYear:
                return .yearToDate
            }
        }
    }
}

// MARK: - Constants
extension AnalyticsHubTimeRangeSelection {

    enum TimeRangeGeneratorError: Error {
        case selectedRangeGenerationFailed
        case previousRangeGenerationFailed
    }

    enum Localization {
        static let today = NSLocalizedString("Today", comment: "Title of the Analytics Hub Today's selection range")
        static let weekToDate = NSLocalizedString("Week to Date", comment: "Title of the Analytics Hub Week to Date selection range")
        static let monthToDate = NSLocalizedString("Month to Date", comment: "Title of the Analytics Hub Month to Date selection range")
        static let yearToDate = NSLocalizedString("Year to Date", comment: "Title of the Analytics Hub Year to Date selection range")
        static let selectionTitle = NSLocalizedString("Date Range", comment: "Title of the range selection list")
        static let noCurrentPeriodAvailable = NSLocalizedString("No current period available",
                                                                comment: "A error message when it's not possible to acquire"
                                                                + "the Analytics Hub current selection range")
        static let noPreviousPeriodAvailable = NSLocalizedString("no previous period",
                                                                 comment: "A error message when it's not possible to"
                                                                 + "acquire the Analytics Hub previous selection range")
    }
}
