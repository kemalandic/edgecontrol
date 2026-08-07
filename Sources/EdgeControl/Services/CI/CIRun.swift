import Foundation

/// One workflow run, normalised across hosts.
///
/// GitHub splits outcome across `status` and `conclusion`; Forgejo carries it
/// in a single `status`. Both collapse into `state` here so the UI has one
/// vocabulary to render.
public struct CIRun: Identifiable, Equatable, Sendable {
    /// `<accountID>/<repoFullName>/<hostRunID>`.
    ///
    /// Qualified rather than the raw numeric run ID: two hosts can return the
    /// same number, which would collapse rows in SwiftUI's `ForEach`.
    public let id: String
    public let accountID: UUID
    /// Shown next to the repository name when more than one account exists.
    public let hostLabel: String
    public let repositoryName: String
    /// GitHub sends a display name; Forgejo sends the workflow filename.
    public let workflowName: String
    public let title: String
    public let branch: String
    public let state: CIRunState
    public let startedAt: Date
    public let url: URL

    public init(
        id: String,
        accountID: UUID,
        hostLabel: String,
        repositoryName: String,
        workflowName: String,
        title: String,
        branch: String,
        state: CIRunState,
        startedAt: Date,
        url: URL
    ) {
        self.id = id
        self.accountID = accountID
        self.hostLabel = hostLabel
        self.repositoryName = repositoryName
        self.workflowName = workflowName
        self.title = title
        self.branch = branch
        self.state = state
        self.startedAt = startedAt
        self.url = url
    }
}
