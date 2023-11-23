//
 //  ContentView.swift
 //  LocationSimulator
 //
 //  Created by David Klopp on 14.08.20.
 //  Copyright © 2020 David Klopp. All rights reserved.
 //

import AppKit
import MapKit

typealias ErrorIndicatorAction = () -> Void

/// This is the main content view. It includes the mapView and all the controls that overlay the mapView.
/// Since this view contains links to the interface builders main storyboard, it belongs to this viewController and
/// not to the general Views group.
class ContentView: NSView {
    @IBOutlet weak var mapView: MapView! {
        didSet {
            if #available(OSX 11.0, *) {
                if self.compassButton == nil {
                    // Hide the default compass.
                    self.mapView?.showsCompass = false
                    // Create a new compass button.
                    let compass = MKCompassButton(mapView: self.mapView)
                    compass.compassVisibility = .visible
                    self.addSubview(compass)
                    // Assign the new compass button
                    self.compassButton = compass
                }

                if self.zoomControl == nil {
                    // Hide the original zoom controls
                    self.mapView?.showsZoomControls = false
                    // Add the new zoom controls
                    let zoomControl = MKZoomControl(mapView: self.mapView)
                    self.addSubview(zoomControl)
                    // Assign the new zoom controls
                    self.zoomControl = zoomControl
                }

                NotificationCenter.default.addObserver(
                    self, selector: #selector(mapViewFrameChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: nil
                )
            }
        }

    }

    /// The spinner in the top right corner.
    @IBOutlet var spinnerHUD: SpinnerHUDView!

    /// The direction outer circle.
    @IBOutlet var movementDirectionHUD: MovementDirectionHUDView!

    /// The movement button.
    @IBOutlet var movementButtonHUD: MovementButtonHUDView!

    /// The error indicator in the lower right corner.
    @IBOutlet var errorIndicator: NSImageView! {
        didSet {
            // Add a click gesture to the view.
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(errorIndicatorClicked(_:)))
            self.errorIndicator.addGestureRecognizer(clickGesture)
        }
    }

    @IBOutlet var errorIndicatorWidthConstraint: NSLayoutConstraint!

    /// The play pause indicator to show if a navigation is active
    @IBOutlet var playPauseIndicator: NSImageView!

    /// The label in the bottom bar which displays the total amount of meters you walked.
    @IBOutlet var totalDistanceLabel: NSTextField!

    /// The container view which contains the button and the control.
    @IBOutlet var movementContainer: NSView! {
        didSet {
            // Make the view layer backed.
            self.movementContainer.wantsLayer = true
            // Add a rotation gesture recognizer to the movement container.
            let recognizer = NSRotationGestureRecognizer(target: self, action: #selector(directionHUDRotateByGesture))
            self.movementContainer.addGestureRecognizer(recognizer)
        }
    }

    // MARK: - MACOS 11.0

    /// Background for the footer bar on macOS > 11
    @IBOutlet var labelHUD: HUDView! {
        didSet {
            // Show a nice HUD background on macOS 11
            if #available(OSX 11.0, *) {
                self.labelHUD.cornerRadius = 0
                self.labelHUD.isHidden = false
            } else {
                self.labelHUD.isHidden = true
            }
        }
    }

    /// The bottom constraint of the content view. The default for macOS versions fewer 11 is 20.
    @IBOutlet var bottomConstraint: NSLayoutConstraint! {
        didSet { if #available(OSX 11.0, *) { self.bottomConstraint.constant = 0 } }
    }

    @IBOutlet var totalDistanceLabelTopConstraint: NSLayoutConstraint! {
        didSet { if #available(OSX 11.0, *) { self.totalDistanceLabelTopConstraint.constant -= 20 } }
    }

    @IBOutlet var movementContainerWidthConstraint: NSLayoutConstraint! {
        didSet { if #available(OSX 11.0, *) { self.movementContainerWidthConstraint.constant -= 4 } }
    }

    @IBOutlet var movementContainerHeightConstraint: NSLayoutConstraint! {
        didSet { if #available(OSX 11.0, *) { self.movementContainerHeightConstraint.constant -= 4 } }
    }

    /// MacOS 11 > only: The custom compass view.
    private var compassButton: NSView?

    /// MacOS 11 > only: The custom zoom control.
    private var zoomControl: NSView?

    /// MacOS 11 > only: The predefined scale view.
    private var scaleView: NSView? {
        return self.mapView.subviews.first(where: { $0.className == "MKScaleView" })
    }

    /// The heading of the mapView
    var cameraHeading: CLLocationDirection {
        self.mapView.camera.heading
    }

    // MARK: - Interaction

    /// Show or hide the navigation controls in the lower left corner.
    public var controlsHidden: Bool {
        get { self.movementContainer.isHidden }
        set { self.movementContainer.isHidden = newValue }
    }

    /// The action to perform when the error indicator is clicked.
    public var errorIndicationAction: ErrorIndicatorAction?

    // MARK: - Private

    /// Starting angle for the direction overlay rotation.
    private var startAngleInDegrees: Double = 0.0

    // MARK: - Helper

    public func reset() {
        // reset the total distance label
        self.setTotalDistance(meter: 0)
        // hide the controls
        self.controlsHidden = true
        // show the error indicator on first view appearance.
        self.showErrorInidcator()
    }

    @objc private func errorIndicatorClicked(_ sender: Any) {
        // Disable the user interaction while the action is performed.
        self.errorIndicator.isEnabled = false
        self.errorIndicationAction?()
        self.errorIndicator.isEnabled = true
    }

    // MARK: - Layout

    @objc func mapViewFrameChanged(_ notification: Notification) {
        guard notification.object as? NSView == self.scaleView else { return }
        // Ugly hack to move the predefined scale view whenever the system tries to position it
        // MKScaleView is private on macOS for whatever reason...
        let mapOverlayWidthBehindSidebar = self.mapView.frame.width - self.frame.width
        self.scaleView?.frame.origin.x = mapOverlayWidthBehindSidebar
    }

    override func layout() {
        if #available(OSX 11.0, *) {
            // Layout the compass view.
            // self.compassButton?.frame = self.convert(self.movementDirectionHUD.frame, from: self.movementContainer)
            let controlFrame = self.convert(self.movementDirectionHUD.frame, from: self.movementContainer)
            let padX = controlFrame.origin.x
            let padY = controlFrame.origin.y
            let offX = self.frame.size.width - (self.compassButton?.bounds.width ?? 0) - padX

            self.compassButton?.frame.origin.x = offX
            self.compassButton?.frame.origin.y = padY

            let zoomControlWidth = self.zoomControl?.frame.width ?? 0
            self.zoomControl?.frame.origin.x = (self.compassButton?.frame.minX ?? 0) - zoomControlWidth - padX
            self.zoomControl?.frame.origin.y = padY
        }
        super.layout()
    }

    // MARK: - Gesture Recognizer

    /// Rotate the translation overlay to a specific angle given in degrees.
    public func rotateDirectionHUD(toAngleInDegrees angle: Double) {
        self.movementDirectionHUD.rotateyTo(angleInDegrees: angle)
    }

    /// Rotate the translation overlay to a specific angle given in rad.
    public func rotateDirectionHUD(toAngleInRad angle: Double) {
        self.movementDirectionHUD.rotateTo(angleInRad: angle)
    }

    @objc private func directionHUDRotateByGesture(sender: NSRotationGestureRecognizer) {
        switch sender.state {
        case .began, .ended:
            self.startAngleInDegrees = self.movementDirectionHUD.currentHeadingInDegrees
        case .changed:
            let deltaAngle = Double(sender.rotation * 180 / .pi)
            self.rotateDirectionHUD(toAngleInDegrees: self.startAngleInDegrees + deltaAngle)
        default:
            break
        }
    }

    // MARK: - Spinner

    /// Show an animated progress spinner in the upper right corner.
    public func startSpinner() {
        self.spinnerHUD.startSpinning()
        self.spinnerHUD.isHidden = false
    }

    /// Hide and stop the progress spinner in the upper right corner.
    public func stopSpinner() {
        self.spinnerHUD.stopSpinning()
        self.spinnerHUD.isHidden = true
    }

    // MARK: - Bottom bar

    /// Change the text of the total distance label.
    /// - Parameter meter: the amount of meters walked
    public func setTotalDistance(meter: Double) {
        let totalDistanceInKM = meter / 1000.0
        let labelText = "TOTAL_DISTANCE".localized
        self.totalDistanceLabel.stringValue = String(format: labelText, totalDistanceInKM)
    }

    /// Show the warning triangle in the lower right corner.
    public func showErrorInidcator() {
        self.errorIndicatorWidthConstraint.constant = 38
        self.errorIndicator.isHidden = false
    }

    /// Hide the warning triangle in the lower right corner.
    public func hideErrorInidcator() {
        self.errorIndicatorWidthConstraint.constant = 0
        self.errorIndicator.isHidden = true
    }

    /// Show a pause icon in the  lower right corner.
    public func showPauseIndicator() {
        self.playPauseIndicator.image = .pauseImage.tint(color: .secondaryLabelColor)
        self.playPauseIndicator.isHidden = false
    }

    /// Show a play icon in the  lower right corner.
    public func showPlayIndicator() {
        self.playPauseIndicator.image = .playImage.tint(color: .secondaryLabelColor)
        self.playPauseIndicator.isHidden = false
    }

    /// Hide the play or pause icon in the lower right corner.
    public func hidePlayPauseIndicator() {
        self.playPauseIndicator.isHidden = true
    }
 }
