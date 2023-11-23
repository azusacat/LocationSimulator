//
//  WindowController.swift
//  LocationSimulator
//
//  Created by David Klopp on 18.08.19.
//  Copyright © 2019 David Klopp. All rights reserved.
//

import Foundation
import AppKit
import MapKit
import CoreLocation
import GPXParser
import LocationSpoofer
import SuggestionPopup

/// The main window controller instance which hosts the map view and the toolbar.
class WindowController: NSWindowController {
    // MARK: - Enums

    enum RotateDirection {
        case clockwise
        case counterclockwise
    }

    enum MoveDirection {
        case up
        case down
        case left
        case right
    }

    // MARK: - Controller / Model

    /// The toolbar controller instance to handle the toolbar validation as well as the toolbar actions.
    @IBOutlet var toolbarController: ToolbarController!

    /// The touchbar controller instance to handle the touchbar validation as well as the touchbar actions.
    @IBOutlet var touchbarController: TouchbarController!

    // MARK: - ViewController

    /// Reference to the SplitViewController
    public var splitViewController: SplitViewController? {
        return self.contentViewController as? SplitViewController
    }

    /// Reference to the mapViewController if one exists.
    public var mapViewController: MapViewController? {
        return self.splitViewController?.detailViewController as? MapViewController
    }

    // MARK: - Model

    /// Internal reference to a location manager for this mac's location
    private let locationManager = LocationManager()

    /// The device status observer used to update toolbar and touchbar.
    private var statusObserver: NSObjectProtocol?

    // MARK: - Helper

    public var moveType: MoveType {
        guard self.toolbarController.moveType == self.touchbarController.moveType else {
            fatalError("Inconsistent moveType status between touchbar and toolbar!")
        }
        return self.toolbarController.moveType
    }

    public var mapType: MKMapType {
        return self.mapViewController?.mapType ?? .standard
    }

    public var speed: Double {
        return self.toolbarController.speed
    }

