import Foundation
import Yosemite
import protocol Storage.StorageManagerType

final class PluginListViewModel {

    /// Current state of the plugin list
    ///
    @Published var pluginListState: PluginListState = .results

    /// ID of the site to load plugins for
    ///
    private let siteID: Int64

    /// Reference to the StoresManager to dispatch Yosemite Actions.
    ///
    private let storesManager: StoresManager

    /// StorageManager to load plugins from storage
    ///
    private let storageManager: StorageManagerType

    /// Results controller for the plugin list
    ///
    private lazy var resultsController: ResultsController<StorageSitePlugin> = {
        let predicate = NSPredicate(format: "siteID = %ld", self.siteID)
        let nameDescriptor = NSSortDescriptor(keyPath: \StorageSitePlugin.name, ascending: true)
        let statusDescriptor = NSSortDescriptor(keyPath: \StorageSitePlugin.status, ascending: true)
        return ResultsController<StorageSitePlugin>(
            storageManager: storageManager,
            sectionNameKeyPath: "status",
            matching: predicate,
            sortedBy: [statusDescriptor, nameDescriptor]
        )
    }()

    init(siteID: Int64,
         storesManager: StoresManager = ServiceLocator.stores,
         storageManager: StorageManagerType = ServiceLocator.storageManager) {
        self.siteID = siteID
        self.storesManager = storesManager
        self.storageManager = storageManager
    }

    /// Start fetching plugin data from local storage.
    ///
    func activate(onDataChanged: @escaping () -> Void) {
        do {
            try resultsController.performFetch()
        } catch {
            DDLogError("⛔️ Error fetching plugin list!")
        }

        resultsController.onDidChangeContent = onDataChanged
    }

    /// Manually resync plugins.
    ///
    func resyncPlugins(onComplete: @escaping () -> Void) {
        pluginListState = .syncing
        let action = SitePluginAction.synchronizeSitePlugins(siteID: siteID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.pluginListState = .results
            case .failure:
                self.pluginListState = .error
            }
            onComplete()
        }
        storesManager.dispatch(action)
    }
}

// MARK: - Data source for plugin list
//
extension PluginListViewModel {
    /// Number of sections to display on the table view.
    ///
    var numberOfSections: Int {
        resultsController.sections.count
    }

    /// Title of table view section at specified index.
    ///
    func titleForSection(at index: Int) -> String? {
        guard let rawStatus = resultsController.sections[safe: index]?.name else {
            return nil
        }
        let pluginStatus = SitePluginStatusEnum(rawValue: rawStatus)
        let sectionTitle: String
        switch pluginStatus {
        case .active:
            sectionTitle = NSLocalizedString("Active Plugins", comment: "Title for table view section of active plugins")
        case .inactive:
            sectionTitle = NSLocalizedString("Inactive Plugins", comment: "Title for table view section of inactive plugins")
        case .networkActive:
            sectionTitle = NSLocalizedString("Network Active Plugins", comment: "Title for table view section of network active plugins")
        case .unknown:
            sectionTitle = "" // This case should not happen
        }
        return sectionTitle.capitalized
    }

    /// Number of rows in a specified table view section index.
    ///
    func numberOfRows(inSection sectionIndex: Int) -> Int {
        resultsController.sections[safe: sectionIndex]?.objects.count ?? 0
    }

    /// View model for the table view cell at specified index path.
    ///
    func cellModelForRow(at indexPath: IndexPath) -> PluginListCellViewModel {
        let plugin = resultsController.object(at: indexPath)
        // The description can sometimes contain HTML tags
        // so it's best to be extra safe by removing those tags
        return PluginListCellViewModel(
            name: plugin.name,
            description: plugin.descriptionRaw.removedHTMLTags
        )
    }
}

// MARK: - Model for plugin list cells
//
struct PluginListCellViewModel {
     let name: String
     let description: String
 }

// MARK: - Nested Types
//
extension PluginListViewModel {
    /// States for the Plugin List screen
    ///
    enum PluginListState {
        case results
        case syncing
        case error
    }
}
