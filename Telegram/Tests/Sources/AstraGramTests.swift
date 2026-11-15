import XCTest
import Foundation

/// End-to-end checks of AstraGram's features on Telegram's test servers.
///
/// The app is launched with `--ui-test` (test servers, fresh data) and logs in to a test account. The other side of
/// the chat is a second test account driven by `astragram/uitest/peer_controller.py`, which runs on the host and is
/// reached over HTTP: it sends, edits and deletes messages and reports what the other side sees (read state, typing,
/// online status, whether view-once media was reported as opened). Every check and a screenshot of every step are
/// sent to the controller, which writes the report.
final class AstraGramTests: XCTestCase {
    private let controllerUrl = URL(string: "http://127.0.0.1:8765")!
    private var app: XCUIApplication!
    private var stepIndex = 0

    // MARK: Controller

    @discardableResult
    private func call(_ path: String, _ query: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 120.0) -> [String: Any] {
        var components = URLComponents(url: self.controllerUrl.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        if let body = body {
            request.httpMethod = "POST"
            request.httpBody = body
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any] = [:]
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                result = object
            } else if let error = error {
                result = ["error": "\(error)"]
            }
            semaphore.signal()
        }.resume()
        let _ = semaphore.wait(timeout: .now() + timeout + 5.0)
        return result
    }

    private func log(_ message: String) {
        NSLog("[AstraTest] \(message)")
        self.call("log", ["message": message])
    }

    private func screenshot(_ name: String) {
        self.stepIndex += 1
        let data = XCUIScreen.main.screenshot().pngRepresentation
        self.call("screenshot", ["name": String(format: "%02d-%@", self.stepIndex, name)], body: data)
    }

    private func check(_ name: String, _ passed: Bool, _ detail: String) {
        self.log("\(passed ? "PASS" : "FAIL") \(name): \(detail)")
        self.call("result", ["name": name, "passed": passed ? "1" : "0", "detail": detail])
        XCTAssertTrue(passed, "\(name): \(detail)")
    }

    // MARK: UI helpers

    private func element(containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", text, text)
        return self.app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func waitFor(_ text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            self.dismissSystemAlerts()
            if self.element(containing: text).exists {
                return true
            }
            sleep(1)
        }
        return false
    }

    /// Taps through system permission alerts (notifications, contacts), which would otherwise cover the app.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Allow", "Allow Full Access", "OK", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    private func tapFirstExisting(_ candidates: [XCUIElement]) -> Bool {
        for candidate in candidates where candidate.exists && candidate.isHittable {
            candidate.tap()
            return true
        }
        return false
    }

    private func sleepSeconds(_ seconds: UInt32) {
        sleep(seconds)
        self.dismissSystemAlerts()
    }

    // MARK: Login

    private func login(phone: String, code: String) -> Bool {
        let startButton = self.app.buttons["Auth.Welcome.StartButton"]
        guard startButton.waitForExistence(timeout: 30.0) else {
            self.screenshot("no-welcome-screen")
            return false
        }
        startButton.tap()

        let countryCodeField = self.app.textFields["Auth.PhoneEntry.CountryCodeField"]
        guard countryCodeField.waitForExistence(timeout: 15.0) else {
            self.screenshot("no-phone-entry")
            return false
        }
        countryCodeField.tap()
        for _ in 0 ..< 10 {
            countryCodeField.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        // Test numbers are 99966XYYYY: country code 999, number 66XYYYY.
        countryCodeField.typeText(String(phone.prefix(3)))
        let phoneNumberField = self.app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        phoneNumberField.tap()
        phoneNumberField.typeText(String(phone.dropFirst(3)))
        self.screenshot("phone-entered")

        let continueButton = self.app.buttons["Auth.PhoneEntry.ContinueButton"]
        guard continueButton.waitForExistence(timeout: 5.0) else {
            return false
        }
        continueButton.tap()
        let confirmButton = self.app.buttons["Auth.PhoneConfirm.ContinueButton"]
        if confirmButton.waitForExistence(timeout: 10.0) {
            confirmButton.tap()
        }

        let codeField = self.app.textFields["Auth.CodeEntry.CodeField"]
        guard codeField.waitForExistence(timeout: 30.0) else {
            self.screenshot("no-code-entry")
            return false
        }
        codeField.typeText(code)

        // A new account asks for a name; the controller signs the account up beforehand, but handle both.
        let firstNameField = self.app.textFields["Auth.SetName.FirstNameField"]
        if firstNameField.waitForExistence(timeout: 10.0) {
            firstNameField.tap()
            firstNameField.typeText("Astra")
            let signUpButton = self.app.buttons["Auth.SetName.ContinueButton"]
            if signUpButton.waitForExistence(timeout: 3.0) {
                signUpButton.tap()
            }
        }
        self.sleepSeconds(8)
        self.dismissSystemAlerts()
        self.sleepSeconds(2)
        self.screenshot("after-login")
        return true
    }

    // MARK: Test

    func testAstraGramFeatures() throws {
        self.continueAfterFailure = true

        let setup = self.call("setup", timeout: 600.0)
        guard let appPhone = setup["app_phone"] as? String, let code = setup["code"] as? String, let peerName = setup["peer_name"] as? String else {
            XCTFail("peer controller setup failed: \(setup)")
            return
        }

        let settings: [String: Any] = [
            "hideOnlineStatus": true,
            "hideReadReceipts": true,
            "hideStoryViews": true,
            "hideTyping": true,
            "hideMessageContentsRead": true,
            "markReadAfterSend": true,
            "saveDeletedMessages": true,
            "keepDeletedMessagesInChat": true,
            "saveEditHistory": true,
            "keepSelfDestructingMedia": true
        ]
        let settingsData = try JSONSerialization.data(withJSONObject: settings)

        self.app = XCUIApplication()
        self.app.launchArguments += ["--ui-test", "--astra-settings", settingsData.base64EncodedString()]
        self.app.launch()

        guard self.login(phone: appPhone, code: code) else {
            self.check("login", false, "could not log in to the test account")
            return
        }

        // The peer writes first, so the chat appears in the chat list.
        let started = self.call("start_chat", timeout: 180.0)
        self.log("start_chat: \(started)")
        guard self.waitFor(peerName, timeout: 60.0) else {
            self.screenshot("no-chat-in-list")
            self.check("login", false, "the chat with \(peerName) did not appear")
            return
        }
        self.check("login", true, "logged in, chat with \(peerName) is in the list")
        self.element(containing: peerName).tap()
        self.sleepSeconds(4)
        self.screenshot("chat-opened")

        // Ghost mode: online status.
        self.sleepSeconds(6)
        let status = self.call("status")["status"] as? String ?? "?"
        self.check("ghost.online", status != "UserStatusOnline", "the peer sees status \(status)")

        // Ghost mode: read receipts.
        let readCheck = self.call("send_text", ["text": "ghost read check"])
        let readCheckId = readCheck["id"] as? Int ?? 0
        let readCheckShown = self.waitFor("ghost read check", timeout: 30.0)
        self.check("receive.text", readCheckShown, "an incoming message is shown in the open chat")
        self.sleepSeconds(8)
        let readStateBefore = self.call("read_state")["read_outbox_max_id"] as? Int ?? -1
        self.check("ghost.read", readStateBefore < readCheckId, "the peer's read_outbox_max_id is \(readStateBefore), the message is \(readCheckId)")
        self.screenshot("ghost-read")

        // Ghost mode: typing.
        self.call("reset_typing")
        let input = self.app.textViews.firstMatch
        if input.waitForExistence(timeout: 5.0) {
            input.tap()
            input.typeText("typing check")
            self.sleepSeconds(7)
            let typing = self.call("typing")["count"] as? Int ?? -1
            self.check("ghost.typing", typing == 0, "the peer received \(typing) typing updates")
            self.screenshot("typed")

            // Mark read after send.
            let sendButton = self.app.buttons["Send"]
            if self.tapFirstExisting([sendButton, self.element(containing: "Send")]) {
                self.sleepSeconds(8)
                let readStateAfter = self.call("read_state")["read_outbox_max_id"] as? Int ?? -1
                let received = self.call("last_incoming")["text"] as? String ?? ""
                self.check("send.text", received.contains("typing check"), "the peer received \"\(received)\"")
                self.check("ghost.markReadAfterSend", readStateAfter >= readCheckId, "after sending, read_outbox_max_id is \(readStateAfter)")
                self.screenshot("sent")
            } else {
                self.screenshot("no-send-button")
                self.check("send.text", false, "the send button was not found")
            }
        } else {
            self.screenshot("no-input")
            self.check("ghost.typing", false, "the message input was not found")
        }

        // Anti-delete.
        let deleted = self.call("send_text", ["text": "this will be deleted"])
        let deletedId = deleted["id"] as? Int ?? 0
        let _ = self.waitFor("this will be deleted", timeout: 30.0)
        self.sleepSeconds(3)
        self.call("delete", ["id": "\(deletedId)"])
        self.sleepSeconds(8)
        self.check("antidelete.keep", self.element(containing: "this will be deleted").exists, "a message deleted by the peer is still shown")
        self.screenshot("antidelete")

        // Edit history.
        let edited = self.call("send_text", ["text": "original version"])
        let editedId = edited["id"] as? Int ?? 0
        let _ = self.waitFor("original version", timeout: 30.0)
        self.sleepSeconds(3)
        self.call("edit", ["id": "\(editedId)", "text": "edited version"])
        let editShown = self.waitFor("edited version", timeout: 30.0)
        self.check("edit.update", editShown, "the edited text is shown")
        let editedMessage = self.element(containing: "edited version")
        if editedMessage.exists {
            editedMessage.press(forDuration: 1.2)
            self.sleepSeconds(2)
            self.screenshot("context-menu")
            let historyItem = self.element(containing: "Edit History")
            if historyItem.exists {
                historyItem.tap()
                self.sleepSeconds(3)
                self.screenshot("edit-history")
                self.check("edit.history", self.element(containing: "original version").exists, "the edit history shows the original text")
                let _ = self.tapFirstExisting([self.app.buttons["Back"], self.app.buttons["Close"], self.app.buttons["Done"]])
                self.sleepSeconds(2)
            } else {
                self.check("edit.history", false, "no Edit History item in the context menu")
                self.app.swipeDown()
                self.sleepSeconds(2)
            }
        }
        self.screenshot("after-edit")

        // View-once photo.
        let viewOnce = self.call("send_view_once", timeout: 180.0)
        let viewOnceId = viewOnce["id"] as? Int ?? 0
        self.sleepSeconds(8)
        self.screenshot("view-once-received")
        let photoPredicate = NSPredicate(format: "label CONTAINS[c] 'photo' OR label CONTAINS[c] 'view once' OR label CONTAINS[c] 'self-destruct'")
        let photos = self.app.descendants(matching: .any).matching(photoPredicate)
        self.log("photo-like elements: \(photos.count)")
        var opened = false
        if photos.count > 0 {
            let photo = photos.element(boundBy: photos.count - 1)
            if photo.isHittable {
                photo.tap()
                opened = true
            }
        }
        if !opened {
            // The newest message is right above the input panel.
            self.app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.78)).tap()
        }
        self.sleepSeconds(4)
        self.screenshot("view-once-opened")
        if !self.tapFirstExisting([self.app.buttons["Close"], self.app.buttons["Done"]]) {
            self.app.swipeDown()
        }
        self.sleepSeconds(5)
        self.screenshot("view-once-closed")
        let expired = self.element(containing: "expired")
        self.check("viewonce.kept", !expired.exists, expired.exists ? "the media is shown as expired: \(expired.label)" : "the media is not shown as expired")
        let viewOnceState = self.call("message", ["id": "\(viewOnceId)"])
        let mediaUnread = viewOnceState["media_unread"] as? Bool
        self.check("viewonce.ghost", mediaUnread == true, "for the peer media_unread is \(String(describing: mediaUnread)) (true: opening was not reported)")

        // Reopen.
        if photos.count > 0, photos.element(boundBy: photos.count - 1).isHittable {
            photos.element(boundBy: photos.count - 1).tap()
        } else {
            self.app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.78)).tap()
        }
        self.sleepSeconds(4)
        self.screenshot("view-once-reopened")

        self.call("finish")
    }
}
