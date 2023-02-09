import Foundation
import Yosemite

/// Actions in the product form bottom sheet to add more product details.
enum ProductFormBottomSheetAction {
    case editInventorySettings
    case editShippingSettings
    case editCategories
    case editTags
    case editShortDescription
    case editSKU
    case editLinkedProducts
    case convertToVariable

    init?(productFormAction: ProductFormEditAction) {
        switch productFormAction {
        case .inventorySettings:
            self = .editInventorySettings
        case .shippingSettings:
            self = .editShippingSettings
        case .categories:
            self = .editCategories
        case .tags:
            self = .editTags
        case .shortDescription:
            self = .editShortDescription
        case .sku:
            self = .editSKU
        case .linkedProducts:
            self = .editLinkedProducts
        case .convertToVariable:
            self = .convertToVariable
        default:
            return nil
        }
    }
}

extension ProductFormBottomSheetAction {
    var title: String {
        switch self {
        case .editInventorySettings:
            return NSLocalizedString("Inventory",
                                     comment: "Title of the product form bottom sheet action for editing inventory settings.")
        case .editShippingSettings:
            return NSLocalizedString("Shipping",
                                     comment: "Title of the product form bottom sheet action for editing shipping settings.")
        case .editCategories:
            return NSLocalizedString("Categories",
                                     comment: "Title of the product form bottom sheet action for editing categories.")
        case .editTags:
            return NSLocalizedString("Tags",
                                     comment: "Title of the product form bottom sheet action for editing tags.")
        case .editShortDescription:
            return NSLocalizedString("Short description",
                                     comment: "Title of the product form bottom sheet action for editing short description.")
        case .editSKU:
            return NSLocalizedString("SKU",
                                     comment: "Title of the product form bottom sheet action for editing short description.")
        case .editLinkedProducts:
            return NSLocalizedString("Linked products",
                                     comment: "Title of the product form bottom sheet action for editing linked products.")
        case .convertToVariable:
            return NSLocalizedString("Add product variations",
                                     comment: "Title of the product form bottom sheet action for switching to variable product type.")
        }
    }

    var subtitle: String {
        switch self {
        case .editInventorySettings:
            return NSLocalizedString("Update product inventory and SKU",
                                     comment: "Subtitle of the product form bottom sheet action for editing inventory settings.")
        case .editShippingSettings:
            return NSLocalizedString("Add weight and dimensions",
                                     comment: "Subtitle of the product form bottom sheet action for editing shipping settings.")
        case .editCategories:
            return NSLocalizedString("Organise your products into related groups",
                                     comment: "Subtitle of the product form bottom sheet action for editing categories.")
        case .editTags:
            return NSLocalizedString("Make your products easier to find with tags",
                                     comment: "Subtitle of the product form bottom sheet action for editing tags.")
        case .editShortDescription:
            return NSLocalizedString("A brief excerpt about your product",
                                     comment: "Subtitle of the product form bottom sheet action for editing short description.")
        case .editSKU:
            return NSLocalizedString("Easily identify your products with unique codes",
                                     comment: "Subtitle of the product form bottom sheet action for editing SKU.")
        case .editLinkedProducts:
            return NSLocalizedString("Increase sales with upsells and cross-sells",
                                     comment: "Subtitle of the product form bottom sheet action for linked products.")
        case .convertToVariable:
            return NSLocalizedString("Add sizes, colors, or other options",
                                     comment: "Subtitle of the product form bottom sheet action for switching to variable product type.")
        }
    }
}
