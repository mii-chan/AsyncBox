/// What `load` does when another load is already in progress.
public enum AsyncBoxLoadPolicy: Sendable {
    /// Returns `false` without running the closure.
    case skip

    /// Runs the closure as a new load. The earlier load is not cancelled;
    /// its outcome is discarded.
    case restart
}
