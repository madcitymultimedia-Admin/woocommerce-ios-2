import UIKit
import Yosemite


/// Displays the name and url for a downloadable file of a product
final class ProductDownloadFileViewController: UIViewController {

    @IBOutlet private weak var tableView: UITableView!

    private let viewModel: ProductDownloadFileViewModelOutput & ProductDownloadFileActionHandler

    // Completion callback
    //
    typealias Completion = (_ fileName: String?,
        _ fileURL: String,
        _ fileID: String?,
        _ hasUnsavedChanges: Bool) -> Void
    private let onCompletion: Completion

    private lazy var keyboardFrameObserver = KeyboardFrameObserver { [weak self] keyboardFrame in
        self?.handleKeyboardFrameUpdate(keyboardFrame: keyboardFrame)
    }

    /// Init
    ///
    init(product: ProductFormDataModel, downloadFileIndex: Int?, formType: FormType, completion: @escaping Completion) {
        viewModel = ProductDownloadFileViewModel(product: product, downloadFileIndex: downloadFileIndex, formType: formType)
        onCompletion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startListeningToNotifications()
        configureNavigationBar()
        configureMainView()
        configureTableView()
        handleSwipeBackGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        configureUrlTextFieldAsFirstResponder()
    }
}

// MARK: - Navigation actions handling
//
extension ProductDownloadFileViewController {

    override func shouldPopOnBackButton() -> Bool {
        guard viewModel.hasUnsavedChanges() else {
            return true
        }
        presentBackNavigationActionSheet()
        return false
    }

    override func shouldPopOnSwipeBack() -> Bool {
        return shouldPopOnBackButton()
    }

    @objc private func completeUpdating() {
        viewModel.completeUpdating(
            onCompletion: { [weak self] (fileName, fileURL, fileID, hasUnsavedChanges) in
                self?.onCompletion(fileName, fileURL, fileID, hasUnsavedChanges)
            }, onError: { [weak self] error in
                switch error {
                case .emptyFileName:
                    self?.displayEmptyFileNameErrorNotice()
                case .emptyFileUrl:
                    self?.displayInvalidUrlErrorNotice()
                case .invalidFileUrl:
                    self?.displayInvalidUrlErrorNotice()
                }
        })
    }

    @objc private func deleteDownloadableFile() {
        //TODO: - Handle the deletion of file properly
    }

    private func presentBackNavigationActionSheet() {
        UIAlertController.presentDiscardChangesActionSheet(viewController: self, onDiscard: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
    }
}

// MARK: - UITableViewDataSource Conformance
//
extension ProductDownloadFileViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = viewModel.sections[indexPath.section].rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: row.reuseIdentifier, for: indexPath)
        configure(cell, for: row, at: indexPath)

        return cell
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return viewModel.sections[section].footer
    }
}

// MARK: - Cell configuration
//
private extension ProductDownloadFileViewController {
    /// Cells currently configured in the order they appear on screen
    ///
    func configure(_ cell: UITableViewCell, for row: Row, at indexPath: IndexPath) {
        switch cell {
        case let cell as TitleAndTextFieldTableViewCell where row == .name:
            configureName(cell: cell)
        case let cell as TitleAndTextFieldTableViewCell where row == .url:
            configureURL(cell: cell)
        default:
            fatalError()
            break
        }
    }

    func configureName(cell: TitleAndTextFieldTableViewCell) {
        let cellViewModel = Product.createDownloadFileNameViewModel(fileName: viewModel.fileName) { [weak self] value in
            self?.viewModel.handleFileNameChange(value) { [weak self] (isValid) in
                self?.enableDoneButton(isValid)
                if let indexPath = self?.viewModel.sections.indexPathForRow(.name),
                    let cell = self?.tableView.cellForRow(at: indexPath) as? TitleAndTextFieldTableViewCell {
                    cell.textFieldBecomeFirstResponder()
                }
            }
        }
        cell.configure(viewModel: cellViewModel)
    }

    func configureURL(cell: TitleAndTextFieldTableViewCell) {
        let cellViewModel = Product.createDownloadFileUrlViewModel(fileUrl: viewModel.fileURL) { [weak self] value in
            self?.viewModel.handleFileUrlChange(value) { [weak self] (isValid) in
                self?.enableDoneButton(isValid)
                if let indexPath = self?.viewModel.sections.indexPathForRow(.url),
                    let cell = self?.tableView.cellForRow(at: indexPath) as? TitleAndTextFieldTableViewCell {
                    cell.textFieldBecomeFirstResponder()
                }
            }
        }
        cell.configure(viewModel: cellViewModel)
    }
}

// MARK: - View Configuration
//
private extension ProductDownloadFileViewController {

