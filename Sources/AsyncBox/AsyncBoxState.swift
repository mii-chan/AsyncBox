/// An error that can declare whether an existing value remains valid after
/// the failure.
public protocol AsyncBoxStateFailure: Error {
    /// Whether the value available before the failure can still be used.
    var isValueValid: Bool { get }
}

/// An exhaustive representation of the lifecycle of an asynchronously loaded value.
///
/// `loading` and `error` carry the previously loaded value (if any) so that
/// views can keep showing existing content while reloading or after a failure.
public enum AsyncBoxState<Value> {
    /// No load has been requested yet.
    case initial

    /// A load is in progress. The associated value is the previous value, if any.
    case loading(Value?)

    /// A load has succeeded.
    case loaded(Value)

    /// A load has failed. The second associated value is the previous value, if any.
    case error(any Error, Value?)
}

extension AsyncBoxState {
    /// The currently available value: the loaded value, or the previous value
    /// retained by `loading` / `error`.
    public var value: Value? {
        switch self {
        case .loaded(let value),
             .loading(.some(let value)),
             .error(_, .some(let value)):
            value
        case .initial, .loading(.none), .error(_, .none):
            nil
        }
    }

    /// The error if the state is `error`, otherwise `nil`.
    public var error: (any Error)? {
        if case .error(let error, _) = self { error } else { nil }
    }

    /// Whether the state is `loading`.
    public var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    /// Whether the state is `initial`.
    public var isInitial: Bool {
        if case .initial = self { true } else { false }
    }

    /// Whether a value is currently available.
    public var hasValue: Bool { value != nil }
}
