//
//  ProgressViewAlert.swift
//  LocationSimulator
//
//  Created by David Klopp on 21.12.20.
//  Copyright © 2020 David Klopp. All rights reserved.
//

import AppKit
import Downloader

/// Extend the response for a more readable format.
extension NSApplication.ModalResponse {
    static let failed = NSApplication.ModalResponse(10002)
}

/// Alert view which manages and shows the download progress for the developer disk images.
class DownloadProgressAlert: NSAlert {
    public var progressView: ProgressListView? {
        return self.accessoryView as? ProgressListView
    }

    public var downloadListViewController = DownloadListViewController()

    public private(set) var developerDiskImage: DeveloperDiskImage

    init(developerDiskImage: DeveloperDiskImage) {
        self.developerDiskImage = developerDiskImage

        super.init()

        self.messageText = "PROGRESS".localized
        self.informativeText = ""
        let cancelButton = self.addButton(withTitle: "CANCEL".localized)
        self.alertStyle = .critical

        // Setup the accessory view with the download progress bars and status labels.
        self.accessoryView = self.downloadListViewController.view

        // Cancel the download if the cancel button is clicked.
        cancelButton.target = self.downloadListViewController
        cancelButton.action = #selector(self.downloadListViewController.cancelDownload)
    }

    // MARK: - Sheet modal

    @objc private func stopModal(_ code: NSNumber) {
        NSApp.stopModal(withCode: NSApplication.ModalResponse(code.intValue))
    }

    @objc private func showModal(forWindow window: NSWindow) {
        self.beginSheetModal(for: window)
    }

    /// Run a sheet modal and block until the user cancels the operation or the download is finished.
    /// While this sheet is showing, the user can not interact with the app. It is therefore reasonable to
    /// block until the operation is finished.
    /// - Parameter window: the window to present the alert in.
    func runSheetModal(forWindow window: NSWindow) -> NSApplication.ModalResponse {
        // Add a callback when the download finished to dismiss the window.
        self.downloadListViewController.downloadFinishedAction = { [weak self] status in
            var response: NSApplication.ModalResponse = .failed
            switch status {
            case .failure: response = .failed
            case .success: response = .OK
            case .cancel:  response = .cancel
            }

            // Stop the modal. Make sure we use the correct runloop and thread by using performSelector.
            guard let `self` = self else { return }
            self.performSelector(onMainThread: #selector(self.stopModal(_:)),
                                 with: NSNumber(value: response.rawValue), waitUntilDone: true)
        }

        // Update the download links for the developer disk images. This is allowed to fail
        self.downloadListViewController.updateFinishedAction = { [weak self] status in
            guard let `self` = self else { return }

            var response: NSApplication.ModalResponse?
            if status == .cancel {
                // Update was canceled
                response = .cancel
            } else if !self.downloadListViewController.prepareDownload(developerDiskImage) {
                // Prepare the download
                response = .failed
            } else {
                self.downloadListViewController.startDownload()
            }

            if let response = response {
                // Stop the modal. Make sure we use the correct runloop and thread by using performSelector.
                self.performSelector(onMainThread: #selector(self.stopModal(_:)),
                                     with: NSNumber(value: response.rawValue), waitUntilDone: true)
            }
        }

        // Update the download links for the developer disk images. This is allowed to fail
        self.downloadListViewController.updateDeveloperDiskImageDownloadLinks()

        // Show the sheet. Make sure we use the correct runloop and thread by using performSelector.
        self.performSelector(onMainThread: #selector(showModal(forWindow:)), with: window, waitUntilDone: true)
        // Just grab the last sheet... let's hope that no other sheet for some reason came in between.
        let sheet = window.sheets.last

        // Wait till modal completion.
        let response = NSApp.runModal(for: window)

        // Dismiss the sheet.
        if let sheet = sheet {
            window.endSheet(sheet)
        }

        return response
    }
}
