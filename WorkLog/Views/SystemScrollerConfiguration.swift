import AppKit
import SwiftUI

extension View {
    func systemScrollerBehavior() -> some View {
        background(SystemScrollerConfigurator())
    }
}

private struct SystemScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollerConfigurationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollerConfigurationView)?.scheduleConfiguration()
    }
}

private final class ScrollerConfigurationView: NSView {
    private weak var configuredScrollView: NSScrollView?
    private var scrollObserver: NSObjectProtocol?
    private var pendingHide: DispatchWorkItem?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleConfiguration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    override func layout() {
        super.layout()
        if configuredScrollView == nil {
            scheduleConfiguration()
        }
    }

    deinit {
        stopObservingScroll()
    }

    func scheduleConfiguration() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let scrollView = self.relatedScrollView else { return }
            scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
            scrollView.autohidesScrollers = Self.shouldAutoHideScrollers

            if Self.shouldAutoHideScrollers {
                self.observeScrollViewIfNeeded(scrollView)
                self.scheduleScrollerHide(after: 0)
            } else {
                self.stopObservingScroll()
                scrollView.verticalScroller?.alphaValue = Self.persistentScrollerOpacity
                scrollView.horizontalScroller?.alphaValue = Self.persistentScrollerOpacity
            }
        }
    }

    private func observeScrollViewIfNeeded(_ scrollView: NSScrollView) {
        guard configuredScrollView !== scrollView else { return }
        stopObservingScroll()

        configuredScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.showScrollersTemporarily()
        }
    }

    private func showScrollersTemporarily() {
        pendingHide?.cancel()
        configuredScrollView?.verticalScroller?.alphaValue = Self.activeScrollerOpacity
        configuredScrollView?.horizontalScroller?.alphaValue = Self.activeScrollerOpacity
        scheduleScrollerHide(after: 1.2)
    }

    private func scheduleScrollerHide(after delay: TimeInterval) {
        pendingHide?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, Self.shouldAutoHideScrollers else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = delay == 0 ? 0 : 0.2
                self.configuredScrollView?.verticalScroller?.animator().alphaValue = 0
                self.configuredScrollView?.horizontalScroller?.animator().alphaValue = 0
            }
        }
        pendingHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func stopObservingScroll() {
        pendingHide?.cancel()
        pendingHide = nil
        if let scrollObserver = scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
        scrollObserver = nil
        configuredScrollView = nil
    }

    private var relatedScrollView: NSScrollView? {
        var view = superview
        while let currentView = view {
            if let scrollView = currentView as? NSScrollView {
                return scrollView
            }
            view = currentView.superview
        }

        guard let contentView = window?.contentView else { return nil }
        let targetRect = convert(bounds, to: nil)
        return scrollViews(in: contentView)
            .filter(\.hasVerticalScroller)
            .min { scrollViewDistance($0, targetRect) < scrollViewDistance($1, targetRect) }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { subview -> [NSScrollView] in
            let current = (subview as? NSScrollView).map { [$0] } ?? []
            return current + scrollViews(in: subview)
        }
    }

    private func scrollViewDistance(_ scrollView: NSScrollView, _ targetRect: NSRect) -> CGFloat {
        let scrollRect = scrollView.convert(scrollView.bounds, to: nil)
        return abs(scrollRect.minX - targetRect.minX)
            + abs(scrollRect.minY - targetRect.minY)
            + abs(scrollRect.width - targetRect.width)
            + abs(scrollRect.height - targetRect.height)
    }

    private static var shouldAutoHideScrollers: Bool {
        UserDefaults.standard.string(forKey: "AppleShowScrollBars") != "Always"
    }

    private static let activeScrollerOpacity: CGFloat = 0.45
    private static let persistentScrollerOpacity: CGFloat = 0.58
}
