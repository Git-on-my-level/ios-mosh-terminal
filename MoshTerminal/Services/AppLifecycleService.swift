import Combine
import UIKit

@MainActor
final class AppLifecycleService: ObservableObject {
    enum State: Equatable {
        case foreground
        case background
    }

    enum Event: Equatable {
        case foreground
        case background
    }

    @Published private(set) var state: State
    let events = PassthroughSubject<Event, Never>()

    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter = .default,
        application: UIApplication? = nil
    ) {
        let app = application ?? UIApplication.shared
        let initialState: State = app.applicationState == .background ? .background : .foreground
        self.state = initialState

        let backgroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.transition(to: .background, event: .background)
            }
        }

        let foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.transition(to: .foreground, event: .foreground)
            }
        }

        observers.append(backgroundObserver)
        observers.append(foregroundObserver)
    }

    deinit {
        let notificationCenter = NotificationCenter.default
        observers.forEach { notificationCenter.removeObserver($0) }
    }

    private func transition(to newState: State, event: Event) {
        guard state != newState else { return }
        state = newState
        events.send(event)
    }
}

extension AppLifecycleService: @preconcurrency AppLifecycleProviding {
    var eventsPublisher: AnyPublisher<Event, Never> {
        events.eraseToAnyPublisher()
    }
}
