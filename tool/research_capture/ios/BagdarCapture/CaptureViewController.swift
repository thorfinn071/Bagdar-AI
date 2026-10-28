import UIKit

final class CaptureViewController: UIViewController {
  private let recorder = CaptureRecorder()
  private let status = UILabel()
  private let consent = UISwitch()
  private let export = UIButton(type: .system)
  private let start = UIButton(type: .system)
  private var selectedFolder: URL?
  private var recorderBusy = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    title = "Bagdar Research Capture"
    let explanation = UILabel()
    explanation.text = "Research recording only. Remain stationary in a prepared scene. No walking guidance. RGB images may contain private information. Data stays on this phone until you export it."
    explanation.numberOfLines = 0
    explanation.font = .preferredFont(forTextStyle: .body)
    explanation.adjustsFontForContentSizeCategory = true
    let consentLabel = UILabel()
    consentLabel.text = "I consent to this local recording"
    consentLabel.numberOfLines = 0
    consent.accessibilityLabel = consentLabel.text
    consent.addTarget(self, action: #selector(consentChanged), for: .valueChanged)
    start.setTitle("Start recording", for: .normal)
    start.isEnabled = false
    start.addTarget(self, action: #selector(startRecording), for: .touchUpInside)
    let stop = UIButton(type: .system)
    stop.setTitle("Stop recording", for: .normal)
    stop.addTarget(self, action: #selector(stopRecording), for: .touchUpInside)
    export.setTitle("Export selected recording", for: .normal)
    export.isEnabled = false
    export.addTarget(self, action: #selector(exportRecording), for: .touchUpInside)
    status.numberOfLines = 0
    status.font = .preferredFont(forTextStyle: .body)
    status.adjustsFontForContentSizeCategory = true
    status.text = "Ready to request camera access. Recordings are not calibration or safety evidence."
    let row = UIStackView(arrangedSubviews: [consentLabel, consent]); row.spacing = 12
    let stack = UIStackView(arrangedSubviews: [explanation, row, start, stop, export, status])
    stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll); scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)])
    for button in [start, stop, export] {
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
      button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
      button.titleLabel?.adjustsFontForContentSizeCategory = true
    }
    recorder.onStatus = { [weak self] message, folder, ready in
      guard let self else { return }
      self.status.text = message
      self.recorderBusy = !ready
      self.start.isEnabled = self.consent.isOn && ready
      if let folder { self.selectedFolder = folder; self.export.isEnabled = true }
      UIAccessibility.post(notification: .announcement, argument: message)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
                                           name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  private func updateOrientation() {
    let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
    let name: String
    switch orientation {
    case .landscapeLeft: name = "landscapeLeft"
    case .landscapeRight: name = "landscapeRight"
    case .portraitUpsideDown: name = "portraitUpsideDown"
    default: name = "portrait"
    }
    recorder.setOrientation(name)
  }

  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: nil) { _ in self.updateOrientation() }
  }

  @objc private func consentChanged() { start.isEnabled = consent.isOn && !recorderBusy }
  @objc private func startRecording() {
    updateOrientation(); recorderBusy = true; start.isEnabled = false; export.isEnabled = false
    selectedFolder = nil
    recorder.start(consentConfirmed: consent.isOn)
  }
  @objc private func stopRecording() { recorder.stop() }
  @objc private func backgrounded() { recorder.stop(reason: "background", failed: true) }
  @objc private func exportRecording() {
    guard let folder = selectedFolder else { return }
    export.isEnabled = false
    DispatchQueue.global(qos: .utility).async {
      do {
        let output = folder.deletingLastPathComponent().appendingPathComponent(
          folder.lastPathComponent + "-" + UUID().uuidString + ".zip")
        try StoredZip.create(folder: folder, output: output)
        DispatchQueue.main.async {
          self.export.isEnabled = true
          let share = UIActivityViewController(activityItems: [output], applicationActivities: nil)
          share.popoverPresentationController?.sourceView = self.export
          self.present(share, animated: true)
        }
      } catch {
        DispatchQueue.main.async { self.status.text = "Export failed: \(error)"; self.export.isEnabled = true }
      }
    }
  }
}
