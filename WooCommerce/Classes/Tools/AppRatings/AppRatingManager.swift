import Foundation

/// This class will help track whether or not a user should be prompted for an
/// app review.  This class is loosely based on
/// [Appirater](https://github.com/arashpayan/appirater)
///
public class AppRatingManager {
    /// Sets the number of system wide significant events are required when
    /// calling `shouldPromptForAppReview`. Ideally this number should be a
    /// number less than the total of all the significant event counts for each
    /// section so as to trigger the review prompt for a fairly active user who
    /// uses the app in a broad fashion.
    ///
    var systemWideSignificantEventCountRequiredForPrompt: Int = 1

    /// Sets the number of days that have to pass between AppReview prompts
    /// Apple only allows 3 prompts per year. We're trying to be a bit more conservative and are doing
    /// up to 2 times a year (183 = round(365/2)).
    var numberOfDaysToWaitBetweenPrompts: Int = 183

    private let defaults: UserDefaults
    private var sections = [String: Section]()

    /// Don't prompt for reviews for internal builds
    /// http://stackoverflow.com/questions/26081543/how-to-tell-at-runtime-whether-an-ios-app-is-running-through-a-testflight-beta-i?noredirect=1&lq=1
    ///
    private var promptingDisabledLocal: Bool = {
        guard let path = Bundle.main.appStoreReceiptURL?.path else {
            return false
        }
        return path.contains("sandboxReceipt")
    }()

    private var promptingDisabled: Bool {
        return promptingDisabledLocal
    }

    static let shared = AppRatingManager(defaults: .standard)

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// This should be called with the current App Version so as to setup
    /// internal tracking.
    ///
    /// - Parameters:
    ///     - version: version number of the app, e.g. CFBundleShortVersionString
    ///
    func setVersion(_ version: String) {
        let trackingVersion = defaults.string(forKey: Key.currentVersion) ?? version
        defaults.set(version, forKey: Key.currentVersion)

        if trackingVersion == version {
            incrementUseCount()
        } else {
            let shouldSkipRating = shouldSkipRatingForCurrentVersion()
            resetValuesForNewVersion()
            resetReviewPromptDisabledStatus()
            if shouldSkipRating {
                checkNewVersionNeedsSkipping()
            }
        }
    }

    /// Registers a granular section to be tracked
    ///
    /// - Parameters:
    ///     - section: Section name, e.g. "Notifications"
    ///     - significantEventCount: The number of significant events required to trigger an app rating prompt for this particular section.
    ///
    func register(section: String, significantEventCount count: Int) {
        sections[section] = Section(significantEventCount: count, enabled: true)
    }

    /// Increments significant events app wide.
    ///
    func incrementSignificantEvent() {
        incrementStoredValue(key: Key.significantEventCount)
    }

    /// Increments significant events for just this particular section.
    ///
    func incrementSignificantEvent(section: String) {
        guard sections[section] != nil else {
            assertionFailure("Invalid section \(section)")
            return
        }
        let key = significantEventCountKey(section: section)
        incrementStoredValue(key: key)
    }

    /// Indicates that the user didn't want to review the app or leave feedback
    /// for this version.
    ///
    func declinedToRateCurrentVersion() {
        defaults.set(true, forKey: Key.declinedToRateCurrentVersion)
        defaults.set(2, forKey: Key.numberOfVersionsToSkipPrompting)
    }

    /// Indicates that the user decided to give feedback for this version.
    ///
    func gaveFeedbackForCurrentVersion() {
        defaults.set(true, forKey: Key.gaveFeedbackForCurrentVersion)
    }

    /// Indicates that the use rated the current version of the app.
    ///
    func ratedCurrentVersion() {
        defaults.set(true, forKey: Key.ratedCurrentVersion)
    }

    /// Indicates that the user didn't like the current version of the app.
    ///
    func dislikedCurrentVersion() {
        incrementStoredValue(key: Key.userDislikeCount)
        defaults.set(true, forKey: Key.dislikedCurrentVersion)
        defaults.set(2, forKey: Key.numberOfVersionsToSkipPrompting)
    }

    /// Indicates the user did like the current version of the app.
    ///
    func likedCurrentVersion() {
        incrementStoredValue(key: Key.userLikeCount)
        defaults.set(true, forKey: Key.likedCurrentVersion)
        defaults.set(1, forKey: Key.numberOfVersionsToSkipPrompting)
    }

    /// Indicates whether enough time has passed since we last prompted the user for their opinion.
    ///
    func enoughTimePassedSinceLastPrompt()-> Bool {
        if let lastPromptDate = defaults.value(forKeyPath: Key.lastPromptToRateDate),
            let date = lastPromptDate as? Date,
            let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day {
            return days > numberOfDaysToWaitBetweenPrompts
        }
        return true
    }

    /// Checks if the user should be prompted for an app review based on
    /// `systemWideSignificantEventsCount` and also if the user hasn't been
    /// configured to skip being prompted for this release.
    ///
    /// Note that this method will check to see if app review prompts on a
    /// global basis have been shut off.
    ///
    func shouldPromptForAppReview() -> Bool {
        if !enoughTimePassedSinceLastPrompt()
            || shouldSkipRatingForCurrentVersion()
            || promptingDisabled {
            return false
        }

        let events = systemWideSignificantEventCount()
        let required = systemWideSignificantEventCountRequiredForPrompt
        return events >= required
    }

