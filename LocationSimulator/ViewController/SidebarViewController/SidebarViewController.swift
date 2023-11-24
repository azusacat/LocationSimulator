//
//  SidebarController.swift
//  LocationSimulator
//
//  Created by David Klopp on 22.12.20.
//  Copyright © 2020 David Klopp. All rights reserved.
//

import AppKit
import LocationSpoofer
import SuggestionPopup

let kMinimumSidebarWidth = 250.0

let kEnableSidebarSearchField = {
    if #available(OSX 11.0, *) {
        return true
    } else {
        return false
    }
}()

class SidebarViewController: NSViewController {

    @IBOutlet var outlineView: NSOutlineView!

    /// Reference to the internal data source instance responsible for handling and displaying the device list.
    private var dataSource: SidebarDataSource?

    /// The observer when the cell selection changes.
    private var selectionObserver: NSObjectProtocol?
    private var locationObserver: NSObjectProtocol?

    /// The enclosing scrollView containing the outlineView.
    private var scrollView: NSScrollView? {
        self.outlineView.enclosingScrollView
    }

    /// The location search completer used on macOS 11 and greater.
    private var searchCompleter: LocationSearchCompleter?

    private var windowController: WindowController? {
        self.view.window?.windowController as? WindowController
    }

    // MARK: - Constructor

