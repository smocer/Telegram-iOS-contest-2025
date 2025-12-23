import AccountContext
import ChatInterfaceState
import ChatPresentationInterfaceState
import Display
import TelegramPresentationData
import UIKit

final class LiquidChatMediaRecordingButton: ChatTextInputMediaRecordingButtonType {
    enum State: Equatable {
        case idle
        case pressing(pressStartTime: CFTimeInterval)
        case recording(locked: Bool, isCanceling: Bool)
    }

    let view: UIView

    private let control = UIControl()
    private let imageView = UIImageView()
    private var beginWorkItem: DispatchWorkItem?
    private var pressStartPoint: CGPoint = .zero
    private(set) var cancelTranslation: CGFloat = 0

    private var state: State = .idle {
        didSet {
            switch state {
            case .idle:
                onHighlightedChanged?(false)
            case .pressing:
                onHighlightedChanged?(true)
            case let .recording(locked, _):
                onHighlightedChanged?(true)
                updateLocked(locked)
            }
        }
    }

    var onHighlightedChanged: ((Bool) -> Void)?
    var onTrackingLocationChanged: ((CGPoint?) -> Void)?

    private(set) var mode: ChatTextInputMediaRecordingButtonMode = .audio

    func updateMode(mode: ChatTextInputMediaRecordingButtonMode, animated: Bool) {
        self.mode = mode
        updateIcon(animated: animated)
    }

    var fadeDisabled: Bool = false {
        didSet {
            updateFade()
        }
    }

    var statusBarHost: StatusBarHost?

    var audioRecorder: ManagedAudioRecorder? {
        didSet {
            if oldValue != nil, audioRecorder == nil, videoRecordingStatus == nil {
                reset()
            }
        }
    }
    var videoRecordingStatus: InstantVideoControllerRecordingStatus? {
        didSet {
            if oldValue != nil, videoRecordingStatus == nil, audioRecorder == nil {
                reset()
            }
        }
    }

    var recordingDisabled: () -> Void = {}
    var beginRecording: () -> Void = {}
    var endRecording: (Bool) -> Void = { _ in }
    var stopRecording: () -> Void = {}
    var offsetRecordingControls: () -> Void = {}
    var switchMode: () -> Void = {}
    var updateLocked: (Bool) -> Void = { _ in }
    var updateCancelTranslation: () -> Void = {}

    init() {
        control.backgroundColor = .clear
        control.isExclusiveTouch = true
        view = control

        imageView.contentMode = .scaleToFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22)
        ])

        let pressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        pressRecognizer.minimumPressDuration = 0
        pressRecognizer.cancelsTouchesInView = true
        control.addGestureRecognizer(pressRecognizer)

        updateIcon(animated: false)
        updateFade()
    }

    func lock() {
        guard case .recording = state else { return }
        state = .recording(locked: true, isCanceling: false)
    }

    func reset() {
        beginWorkItem?.cancel()
        beginWorkItem = nil
        cancelTranslation = 0
        updateCancelTranslation()
        updateLocked(false)
        state = .idle
    }

    func updateTheme(theme: PresentationTheme) {
        let tint: UIColor = theme.isDark ? .white : .black
        imageView.tintColor = tint
    }

    func setIconTransform(_ transform: CGAffineTransform) {
        imageView.transform = transform
    }
}

private extension LiquidChatMediaRecordingButton {
    func updateIcon(animated: Bool) {
        let name: String
        switch mode {
        case .audio:
            name = "mic"
        case .video:
            name = "video"
        }
        let apply = {
            self.imageView.image = UIImage(systemName: name)
        }
        if animated {
            UIView.transition(with: imageView, duration: 0.2, options: [.transitionCrossDissolve], animations: apply)
        } else {
            apply()
        }
    }

    func updateFade() {
        control.alpha = fadeDisabled ? 0.55 : 1.0
    }

    @objc func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        let coordinateView = control.superview ?? control
        let location = recognizer.location(in: coordinateView)

        switch recognizer.state {
        case .began:
            if case .recording(locked: true, isCanceling: false) = state {
                endRecording(true)
                reset()
                return
            }
            pressStartPoint = location
            onTrackingLocationChanged?(location)
            state = .pressing(pressStartTime: CACurrentMediaTime())
            scheduleBeginRecording()
        case .changed:
            onTrackingLocationChanged?(location)
            handleTranslation(location: location)
        case .ended, .cancelled, .failed:
            onTrackingLocationChanged?(nil)
            finishPress()
        default:
            break
        }
    }

    func scheduleBeginRecording() {
        beginWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, case .pressing = self.state else { return }
            self.state = .recording(locked: false, isCanceling: false)
            self.beginRecording()
        }
        beginWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    func handleTranslation(location: CGPoint) {
        guard case let .recording(locked, _) = state, !locked else { return }

        let dx = location.x - pressStartPoint.x
        let dy = location.y - pressStartPoint.y

        cancelTranslation = min(0, dx)
        updateCancelTranslation()

        let shouldCancel = dx < -48
        if shouldCancel {
            state = .recording(locked: false, isCanceling: true)
        } else if dy < -54 {
            lock()
        } else {
            state = .recording(locked: false, isCanceling: false)
        }
    }

    func finishPress() {
        beginWorkItem?.cancel()
        beginWorkItem = nil

        switch state {
        case let .pressing(pressStartTime):
            let duration = CACurrentMediaTime() - pressStartTime
            reset()
            if duration < 0.18 {
                switchMode()
                updateMode(mode: mode == .audio ? .video : .audio, animated: true)
            }
        case let .recording(locked, isCanceling):
            guard !locked else { return }
            let send = !isCanceling
            endRecording(send)
            reset()
        case .idle:
            break
        }
    }
}
