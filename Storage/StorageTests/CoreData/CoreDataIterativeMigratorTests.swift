import XCTest
import TestKit
import CocoaLumberjack
import CoreData
@testable import Storage

/// Test cases for `CoreDataIterativeMigrator`.
///
/// Test cases for migrating from a model version to another should be in `MigrationTests`.
///
final class CoreDataIterativeMigratorTests: XCTestCase {
    private var modelsInventory: ManagedObjectModelsInventory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        DDLog.add(DDOSLogger.sharedInstance)
        modelsInventory = try .from(packageName: "WooCommerce", bundle: Bundle(for: CoreDataManager.self))
    }

    override func tearDown() {
        modelsInventory = nil
        DDLog.remove(DDOSLogger.sharedInstance)
        super.tearDown()
    }

    /// Tests that model versions are not compatible with each other.
    ///
    /// This protects us from mistakes like adding a new model version that has **no structural
    /// changes** and not setting the Hash Modifier. An example of that is creating a new model
    /// but only renaming the entity classes. If we forget to change the model's Hash Modifier,
    /// then the `CoreDataManager.migrateDataModelIfNecessary` will (correctly) **skip** the
    /// migration. See here for more information: https://tinyurl.com/yxzpwp7t.
    ///
    /// This loops through **all NSManagedObjectModels**, performs a migration, and checks for
    /// compatibility with all the other versions. For example, for "Model 3":
    ///
    /// 1. Migrate the store from previous model (Model 2) to Model 3.
    /// 2. Check that Model 3 is compatible with the _migrated_ store. This verifies the migration.
    /// 3. Check that Models 1, 2, 4, 5, 6, 7, and so on are **not** compatible with the _migrated_ store.
    ///
    /// ## Testing
    ///
    /// You can make this test fail by:
    ///
    /// 1. Creating a new model version for `WooCommerce.xcdatamodeld`, copying the latest version.
    /// 2. Running this test.
    ///
    /// And then make this pass again by setting a Hash Modifier value for the new model.
    ///
    func test_all_model_versions_are_not_compatible_with_each_other() throws {
        // Given
        // Use in-memory type or else this would be too slow.
        let storeType = NSInMemoryStoreType
        let storeURL = try XCTUnwrap(NSURL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)?
            .appendingPathExtension("sqlite"))

        // Cache the models to improve the performance of the loop below.
        let modelsByVersionName = try modelsInventory.versions.reduce(into: [String: NSManagedObjectModel]()) { result, version in
            result[version.name] = try XCTUnwrap(modelsInventory.model(for: version))
        }

        try modelsInventory.versions.forEach { currentVersion in
            // Given
            let currentModel = try XCTUnwrap(modelsByVersionName[currentVersion.name])

            // When
            // Migrate to the currentVersion if this is not the first version in the list.
            if modelsInventory.versions.first != currentVersion {
                let migrator = CoreDataIterativeMigrator(modelsInventory: modelsInventory)
                let (isMigrationSuccessful, _) =
                    try migrator.iterativeMigrate(sourceStore: storeURL, storeType: storeType, to: currentModel)
                XCTAssertTrue(isMigrationSuccessful)
            }

            // Load the persistent container
            let persistentContainer =
                makePersistentContainer(storeURL: storeURL, storeType: storeType, model: currentModel)
            let loadingError: Error? = try waitFor { promise in
                persistentContainer.loadPersistentStores { _, error in
                    promise(error)
                }
            }
            XCTAssertNil(loadingError)

            let persistentStoreCoordinator = persistentContainer.persistentStoreCoordinator
            let persistentStore = try XCTUnwrap(persistentStoreCoordinator.persistentStores.first)

            // Then
            // The current model should be compatible with the current persistent store
            XCTAssertTrue(currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: persistentStore.metadata),
                          "Current model “\(currentVersion.name)” should be compatible with the persistentStore.")

            // All other versions should not be compatible with the current persistentStore
            try modelsInventory.versions.filter {
                $0 != currentVersion
            }.forEach { version in
                let model = try XCTUnwrap(modelsByVersionName[version.name])
                XCTAssertFalse(model.isConfiguration(withName: nil, compatibleWithStoreMetadata: persistentStore.metadata),
                               "Model “\(version.name)” should not be compatible with the persistentStore whose version is “\(currentVersion.name)”.")
            }
        }
    }

    func test_it_will_not_migrate_if_the_database_file_does_not_exist() throws {
        // Given
        let targetModel = try managedObjectModel(for: "Model 28")
        let databaseURL = documentsDirectory.appendingPathComponent("database-file-that-does-not-exist")
        let fileManager = MockFileManager()

        fileManager.whenCheckingIfFileExists(atPath: databaseURL.path, thenReturn: false)

        let migrator = CoreDataIterativeMigrator(modelsInventory: modelsInventory, fileManager: fileManager)

        // When
        let result = try migrator.iterativeMigrate(sourceStore: databaseURL,
                                                   storeType: NSSQLiteStoreType,
                                                   to: targetModel)

        // Then
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.debugMessages.isEmpty)
        XCTAssertEqual(fileManager.fileExistsInvocationCount, 1)
        XCTAssertEqual(fileManager.allMethodsInvocationCount, 1)
    }

    /// This is more like a confidence-check that Core Data does not allow us to open SQLite
    /// files using the wrong `NSManagedObjectModel`.
    func test_opening_a_store_with_a_different_model_fails() throws {
        // Given
        let model1 = try managedObjectModel(for: "Model")
        let model10 = try managedObjectModel(for: "Model 10")

        let storeURL = urlForStore(withName: "Woo Test 10.sqlite", deleteIfExists: true)
        let options = [NSInferMappingModelAutomaticallyOption: false, NSMigratePersistentStoresAutomaticallyOption: false]

        // When
        var psc = NSPersistentStoreCoordinator(managedObjectModel: model1)
        var ps = try? psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)

        XCTAssertNotNil(ps)

        try psc.remove(ps!)

        // Load using a different model
        psc = NSPersistentStoreCoordinator(managedObjectModel: model10)
        ps = try? psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)

        // When
        XCTAssertNil(ps)
    }

    /// Test the IterativeMigrator can migrate iteratively between model 1 to 10.
    func test_iterativeMigrate_can_iteratively_migrate_from_model_1_to_model_10() throws {
        // Given
        let model1 = try managedObjectModel(for: "Model")
        let model10 = try managedObjectModel(for: "Model 10")

        let storeURL = urlForStore(withName: "Woo Test 10.sqlite", deleteIfExists: true)
        let options = [NSInferMappingModelAutomaticallyOption: false, NSMigratePersistentStoresAutomaticallyOption: false]

        var psc = NSPersistentStoreCoordinator(managedObjectModel: model1)
        var ps = try? psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
        XCTAssertNotNil(ps)

        try psc.remove(ps!)

        // When
        do {
            let iterativeMigrator = CoreDataIterativeMigrator(modelsInventory: modelsInventory)
            let (result, _) = try iterativeMigrator.iterativeMigrate(sourceStore: storeURL,
                                                                     storeType: NSSQLiteStoreType,
                                                                     to: model10)
            XCTAssertTrue(result)
        } catch {
            XCTFail("Error when attempting to migrate: \(error)")
        }

        // Then
        psc = NSPersistentStoreCoordinator(managedObjectModel: model10)
        ps = try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
        XCTAssertNotNil(ps)
    }

    func test_model_26_to_27_migration_passed() throws {
        // Arrange
        let model26URL = urlForModel(name: "Model 26")
        let model26 = NSManagedObjectModel(contentsOf: model26URL)!
        let model27URL = urlForModel(name: "Model 27")
        let model27 = NSManagedObjectModel(contentsOf: model27URL)!
        let name = "WooCommerce"
        let crashLogger = MockCrashLogger()
        let coreDataManager = CoreDataManager(name: name, crashLogger: crashLogger)

        // Destroys any pre-existing persistence store.
        let psc = NSPersistentStoreCoordinator(managedObjectModel: modelsInventory.currentModel)
        try psc.destroyPersistentStore(at: coreDataManager.storeURL, ofType: NSSQLiteStoreType, options: nil)

        // Action - step 1: loading persistence store with model 26
        let model26Container = NSPersistentContainer(name: name, managedObjectModel: model26)
        model26Container.persistentStoreDescriptions = [coreDataManager.storeDescription]

        var model26LoadingError: Error?
        waitForExpectation { expectation in
            model26Container.loadPersistentStores { (storeDescription, error) in
                model26LoadingError = error
                expectation.fulfill()
            }
        }

        // Assert - step 1
        XCTAssertNil(model26LoadingError, "Migration error: \(String(describing: model26LoadingError?.localizedDescription))")

        guard let metadata = try? NSPersistentStoreCoordinator
            .metadataForPersistentStore(ofType: NSSQLiteStoreType,
                                        at: coreDataManager.storeURL,
                                        options: nil) else {
                                            XCTFail("Cannot get metadata for persistent store at URL \(coreDataManager.storeURL)")
                                            return
        }

        // The persistent store should be compatible with model 26 now and incompatible with model 27.
        XCTAssertTrue(model26.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
        XCTAssertFalse(model27.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))

        // Arrange - step 2: populating data, migrating persistent store from model 26 to 27, then loading with model 27.
        let context = model26Container.viewContext
        _ = insertAccountWithRequiredProperties(to: context)
        let product = insertProductWithRequiredProperties(to: context)
        let productCategory = insertProductCategoryWithRequiredProperties(to: context)
        product.addToCategories([productCategory])
        context.saveIfNeeded()

        XCTAssertEqual(context.countObjects(ofType: Account.self), 1)
        XCTAssertEqual(context.countObjects(ofType: Product.self), 1)
        XCTAssertEqual(context.countObjects(ofType: ProductCategory.self), 1)

        let model27Container = NSPersistentContainer(name: name, managedObjectModel: model27)
        model27Container.persistentStoreDescriptions = [coreDataManager.storeDescription]

        // Action - step 2
        let iterativeMigrator = CoreDataIterativeMigrator(modelsInventory: modelsInventory)
        let (migrateResult, migrationDebugMessages) = try iterativeMigrator.iterativeMigrate(sourceStore: coreDataManager.storeURL,
                                                                                             storeType: NSSQLiteStoreType,
                                                                                             to: model27)
        XCTAssertTrue(migrateResult, "Failed to migrate to model version 27: \(migrationDebugMessages)")

        var model27LoadingError: Error?
        waitForExpectation { expectation in
            model27Container.loadPersistentStores { (storeDescription, error) in
                model27LoadingError = error
                expectation.fulfill()
            }
        }

        // Assert - step 2
        XCTAssertNil(model27LoadingError, "Migration error: \(String(describing: model27LoadingError?.localizedDescription))")

        XCTAssertEqual(model27Container.viewContext.countObjects(ofType: Account.self), 1)
        XCTAssertEqual(model27Container.viewContext.countObjects(ofType: Product.self), 1)
        // Product categories should be deleted.
        XCTAssertEqual(model27Container.viewContext.countObjects(ofType: ProductCategory.self), 0)
    }

  func test_model_28_to_29_migration_passed() throws {
        // Arrange
        let model28URL = urlForModel(name: "Model 28")
        let model28 = NSManagedObjectModel(contentsOf: model28URL)!
        let model29URL = urlForModel(name: "Model 29")
        let model29 = NSManagedObjectModel(contentsOf: model29URL)!
        let name = "WooCommerce"
        let crashLogger = MockCrashLogger()
        let coreDataManager = CoreDataManager(name: name, crashLogger: crashLogger)

        // Destroys any pre-existing persistence store.
        let psc = NSPersistentStoreCoordinator(managedObjectModel: modelsInventory.currentModel)
        try? psc.destroyPersistentStore(at: coreDataManager.storeURL, ofType: NSSQLiteStoreType, options: nil)

        // Action - step 1: loading persistence store with model 28
        let model28Container = NSPersistentContainer(name: name, managedObjectModel: model28)
        model28Container.persistentStoreDescriptions = [coreDataManager.storeDescription]

        var model28LoadingError: Error?
        waitForExpectation { expectation in
            model28Container.loadPersistentStores { (storeDescription, error) in
                model28LoadingError = error
                expectation.fulfill()
            }
        }

        // Assert - step 1
        XCTAssertNil(model28LoadingError, "Migration error: \(String(describing: model28LoadingError?.localizedDescription))")

        guard let metadata = try? NSPersistentStoreCoordinator
            .metadataForPersistentStore(ofType: NSSQLiteStoreType,
                                        at: coreDataManager.storeURL,
                                        options: nil) else {
                                            XCTFail("Cannot get metadata for persistent store at URL \(coreDataManager.storeURL)")
                                            return
        }

        // The persistent store should be compatible with model 28 now and incompatible with model 29.
        XCTAssertTrue(model28.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
        XCTAssertFalse(model29.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))

        // Arrange - step 2: populating data, migrating persistent store from model 28 to 29, then loading with model 29.
        let context = model28Container.viewContext
        _ = insertAccountWithRequiredProperties(to: context)
        let product = insertProductWithRequiredProperties(to: context)
        let productTag = insertProductTag(to: context)
        product.addToTags(productTag)
        context.saveIfNeeded()

        XCTAssertEqual(context.countObjects(ofType: Account.self), 1)
        XCTAssertEqual(context.countObjects(ofType: Product.self), 1)
        XCTAssertEqual(context.countObjects(ofType: ProductTag.self), 1)

        let model29Container = NSPersistentContainer(name: name, managedObjectModel: model29)
        model29Container.persistentStoreDescriptions = [coreDataManager.storeDescription]

        // Action - step 2
        let iterativeMigrator = CoreDataIterativeMigrator(modelsInventory: modelsInventory)
        let (migrateResult, migrationDebugMessages) = try iterativeMigrator.iterativeMigrate(sourceStore: coreDataManager.storeURL,
                                                                                             storeType: NSSQLiteStoreType,
                                                                                             to: model29)
        XCTAssertTrue(migrateResult, "Failed to migrate to model version 29: \(migrationDebugMessages)")

        var model29LoadingError: Error?
        waitForExpectation { expectation in
            model29Container.loadPersistentStores { (storeDescription, error) in
                model29LoadingError = error
                expectation.fulfill()
            }
        }

        // Assert - step 2
        XCTAssertNil(model29LoadingError, "Migration error: \(String(describing: model29LoadingError?.localizedDescription))")

        XCTAssertEqual(model29Container.viewContext.countObjects(ofType: Account.self), 1)
        XCTAssertEqual(model29Container.viewContext.countObjects(ofType: Product.self), 1)
        // Product tags should be deleted.
        XCTAssertEqual(model29Container.viewContext.countObjects(ofType: ProductTag.self), 0)
    }

    func test_model_20_to_28_migration_with_transformable_attributes_passed() throws {
        // Arrange
        let sourceModelURL = urlForModel(name: "Model 20")
        let sourceModel = NSManagedObjectModel(contentsOf: sourceModelURL)!
        let destinationModelURL = urlForModel(name: "Model 28")
        let destinationModel = NSManagedObjectModel(contentsOf: destinationModelURL)!
        let name = "WooCommerce"
        let crashLogger = MockCrashLogger()
        let coreDataManager = CoreDataManager(name: name, crashLogger: crashLogger)

        // Destroys any pre-existing persistence store.
        let psc = NSPersistentStoreCoordinator(managedObjectModel: modelsInventory.currentModel)
        try psc.destroyPersistentStore(at: coreDataManager.storeURL, ofType: NSSQLiteStoreType, options: nil)

        // Action - step 1: loading persistence store with model 20
        let sourceModelContainer = NSPersistentContainer(name: name, managedObjectModel: sourceModel)
        sourceModelContainer.persistentStoreDescriptions = [coreDataManager.storeDescription]

        var sourceModelLoadingError: Error?
        waitForExpectation { expectation in
            sourceModelContainer.loadPersistentStores { (storeDescription, error) in
                sourceModelLoadingError = error
                expectation.fulfill()
            }
        }

        // Assert - step 1
        XCTAssertNil(sourceModelLoadingError, "Persistence store loading error: \(String(describing: sourceModelLoadingError?.localizedDescription))")

        // Arrange - step 2: populating data, migrating persistent store from model 20 to 28, then loading with model 28.
        let context = sourceModelContainer.viewContext

        let product = insertProductWithRequiredProperties(to: context)
        // Populates transformable attributes.
        let productCrossSellIDs: [Int64] = [630, 688]
        let groupedProductIDs: [Int64] = [94, 134]
        let productRelatedIDs: [Int64] = [270, 37]
        let productUpsellIDs: [Int64] = [1126, 1216]
        let productVariationIDs: [Int64] = [927, 1110]
        product.crossSellIDs = productCrossSellIDs
        product.groupedProducts = groupedProductIDs
        product.relatedIDs = productRelatedIDs
        product.upsellIDs = productUpsellIDs
        product.variations = productVariationIDs

        let productAttribute = insertProductAttributeWithRequiredProperties(to: context)
        // Populates transformable attributes.
        let attributeOptions = ["Woody", "Andy Panda"]
        productAttribute.options = attributeOptions

        product.addToAttributes(productAttribute)
        context.saveIfNeeded()

        XCTAssertEqual(context.countObjects(ofType: Product.self), 1)
        XCTAssertEqual(context.countObjects(ofType: ProductAttribute.self), 1)

        let destinationModelContainer = NSPersistentContainer(name: name, managedObjectModel: destinationModel)
        destinationModelContainer.persistentStoreDescriptions = [coreDataManager.storeDescription]

        // Action - step 2
        let iterativeMigrator = CoreDataIterativeMigrator(modelsInventory: modelsInventory)
        let (migrateResult, migrationDebugMessages) = try iterativeMigrator.iterativeMigrate(sourceStore: coreDataManager.storeURL,
                                                                                             storeType: NSSQLiteStoreType,
                                                                                             to: destinationModel)
        XCTAssertTrue(migrateResult, "Failed to migrate to model version 28: \(migrationDebugMessages)")

        var destinationModelLoadingError: Error?
        waitForExpectation { expectation in
            destinationModelContainer.loadPersistentStores { (storeDescription, error) in
                destinationModelLoadingError = error
                expectation.fulfill()
            }
        }

        // Assert - step 2
        XCTAssertNil(destinationModelLoadingError, "Migration error: \(String(describing: destinationModelLoadingError?.localizedDescription))")

        let persistedProduct = try XCTUnwrap(destinationModelContainer.viewContext.firstObject(ofType: Product.self))
        XCTAssertEqual(persistedProduct.crossSellIDs, productCrossSellIDs)
        XCTAssertEqual(persistedProduct.groupedProducts, groupedProductIDs)
        XCTAssertEqual(persistedProduct.relatedIDs, productRelatedIDs)
        XCTAssertEqual(persistedProduct.upsellIDs, productUpsellIDs)
        XCTAssertEqual(persistedProduct.variations, productVariationIDs)

        let persistedAttribute = try XCTUnwrap(destinationModelContainer.viewContext.firstObject(ofType: ProductAttribute.self))
        XCTAssertEqual(persistedAttribute.options, attributeOptions)
    }

}