    override func viewDidLoad() {
        super.viewDidLoad()

        // Listen for selection changes to change the current view controller. Segues are broken beyond repair on macOS.
        self.registerOutlineViewActions()

        // Create a new data source to handle the devices.
        self.dataSource = SidebarDataSource(sidebarView: self.outlineView)
        self.outlineView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(self.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification, object: nil
        )

        // Load the default value for network devices.
        IOSDevice.detectNetworkDevices = UserDefaults.standard.detectNetworkDevices

        // Tell the datas source to start listening for new devices.
        self.dataSource?.registerDeviceNotifications()
        IOSDevice.startGeneratingDeviceNotifications()
        SimulatorDevice.startGeneratingDeviceNotifications()
        self.dataSource?.fetchTgLocationRecord()

        let timer = Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(proxyToFetchTgRecord), userInfo: nil, repeats: true)
        // Add a searchbar to the sidebar in macOS 11 and up
        if kEnableSidebarSearchField {
            self.setupSearchField()
        }
    }

    @objc func proxyToFetchTgRecord() {
        self.dataSource?.fetchTgLocationRecord()
    }
    deinit {
        // Stop listening for new devices
        IOSDevice.stopGeneratingDeviceNotifications()
        SimulatorDevice.stopGeneratingDeviceNotifications()

        // Remove the selection observer.
        if let observer = self.selectionObserver {
            NotificationCenter.default.removeObserver(observer)
            self.selectionObserver = nil
        }
        if let tgObserver = self.locationObserver {
            NotificationCenter.default.removeObserver(tgObserver)
            self.locationObserver = nil
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Relayout the findbar with the correct titlebar height.
        self.scrollView?.findBarView?.layout()
    }

    // MARK: - AppleScript Helper
    func select(device: Device?) {
        self.dataSource?.selectedDevice = device
    }

    // MARK: - macOS 11.0 SearchField

    var searchEnabled: Bool = false {
        didSet {
            let searchbarView = self.scrollView?.findBarView as? SearchbarView
            searchbarView?.userInteractionEnabled = self.searchEnabled
        }
    }

    private func setupSearchField() {
        let searchbarView = SearchbarView(frame: CGRect(x: 0, y: 0, width: 0, height: 40))
        searchbarView.userInteractionEnabled = false
        self.scrollView?.findBarView = searchbarView
        self.scrollView?.isFindBarVisible = true

        // We use closures instead of linkin the function, because the windowController is still nil on viewDidLoad
        let searchCompleter = LocationSearchCompleter(searchField: searchbarView.searchField)
        searchCompleter.minimumWindowWidth = kMinimumSidebarWidth + 15
        searchCompleter.onSelect = { [weak self] text, suggestion in
            self?.windowController?.searchBarOnSelect(text: text, suggestion: suggestion)
        }
        searchCompleter.onBecomeFirstReponder = { [weak self] in
            self?.windowController?.searchBarOnBecomeFirstReponder()
        }
        searchCompleter.onResignFirstReponder = { [weak self] in
            self?.windowController?.searchBarOnResignFirstReponder()
        }
        self.searchCompleter = searchCompleter
    }

    func clearSearchField() {
        let searchbarView = self.scrollView?.findBarView as? SearchbarView
        searchbarView?.searchField.stringValue = ""
    }

    func apply(sidebarStyle: SidebarStyle) {
        let backgroundEffectView = self.view.superview as? NSVisualEffectView
        backgroundEffectView?.blendingMode = sidebarStyle.blendingMode
        backgroundEffectView?.material = sidebarStyle.material

        let searchbarView = self.scrollView?.findBarView as? SearchbarView
        let headerEffectView = searchbarView?.effectView
        headerEffectView?.blendingMode = sidebarStyle.blendingMode
        headerEffectView?.material = sidebarStyle.material
    }

    // MARK: - Callback
    @objc private func scrollViewDidScroll(_ notification: Notification) {
        guard (notification.object as? NSView)?.enclosingScrollView == self.scrollView,
              let scrollView = self.scrollView, let searchbarView = scrollView.findBarView as? SearchbarView else {
            return
        }
        let offsetY = searchbarView.frame.maxY
        let contentOffsetY = -scrollView.documentVisibleRect.minY - offsetY
        searchbarView.showSeparatorShadow = contentOffsetY < 0
    }

    // MARK: - Selection changed

    private func registerOutlineViewActions() {
        self.locationObserver = NotificationCenter.default.addObserver(forName: Notification.Name("TGLocationChange"), object: nil, queue: .main, using: { selectionDidChangeNotification in
            NSLog("[Observer]location on change")
            if let selectedTgLocation = self.dataSource?.selectedTgLocations {
                NSLog("Selected name %@", selectedTgLocation.name)
//                let long: Double = 140.229372
//                let lat: Double = 22.426614
//                let coord = CLLocationCoordinate2D(latitude: lat, longitude: long)
                var a = selectedTgLocation.name.components(separatedBy: "]")
                if (a.count < 1) { return }
//                a.popLast()
                let b = a.last?.components(separatedBy: ",") ?? []
                if (b.count != 2) { return }
                let coord = try! arrayToCoordinate(b.map {
                    CGFloat(($0 as NSString).doubleValue)
                })
                self.windowController?.mapViewController?.teleportToStartAndNavigate(route: [coord])
//                self.windowController?.mapViewController?.requestTeleportOrNavigation(toCoordinate: coord)
//                , additionalRoute: <#T##[CLLocationCoordinate2D]#>) requestTeleportOrNavigation(toCoordinate: coord)
//                teleportToStartAndNavigate(route: [coord])
                
            }
            
        })
        self.selectionObserver = NotificationCenter.default.addObserver(
            forName: NSOutlineView.selectionDidChangeNotification, object: nil, queue: .main, using: { notification in
                // Only handle the relevant outline view.
                guard let siderbarView = notification.object as? NSOutlineView, siderbarView == self.outlineView else {
                    return
                }
                // We can only change the detail view if we find an enclosing splitView controller.
                guard let splitViewController = self.enclosingSplitViewController as? SplitViewController else {
                    return
                }
                let numOfSim = self.dataSource?.simDevices.count ?? 0
                let numOfReal = self.dataSource?.realDevices.count ?? 0
                if (self.dataSource?.sidebarView?.selectedRow ?? 0 > numOfSim + numOfReal + 3) {
                    return
                }
                // On macOS 11 use the line toolbar separator style for the MapViewController. Otherwise use None.
                var drawSeparator: Bool = false
                var viewController: Any?
                if let device = self.dataSource?.selectedDevice {
                    drawSeparator = true
                    // A device was connected => create and show the corresponding MapViewController.
                    viewController = self.storyboard?.instantiateController(withIdentifier: "MapViewController")
                    if let mapViewController = viewController as? MapViewController {
                        mapViewController.device = device
                        // Set the currently selected move type.
                        let windowController = self.view.window?.windowController as? WindowController
                        mapViewController.moveType = windowController?.moveType
                        mapViewController.speed = windowController?.speed ?? 0
                        mapViewController.mapType = UserDefaults.standard.mapType
                    }
                } else {
                    drawSeparator = false
                    // The last device was removed => create and show a NoDeviceViewController.
                    viewController = self.storyboard?.instantiateController(withIdentifier: "NoDeviceViewController")
                    // If the sidebar is currently hidden, show it. The user might not know where to select a device.
                    if splitViewController.isSidebarCollapsed {
                        splitViewController.toggleSidebar()
                    }
                }

                // Get a reference to the splitViewController and assign the new detailViewController
                splitViewController.detailViewController = viewController as? NSViewController
                // Adjust the style of the detail item to show a separator line for the MapViewController.
                if #available(OSX 11.0, *) {
                    splitViewController.splitViewItems[1].titlebarSeparatorStyle = drawSeparator ? .line : .none
                }
        })
    }
}