    // MARK: - Window lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        if #available(macOS 11.0, *) {
            self.window?.title = ""
            self.window?.titleVisibility = .visible
        }

        // Add callbacks for the `Get Mac location` button
        self.locationManager.onLocation = self.didGetMacLocation(_:)
        self.locationManager.onError = self.failedToGetMacLocation(_:)

        // Set the default move type
        self.setMoveType(.walk)

        // Disable the touchbar and toolbar.
        self.updateForDeviceStatus(.disconnected)

        // Listen for state changes to update the toolbar and touchbar.
        self.statusObserver = NotificationCenter.default.addObserver(forName: .StatusChanged, object: nil,
                                                                     queue: .main) { [weak self] notification in
            // Make sure the event belongs to this window (might be useful for multiple windows in the future).
            guard let viewController = notification.object as? NSViewController,
                  let windowController = viewController.view.window?.windowController,
                  windowController == self,
                  let newState = notification.userInfo?["status"] as? DeviceStatus else { return }
            // Update the UI for the new status
            self?.updateForDeviceStatus(newState)
        }
    }

    deinit {
        // Remove the observer
        if let observer = self.statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        self.statusObserver = nil
    }

    // MARK: - Search
    func searchBarOnSelect(text: String, suggestion: Suggestion) {
        // Disable autofocus since we want to zoom on the searched location and not on the current position
        self.setAutofocusEnabled(false)
        // Zoom into the map at the searched location.
        guard let comp = suggestion as? MKLocalSearchCompletion else { return }
        let request: MKLocalSearch.Request = MKLocalSearch.Request(completion: comp)
        let localSearch: MKLocalSearch = MKLocalSearch(request: request)
        localSearch.start { (response, error) in
            if error == nil, let res: MKLocalSearch.Response = response {
                self.mapViewController?.zoomTo(region: res.boundingRegion)
            }
       }
    }

    func searchBarOnBecomeFirstReponder() {
        NotificationCenter.default.post(name: .SearchDidStart, object: self.window)
    }

    func searchBarOnResignFirstReponder() {
        NotificationCenter.default.post(name: .SearchDidEnd, object: self.window)
    }

    // MARK: - Helper

    private func updateForDeviceStatus(_ status: DeviceStatus) {
        self.toolbarController.updateForDeviceStatus(status)
        self.touchbarController.updateForDeviceStatus(status)
        self.splitViewController?.updateForDeviceStatus(status)
    }

    /// Toggle the sidebar visibility.
    public func toggleSidebar() {
        self.splitViewController?.toggleSidebar()
    }

    /// Enabled / Disable the autofocus to current location feature.
    /// - Parameter enabled: enable or disable the autofocus
    public func setAutofocusEnabled(_ enabled: Bool) {
        self.mapViewController?.autofocusCurrentLocation = enabled
    }

    /// Enabled / Disable the autoreverse feature when navigating.
    /// - Parameter enabled: enable or disable the autoreverse
    public func setAutoreverseEnabled(_ enabled: Bool) {
        self.mapViewController?.autoreverseRoute = enabled
    }

    /// Reset the current location.
    public func resetLocation() {
        self.mapViewController?.resetLocation()
    }

    /// Set the currentlocation of this mac to the spoofed location.
    public func setLocationToCurrentLocation() {
        guard self.locationManager.locationServicesEnabled else {
            // Check if location services are enabled.
            self.window?.showError("LOCATION_SERVICE_DISABLED", message: "LOCATION_SERVICE_DISABLED_MSG")
            return
        }
        // Request the permission to access the mac's location and call the callback functions with the new
        // location.
        self.locationManager.requestLocationAndPermissionIfRequired()
    }

    func didGetMacLocation(_ coordinate: CLLocationCoordinate2D) {
        self.requestLocationChange(coord: coordinate)
    }

    func failedToGetMacLocation(_ error: Error) {
        self.window?.showError("GET_LOCATION_ERROR", message: "GET_LOCATION_ERROR_MSG")
    }

    /// Present an alert to the user to allow him to change the speed.
    public func requestAndApplySpeedChange() {
        guard let window = self.window, !(self.mapViewController?.isShowingAlert ?? false) else {
            // We already present a sheet
            NSSound.beep()
            return
        }

        self.mapViewController?.isShowingAlert = true
        let currentSpeed = max(self.mapViewController?.speed ?? 0, CLLocationSpeed(inKmH: kMinSpeed))

        let changeSpeedAlert = SpeedSelectionAlert(defaultValue: currentSpeed)
        changeSpeedAlert.beginSheetModal(for: window) { [weak self] (response, speed) in
            self?.mapViewController?.isShowingAlert = false
            if response == .OK {
                let speedInMS = CLLocationSpeed(inKmH: speed)
                self?.setSpeed(speedInMS)
                self?.toolbarController.speed = speedInMS
            }
        }
    }

    /// Request a location change to the give coordinates. If no coordinates are specified, a coordinate selection
    /// view will be shown to the user.
    /// - Parameter coord: the new coordinates.
    public func requestLocationChange(coord: CLLocationCoordinate2D? = nil) {
        if let isShowingAlert = self.mapViewController?.isShowingAlert, isShowingAlert {
            // We can only request one location change at a time.
            NSSound.beep()
        } else {
            // Request the location change.
            self.mapViewController?.requestTeleportOrNavigation(toCoordinate: coord)
        }
    }

    /// Change the current move type.
    /// - Parameter moveType: The new move type to select.
    public func setMoveType(_ moveType: MoveType) {
        // Update the UI.
        self.toolbarController.moveType = moveType
        self.touchbarController.moveType = moveType
        // Update the actual move type.
        self.mapViewController?.moveType = moveType

        // Update the menubar selection
        NavigationMenubarItem.selectMoveItem(forMoveType: moveType)

        // Change the speed to the default speed value for this move type
        self.mapViewController?.speed = moveType.speed
    }

    /// Change the current movement speed.
    /// - Parameter speed: new speed value in m/s
    public func setSpeed(_ speed: CLLocationSpeed) {
        self.mapViewController?.speed = speed
    }

    /// Toggle between the automove and the manual move state. If a navigation is running, it will be paused / resumed.
    public func toggleAutoMove() {
        self.mapViewController?.toggleAutoMove()
    }

    /// Stop the current navigation.
    public func stopNavigation() {
        self.mapViewController?.stopNavigation()
    }

    /// Move the spoofed location using the traditional behaviour.
    /// - Parameter direction: up or down
    public func moveTraditional(_ direction: MoveDirection) {
        guard let angle = self.mapViewController?.getDirectionViewAngle() else { return }
        switch direction {
        //    |                 x | x      x | x               x | x
        // ---|--- ==========> ---|--- or ---|--- ==========> ---|---
        //  x | x   arrow up      |          |     arrow up      |
        case .up:   self.mapViewController?.move(flip: angle > 90 && angle < 270)
        //  x | x                 |          |                   |
        // ---|--- ==========> ---|--- or ---|--- ==========> ---|---
        //    |    arrow down   x | x      x | x  arrow down   x | x
        case .down: self.mapViewController?.move(flip: angle < 90 || angle > 270)
        // Do nothing on left or right.
        default: break
        }
    }

    /// Move the spoofed location using the natural behaviour.
    /// - Parameter direction: up, down, left or right
    public func moveNatural(_ direction: MoveDirection) {
        switch direction {
        case .up:
            self.mapViewController?.rotateDirectionViewTo(0)
            self.mapViewController?.move(flip: false)
        case .left:
            self.mapViewController?.rotateDirectionViewTo(90)
            self.mapViewController?.move(flip: false)
        case .down:
            self.mapViewController?.rotateDirectionViewTo(180)
            self.mapViewController?.move(flip: false)
        case .right:
            self.mapViewController?.rotateDirectionViewTo(270)
            self.mapViewController?.move(flip: false)
        }
    }

    /// Rotate the direction overlay.
    /// - Parameter direction: clockwise or counterclockwise
    public func rotate(_ direction: RotateDirection) {
        switch direction {
        case .clockwise:        self.mapViewController?.rotateDirectionViewBy(-5.0)
        case .counterclockwise: self.mapViewController?.rotateDirectionViewBy(5.0)
        }
    }

    /// Return a list with all coordinates if only a signle type of points is found.
    private func uniqueCoordinates(waypoints: [WayPoint], routes: [Route],
                                   tracks: [Track]) -> [CLLocationCoordinate2D]? {
        // More than one track or route
        if tracks.count > 1 || routes.count > 1 {
            return nil
        }

        // Check if there is a single unique point collection to use
        let routepoints = routes.flatMap { $0.routepoints }
        let trackpoints = tracks.flatMap { $0.segments.flatMap { $0.trackpoints } }
        let points: [[GPXPoint]] = [waypoints, routepoints, trackpoints]
        let filteredPoints = points.filter { $0.count > 0 }

        // Return the coordinates with the unique points.
        return filteredPoints.count == 1 ? filteredPoints[0].map { $0.coordinate } : nil
    }

    /// Request to open a GPX file.
    public func requestGPXOpenDialog() {
        guard let window = self.window else { return }

        // Prepare the open file dialog
        let title = "CHOOSE_GPX_FILE"
        let (res, url): (NSApplication.ModalResponse, URL?) = window.showOpenPanel(title, extensions: ["gpx"])

        // Make sure everything is working as expected.
        guard res == .OK, let gpxFile = url else { return }
        do {
            // Try to parse the GPX file
            let parser = try GPXParser(file: gpxFile)
            parser.parse { result in
                switch result {
                case .success:
                    // Successfully opened the file
                    let waypoints = parser.waypoints
                    let routes = parser.routes
                    let tracks = parser.tracks

                    // Start the navigation of the GPX route if there is only one unique route to use.
                    if let coords = self.uniqueCoordinates(waypoints: waypoints, routes: routes, tracks: tracks) {
                        self.mapViewController?.requestGPXRouting(route: coords)
                    } else {
                        // Show a user selection window for the waypoints / routes / tracks.
                        let alert = GPXSelectionAlert(tracks: tracks, routes: routes, waypoints: waypoints)
                        alert.beginSheetModal(for: window) { response, coordinates in
                            guard response == .OK else { return }
                            self.mapViewController?.requestGPXRouting(route: coordinates)
                        }
                    }
                // Could not parse the file.
                case .failure: window.showError("ERROR_PARSE_GPX", message: "ERROR_PARSE_GPX_MSG")
                }
            }
        } catch {
            // Could not open the file.
            window.showError("ERROR_OPEN_GPX", message: "ERROR_OPEN_GPX_MSG")
        }
    }

    /// Zoom in the mapView.
    public func zoomInMap() {
        self.mapViewController?.zoomIn()
    }

    /// Zoom out the mapView.
    public func zoomOutMap() {
        self.mapViewController?.zoomOut()
    }

    /// Change the MapType of the current map.
    public func setMapType(_ mapType: MKMapType) {
        self.mapViewController?.mapType = mapType
        ViewMenubarItem.selectMapTypeItem(forMapType: mapType)
    }
}