/// Helpers for generating data in migration tests
private extension CoreDataIterativeMigratorTests {
    func insertAccountWithRequiredProperties(to context: NSManagedObjectContext) -> Account {
        let account = context.insertNewObject(ofType: Account.self)
        // Populates the required attributes.
        account.userID = 17
        account.username = "hi"
        return account
    }

    func insertProductWithRequiredProperties(to context: NSManagedObjectContext) -> Product {
        let product = context.insertNewObject(ofType: Product.self)
        // Populates the required attributes.
        product.price = ""
        product.permalink = ""
        product.productTypeKey = "simple"
        product.purchasable = true
        product.averageRating = ""
        product.backordered = true
        product.backordersAllowed = false
        product.backordersKey = ""
        product.catalogVisibilityKey = ""
        product.dateCreated = Date()
        product.downloadable = true
        product.featured = true
        product.manageStock = true
        product.name = "product"
        product.onSale = true
        product.soldIndividually = true
        product.slug = ""
        product.shippingRequired = false
        product.shippingTaxable = false
        product.reviewsAllowed = true
        product.groupedProducts = []
        product.virtual = true
        product.stockStatusKey = ""
        product.statusKey = ""
        product.taxStatusKey = ""
        return product
    }

    func insertProductCategoryWithRequiredProperties(to context: NSManagedObjectContext) -> ProductCategory {
        let productCategory = context.insertNewObject(ofType: ProductCategory.self)
        // Populates the required attributes.
        productCategory.name = "testing"
        productCategory.slug = ""
        return productCategory
    }