    func configureNavigationBar() {
        if let fileName = viewModel.fileName {
            title = fileName
        } else {
            title = NSLocalizedString("Add Downloadable File",
                                      comment: "Downloadable file screen navigation title")
        }

        var rightBarButtonItems = [UIBarButtonItem]()

        let moreBarButton: UIBarButtonItem = {
            let button = UIBarButtonItem(image: .moreImage,
                                         style: .plain,
                                         target: self,
                                         action: #selector(deleteDownloadableFile))
            button.accessibilityLabel = NSLocalizedString("Show bottom action sheet to delete downloadable file from list",
                                                          comment: "Accessibility label to show bottom action sheet to delete downloadable file from the list")
            return button
        }()
        rightBarButtonItems.append(moreBarButton)

        let updateButtonTitle = NSLocalizedString("Update",
                                                comment: "Action for updating a Products' downloadable files' info remotely")
        let updateBarButton: UIBarButtonItem = {
            let button = UIBarButtonItem(title: updateButtonTitle,
                                         style: .done,
                                         target: self,
                                         action: #selector(completeUpdating))
            button.accessibilityLabel = NSLocalizedString("Update products' downloadable files' info remotely",
                                                          comment: "Accessibility label to update products' downloadable files' info remotely")
            button.accessibilityIdentifier = ProductDownloadFileViewModel.Strings.updateBarButtonAccessibilityIdentifier
            return button
        }()
        rightBarButtonItems.append(updateBarButton)

        navigationItem.rightBarButtonItems = rightBarButtonItems

        removeNavigationBackBarButtonText()
        enableDoneButton(false)
    }

    func configureMainView() {
        view.backgroundColor = .listBackground
    }

    func configureTableView() {
        tableView.dataSource = self

        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .listBackground
        tableView.removeLastCellSeparator()

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        registerTableViewCells()
    }

    /// Since the file url is the mandatory text field in this view for Product Downloadable file form,
    /// the text field becomes the first responder immediately when the view did appear
    ///
    func configureUrlTextFieldAsFirstResponder() {
        if let indexPath = viewModel.sections.indexPathForRow(.url) {
            let cell = tableView.cellForRow(at: indexPath) as? TitleAndTextFieldTableViewCell
            cell?.textFieldBecomeFirstResponder()
        }
    }

    func registerTableViewCells() {
        for row in Row.allCases {
            tableView.register(row.type.loadNib(), forCellReuseIdentifier: row.reuseIdentifier)
        }
    }

    func enableDoneButton(_ enabled: Bool) {
        navigationItem.rightBarButtonItems?.forEach({ (barButtonItem) in
            if barButtonItem.accessibilityIdentifier == ProductDownloadFileViewModel.Strings.updateBarButtonAccessibilityIdentifier {
                barButtonItem.isEnabled = enabled
            }
        })
    }
}

// MARK: - Keyboard management
//
extension ProductDownloadFileViewController: KeyboardScrollable {
    var scrollable: UIScrollView {
        return tableView
    }
}

private extension ProductDownloadFileViewController {
    /// Registers for all of the related Notifications
    ///
    func startListeningToNotifications() {
        keyboardFrameObserver.startObservingKeyboardFrame()
    }
}

// MARK: - Error handling
//
private extension ProductDownloadFileViewController {

    /// Displays a Notice onscreen, indicating that you can't add a downloadable file without adding a file name
    ///
    func displayEmptyFileNameErrorNotice() {
        UIApplication.shared.keyWindow?.endEditing(true)
        let message = NSLocalizedString("The file name can not be empty",
                                        comment: "Download file error notice message, when file name is not given but done button is tapped")

        let notice = Notice(title: message, feedbackType: .error)
        ServiceLocator.noticePresenter.enqueue(notice: notice)
    }

    /// Displays a Notice onscreen, indicating that you can't add a downloadable file without adding a valid file url
    ///
    func displayInvalidUrlErrorNotice() {
        UIApplication.shared.keyWindow?.endEditing(true)
        let message = NSLocalizedString("File url is empty or invalid",
                                        comment: "Download file url error notice message, when file url is not given/invalid but done button is tapped")

        let notice = Notice(title: message, feedbackType: .error)
        ServiceLocator.noticePresenter.enqueue(notice: notice)
    }
}

extension ProductDownloadFileViewController {

    struct Section: RowIterable, Equatable {
        let footer: String?
        let rows: [Row]

        init(footer: String? = nil, rows: [Row]) {
            self.footer = footer
            self.rows = rows
        }
    }

    enum Row: CaseIterable {
        case name
        case url

        fileprivate var type: UITableViewCell.Type {
            switch self {
            case .name, .url:
                return TitleAndTextFieldTableViewCell.self
            }
        }

        fileprivate var reuseIdentifier: String {
            return type.reuseIdentifier
        }
    }

    enum FormType {
        case add
        case edit
    }
}
