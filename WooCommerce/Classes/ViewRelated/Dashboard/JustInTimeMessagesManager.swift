import Foundation
import Yosemite

enum AppScreen {
    case dashboard
}

final class JustInTimeMessagesManager {
    private let stores: StoresManager
    private let analytics: Analytics
    private let appScreenJitmSourceMapping: [AppScreen: String] = [.dashboard: "my_store"]

    init(stores: StoresManager = ServiceLocator.stores,
         analytics: Analytics = ServiceLocator.analytics) {
        self.stores = stores
        self.analytics = analytics
    }

    func loadMessage(for screen: AppScreen, siteID: Int64) async throws -> JustInTimeMessageAnnouncementCardViewModel? {
        guard let source = appScreenJitmSourceMapping[screen] else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let action = JustInTimeMessageAction.loadMessage(
                siteID: siteID,
                screen: source,
                hook: .adminNotices) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case let .success(messages):
                        guard let message = messages.first else {
                            return continuation.resume(returning: nil)
                        }
                        self.analytics.track(event:
                                .JustInTimeMessage.fetchSuccess(source: source,
                                                                messageID: message.messageID,
                                                                count: Int64(messages.count)))
                        let viewModel = JustInTimeMessageAnnouncementCardViewModel(
                            justInTimeMessage: message,
                            screenName: source,
                            siteID: siteID)
                        continuation.resume(returning: viewModel)
                    case let .failure(error):
                        self.analytics.track(event:
                                .JustInTimeMessage.fetchFailure(source: source,
                                                                error: error))
                        continuation.resume(throwing: error)
                    }
                }
            Task { @MainActor in
                stores.dispatch(action)
            }
        }
    }
}