    func insertProductTag(to context: NSManagedObjectContext) -> ProductTag {
        let productTag = context.insertNewObject(ofType: ProductTag.self)
        // Populates the required attributes.
        productTag.tagID = 34
        productTag.name = "testing"
        productTag.slug = ""
        return productTag
    }

    func insertProductAttributeWithRequiredProperties(to context: NSManagedObjectContext) -> ProductAttribute {
        let productAttribute = context.insertNewObject(ofType: ProductAttribute.self)
        // Populates the required attributes.
        productAttribute.name = "woodpecker"
        productAttribute.variation = true
        productAttribute.visible = true
        return productAttribute
    }
}

/// Helpers for the Core Data migration tests
private extension CoreDataIterativeMigratorTests {

    var documentsDirectory: URL {
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last!
        return URL(fileURLWithPath: path)
    }

    func managedObjectModel(for modelName: String) throws -> NSManagedObjectModel {
        let modelVersion = ManagedObjectModelsInventory.ModelVersion(name: modelName)
        return try XCTUnwrap(modelsInventory.model(for: modelVersion))
    }

    /// Prefer using `managedObjectModel(for:)` directly. 
    func urlForModel(name: String) -> URL {

        let bundle = Bundle(for: CoreDataManager.self)
        guard let path = bundle.paths(forResourcesOfType: "momd", inDirectory: nil).first,
            let url = bundle.url(forResource: name, withExtension: "mom", subdirectory: URL(fileURLWithPath: path).lastPathComponent) else {
            fatalError("Missing Model Resource")
        }

        return url
    }

    func urlForStore(withName: String, deleteIfExists: Bool = false) -> URL {
        let storeURL = documentsDirectory.appendingPathComponent(withName)

        if deleteIfExists {
            try? FileManager.default.removeItem(at: storeURL)
        }

        try? FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)

        return storeURL
    }

    func makePersistentContainer(storeURL: URL, storeType: String, model: NSManagedObjectModel) -> NSPersistentContainer {
        let description: NSPersistentStoreDescription = {
            let description = NSPersistentStoreDescription(url: storeURL)
            description.shouldAddStoreAsynchronously = false
            description.shouldMigrateStoreAutomatically = false
            description.type = storeType
            return description
        }()

        let container = NSPersistentContainer(name: "ContainerName", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        return container
    }
}
