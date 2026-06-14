import Observation

/// An observable container that pairs an asynchronously loaded value with its
/// loading lifecycle, intended to be owned by a store as the single source of truth.
///
/// All state transitions go through the methods of this class; `state` itself
/// is read-only from the outside.
@Observable
@MainActor
public final class AsyncBox<Value> {
    /// The current state.
    public private(set) var state: AsyncBoxState<Value>

    /// Creates a box in the given state. Defaults to `.initial`.
    public init(state: AsyncBoxState<Value> = .initial) {
        self.state = state
    }

    /// Creates a box that starts as `.loaded` with the given value.
    public init(initialValue: Value) {
        self.state = .loaded(initialValue)
    }
}

// MARK: - Derived Properties

extension AsyncBox {
    /// See ``AsyncBoxState/value``.
    public var value: Value? { state.value }

    /// See ``AsyncBoxState/error``.
    public var error: (any Error)? { state.error }

    /// See ``AsyncBoxState/isLoading``.
    public var isLoading: Bool { state.isLoading }

    /// See ``AsyncBoxState/isInitial``.
    public var isInitial: Bool { state.isInitial }

    /// See ``AsyncBoxState/hasValue``.
    public var hasValue: Bool { state.hasValue }
}

// MARK: - State Transitions

extension AsyncBox {
    /// Transitions to `.loaded` with the given value.
    public func succeed(with value: Value) {
        state = .loaded(value)
    }

    /// Transitions to `.error`.
    ///
    /// Errors conforming to ``AsyncBoxStateFailure`` determine whether the
    /// current value is retained. Unclassified errors retain it by default.
    public func fail(with error: any Error) {
        let isValueValid =
            (error as? any AsyncBoxStateFailure)?.isValueValid
            ?? true

        state = .error(error, isValueValid ? value : nil)
    }

    /// Transitions to `.loading`, retaining the current value as the previous value.
    public func startLoading() {
        state = .loading(value)
    }

    /// Transitions back to `.initial`.
    public func reset() {
        state = .initial
    }

    /// Mutates the value in place while keeping the current state
    /// (`loaded` stays `loaded`, `loading` stays `loading`, and so on).
    /// Does nothing when no value is available.
    public func mutate(_ transform: (inout Value) -> Void) {
        switch state {
        case .loaded(var value):
            transform(&value)
            state = .loaded(value)
        case .loading(.some(var value)):
            transform(&value)
            state = .loading(value)
        case .error(let error, .some(var value)):
            transform(&value)
            state = .error(error, value)
        case .initial, .loading(.none), .error(_, .none):
            break
        }
    }
}

// MARK: - Loading

extension AsyncBox {
    /// Runs `perform` and reflects its outcome in `state`: `.loading` while
    /// running, `.loaded` on success, `.error` on failure.
    /// The error is also rethrown. Throws ``AsyncBoxLoadError/alreadyLoading``
    /// without running `perform` when another load is in progress.
    public func load(
        _ perform: nonisolated(nonsending) () async throws -> Value
    ) async throws {
        if isLoading {
            throw AsyncBoxLoadError.alreadyLoading
        }

        let previousState = state
        startLoading()
        do {
            let value = try await perform()
            succeed(with: value)
        } catch let error as CancellationError {
            state = previousState
            throw error
        } catch {
            fail(with: error)
            throw error
        }
    }
}
