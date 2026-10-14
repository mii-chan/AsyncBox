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

    /// The load whose outcome may still update `state`.
    /// Cleared whenever `state` leaves `loading`.
    @ObservationIgnored
    private var currentLoad: LoadContext?

    /// Creates a box in the given state. Defaults to `.initial`.
    public init(state: AsyncBoxState<Value> = .initial) {
        self.state = state
    }

    /// Creates a box that starts as `.loaded` with the given value.
    public init(initialValue: Value) {
        self.state = .loaded(initialValue)
    }

    private final class LoadContext {
        let errorBeforeLoading: (any Error)?

        init(errorBeforeLoading: (any Error)?) {
            self.errorBeforeLoading = errorBeforeLoading
        }
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
        replaceState(.loaded(value))
    }

    /// Transitions to `.error`.
    ///
    /// Errors conforming to ``AsyncBoxStateFailure`` determine whether the
    /// current value is retained. Unclassified errors retain it by default.
    public func fail(with error: any Error) {
        replaceState(failureState(for: error))
    }

    /// Transitions back to `.initial`.
    public func reset() {
        replaceState(.initial)
    }

    /// Mutates the value in place while keeping the current state
    /// (`loaded` stays `loaded`, `loading` stays `loading`, and so on).
    /// Does nothing when no value is available.
    public func mutate(_ transform: (inout Value) -> Void) {
        switch state {
        case .loaded(var value):
            transform(&value)
            replaceState(.loaded(value))
        case .loading(.some(var value)):
            transform(&value)
            replaceState(.loading(value))
        case .error(let error, .some(var value)):
            transform(&value)
            replaceState(.error(error, value))
        case .initial, .loading(.none), .error(_, .none):
            break
        }
    }

    /// Transitions to `.loading`, retaining the current value as the previous value.
    func startLoading() {
        replaceState(.loading(value))
    }
}

// MARK: - Loading

extension AsyncBox {
    /// Runs `perform` and reflects its outcome in `state`: `.loading` while
    /// running, `.loaded` on success, `.error` on failure. The error is also
    /// rethrown.
    ///
    /// Returns `false` without running `perform` when another load is in
    /// progress and `policy` is `.skip`, or when the outcome is discarded
    /// because the box was reset, transitioned, or restarted meanwhile.
    /// A discarded error is not rethrown; `CancellationError` always is.
    @discardableResult
    public func load(
        ifLoading policy: AsyncBoxLoadPolicy = .skip,
        _ perform: nonisolated(nonsending) () async throws -> Value
    ) async throws -> Bool {
        if isLoading && policy == .skip {
            return false
        }

        let context = LoadContext(
            errorBeforeLoading: isLoading ? currentLoad?.errorBeforeLoading : state.error
        )
        currentLoad = context
        startLoading()

        do {
            let value = try await perform()
            guard currentLoad === context else { return false }
            replaceState(.loaded(value))
            return true
        } catch let error as CancellationError {
            if currentLoad === context {
                replaceState(stateBeforeLoading(context))
            }
            throw error
        } catch {
            guard currentLoad === context else { return false }
            replaceState(failureState(for: error))
            throw error
        }
    }
}

// MARK: - Private Helpers

extension AsyncBox {
    private func replaceState(_ newState: AsyncBoxState<Value>) {
        if !newState.isLoading {
            currentLoad = nil
        }
        state = newState
    }

    private func failureState(for error: any Error) -> AsyncBoxState<Value> {
        let isValueValid =
            (error as? any AsyncBoxStateFailure)?.isValueValid
            ?? true

        return .error(error, isValueValid ? value : nil)
    }

    /// Uses the current value so that mutations made while loading are kept.
    private func stateBeforeLoading(_ context: LoadContext) -> AsyncBoxState<Value> {
        if let error = context.errorBeforeLoading {
            .error(error, value)
        } else if let value {
            .loaded(value)
        } else {
            .initial
        }
    }
}