    /// Checks if the user should be prompted for an app review based on the
    /// number of significant events configured for this particular section and
    /// if the user hasn't been configured to skip being prompted for this
    /// release.
    ///
    /// Note that this method will check to see if prompts for this section have
    /// been shut off entirely.
    ///
    func shouldPromptForAppReview(section name: String) -> Bool {
        guard let section = sections[name] else {
            assertionFailure("Invalid section \(name)")
            return false
        }

        if !enoughTimePassedSinceLastPrompt()
            || shouldSkipRatingForCurrentVersion()
            || promptingDisabled
            || !section.enabled {
            return false
        }

        let key = significantEventCountKey(section: name)
        let events = defaults.integer(forKey: key)
        let required = section.significantEventCount
        return events >= required
    }

    /// Checks if the user has ever indicated that they like the app.
    ///
    func hasUserEverLikedApp() -> Bool {
        return defaults.integer(forKey: Key.userLikeCount) > 0
    }

    /// Checks if the user has ever indicated they dislike the app.
    ///
    func hasUserEverDislikedApp() -> Bool {
        return defaults.integer(forKey: Key.userDislikeCount) > 0
    }

    // MARK: - Private

    private func incrementUseCount() {
        incrementStoredValue(key: Key.useCount)
    }

    private func significantEventCountKey(section: String) -> String {
        return "\(Key.significantEventCount)_\(section)"
    }

    private func resetValuesForNewVersion() {
        defaults.removeObject(forKey: Key.significantEventCount)
        defaults.removeObject(forKey: Key.ratedCurrentVersion)
        defaults.removeObject(forKey: Key.declinedToRateCurrentVersion)
        defaults.removeObject(forKey: Key.gaveFeedbackForCurrentVersion)
        defaults.removeObject(forKey: Key.dislikedCurrentVersion)
        defaults.removeObject(forKey: Key.likedCurrentVersion)
        defaults.removeObject(forKey: Key.skipRatingCurrentVersion)
        for sectionName in sections.keys {
            defaults.removeObject(forKey: significantEventCountKey(section: sectionName))
        }
    }

    private func resetReviewPromptDisabledStatus() {
        for key in sections.keys {
            sections[key]?.enabled = true
        }
    }

    private func checkNewVersionNeedsSkipping() {
        let toSkip = defaults.integer(forKey: Key.numberOfVersionsToSkipPrompting)
        let skipped = defaults.integer(forKey: Key.numberOfVersionsSkippedPrompting)

        if toSkip > 0 {
            if skipped < toSkip {
                defaults.set(skipped + 1, forKey: Key.numberOfVersionsSkippedPrompting)
                defaults.set(true, forKey: Key.skipRatingCurrentVersion)
            } else {
                defaults.removeObject(forKey: Key.numberOfVersionsSkippedPrompting)
                defaults.removeObject(forKey: Key.numberOfVersionsToSkipPrompting)
            }
        }
    }

    private func shouldSkipRatingForCurrentVersion() -> Bool {
        let interactedWithAppReview = defaults.bool(forKey: Key.ratedCurrentVersion)
            || defaults.bool(forKey: Key.declinedToRateCurrentVersion)
            || defaults.bool(forKey: Key.gaveFeedbackForCurrentVersion)
            || defaults.bool(forKey: Key.likedCurrentVersion)
            || defaults.bool(forKey: Key.dislikedCurrentVersion)
        let skipRatingCurrentVersion = defaults.bool(forKey: Key.skipRatingCurrentVersion)
        return interactedWithAppReview || skipRatingCurrentVersion
    }

    private func incrementStoredValue(key: String) {
        var value = defaults.integer(forKey: key)
        value += 1
        defaults.set(value, forKey: key)
    }

    private func systemWideSignificantEventCount() -> Int {
        var total = defaults.integer(forKey: Key.significantEventCount)
        sections.keys.map(significantEventCountKey).forEach { key in
            total += defaults.integer(forKey: key)
        }
        return total
    }


    // MARK: - Testing

    // Overrides promptingDisabledLocal. For testing purposes only.
    //
    func _overridePromptingDisabledLocal(_ disabled: Bool) {
        promptingDisabledLocal = disabled
    }

    // Overrides lastPromptToRateDate. For testing purposes only.
    //
    func _overrideLastPromptToRateDate(_ date: Date) {
        defaults.set(date, forKey: Key.lastPromptToRateDate)
    }

    // MARK: - Subtypes

    private struct Section {
        var significantEventCount: Int
        var enabled: Bool
    }

    // MARK: - Constants

    private enum Key {
        static let currentVersion = "AppRatingCurrentVersion"

        static let significantEventCount = "AppRatingSignificantEventCount"
        static let useCount = "AppRatingUseCount"
        static let numberOfVersionsSkippedPrompting = "AppRatingsNumberOfVersionsSkippedPrompt"
        static let numberOfVersionsToSkipPrompting = "AppRatingsNumberOfVersionsToSkipPrompting"
        static let skipRatingCurrentVersion = "AppRatingsSkipRatingCurrentVersion"
        static let ratedCurrentVersion = "AppRatingRatedCurrentVersion"
        static let declinedToRateCurrentVersion = "AppRatingDeclinedToRateCurrentVersion"
        static let gaveFeedbackForCurrentVersion = "AppRatingGaveFeedbackForCurrentVersion"
        static let dislikedCurrentVersion = "AppRatingDislikedCurrentVersion"
        static let likedCurrentVersion = "AppRatingLikedCurrentVersion"
        static let userLikeCount = "AppRatingUserLikeCount"
        static let userDislikeCount = "AppRatingUserDislikeCount"
        static let lastPromptToRateDate = "AppRatingLastPromptToRateDate"
    }

    enum Constants {
        static let defaultAppReviewURL = URL(string: "https://itunes.apple.com/us/app/id1389130815?mt=8&action=write-review")!
    }
}
