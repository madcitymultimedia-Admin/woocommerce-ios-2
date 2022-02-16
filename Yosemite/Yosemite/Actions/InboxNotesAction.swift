import Foundation
import Networking

// MARK: - InboxNotesAction: Defines Inbox Notes operations.
//
public enum InboxNotesAction: Action {

    /// Retrieves all of the `InboxNote`s from the API.
    ///
    case loadAllInboxNotes(siteID: Int64,
                           pageNumber: Int = Default.pageNumber,
                           pageSize: Int = Default.pageSize,
                           orderBy: InboxNotesRemote.OrderBy = .date,
                           type: [InboxNotesRemote.NoteType]? = nil,
                           status: [InboxNotesRemote.Status]? = nil,
                           completion: (Result<[InboxNote], Error>) -> ())

    /// Dismiss one `InboxNote`.
    /// This internally marks a notification’s is_deleted field to true and such notifications do not show in the results anymore.
    ///
    case dismissInboxNote(siteID: Int64,
                          noteID: Int64,
                          completion: (Result<InboxNote, Error>) -> ())

    /// Set an `InboxNote` as `actioned`.
    /// This internally marks a notification’s status as `actioned`.
    ///
    case markInboxNoteAsActioned(siteID: Int64,
                                 noteID: Int64,
                                 actionID: Int64,
                                 completion: (Result<InboxNote, Error>) -> ())
}

// MARK: - Constants
//
public extension InboxNotesAction {
    enum Default {
        public static let pageSize = 25
        public static let pageNumber = 1
    }
}