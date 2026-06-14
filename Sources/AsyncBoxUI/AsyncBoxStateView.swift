import AsyncBox
import SwiftUI

/// Switches its content based on an ``AsyncBoxState``.
///
/// States that carry a value (`loaded`, and `loading` / `error` with a
/// previous value) are all rendered through `content`, keeping the content's
/// view identity across reloads and failures. `loadingContent` and
/// `errorContent` appear only when there is no previous value; decorations
/// over existing content are up to the caller (e.g. `.overlay`).
public struct AsyncBoxStateView<
    Value,
    Content: View,
    InitialContent: View,
    LoadingContent: View,
    ErrorContent: View
>: View {
    private let state: AsyncBoxState<Value>
    private let content: (Value) -> Content
    private let initialContent: InitialContent
    private let loadingContent: LoadingContent
    private let errorContent: (any Error) -> ErrorContent

    /// Creates a view with custom views for every slot.
    public init(
        state: AsyncBoxState<Value>,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder initialContent: () -> InitialContent,
        @ViewBuilder loadingContent: () -> LoadingContent,
        @ViewBuilder errorContent: @escaping (any Error) -> ErrorContent
    ) {
        self.state = state
        self.content = content
        self.initialContent = initialContent()
        self.loadingContent = loadingContent()
        self.errorContent = errorContent
    }

    public var body: some View {
        switch state {
        case let .loaded(value),
             let .loading(.some(value)),
             let .error(_, .some(value)):
            content(value)

        case .initial:
            initialContent

        case .loading(.none):
            loadingContent

        case let .error(error, .none):
            errorContent(error)
        }
    }
}

// MARK: - Default Views

/// The default view for the `initial` state.
///
/// Uses `Color.clear` instead of `EmptyView`: with `EmptyView`, lifecycle
/// modifiers attached outside (such as `.task`) would never fire because
/// nothing is rendered.
public struct AsyncBoxDefaultInitialView: View {
    public init() {}

    public var body: some View {
        Color.clear
    }
}

/// The default view for the `loading` state without a previous value.
public struct AsyncBoxDefaultLoadingView: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Convenience Initializers

extension AsyncBoxStateView
where InitialContent == AsyncBoxDefaultInitialView,
      LoadingContent == AsyncBoxDefaultLoadingView {
    /// Creates a view with default initial and loading views.
    public init(
        state: AsyncBoxState<Value>,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder errorContent: @escaping (any Error) -> ErrorContent
    ) {
        self.init(
            state: state,
            content: content,
            initialContent: { AsyncBoxDefaultInitialView() },
            loadingContent: { AsyncBoxDefaultLoadingView() },
            errorContent: errorContent
        )
    }
}

extension AsyncBoxStateView
where InitialContent == AsyncBoxDefaultInitialView {
    /// Creates a view with the default initial view and a custom loading view.
    public init(
        state: AsyncBoxState<Value>,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder loadingContent: () -> LoadingContent,
        @ViewBuilder errorContent: @escaping (any Error) -> ErrorContent
    ) {
        self.init(
            state: state,
            content: content,
            initialContent: { AsyncBoxDefaultInitialView() },
            loadingContent: loadingContent,
            errorContent: errorContent
        )
    }
}
