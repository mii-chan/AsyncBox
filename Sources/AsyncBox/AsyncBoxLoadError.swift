/// An error thrown when a load operation cannot start.
public enum AsyncBoxLoadError: Error, Equatable, Sendable {
    /// Another load operation is already in progress.
    case alreadyLoading
}
