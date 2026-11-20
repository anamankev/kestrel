import XCTest

/// Apple's automated accessibility audit (the Accessibility Inspector checks) on every Kestrel screen.
///
/// Launches with `-uitest` (debug builds only): a throwaway account in a temporary folder, unlocked, no tour.
/// Dynamic Type is excluded on purpose: Kestrel sizes its fonts itself and scales them with the system text size
/// (`ScaledRoot`, capped at 150%). The audit only recognises Apple's text styles, so it would flag every label even
/// though they do scale (checked at 150% on iPad). Split into groups so each run stays well inside test time limits;
/// every issue is printed as `AUDIT-ISSUE` the moment it's found.
final class AccessibilityAuditTests: XCTestCase {
    @MainActor func testMarketScreens() throws {
        try auditScreens(["TERMINAL", "W", "WEI", "AAPL DES", "NVDA GP", "SPY HP", "MSFT FA", "AAPL EVTS", "TSLA CN", "TOP", "KO DVD", "SECF TOYOTA", "MOST"])
    }

    @MainActor func testResearchScreens() throws {
        try auditScreens(["HMAP", "FX", "COMD", "RATES", "ECO", "ECST JAPAN", "NVDA BETA", "MSFT FACT", "NVDA EVST", "SPY BT", "COMP", "MVO", "CORR"])
    }

    @MainActor func testTradingScreens() throws {
        try auditScreens(["EQS", "ERN", "BTC OMON", "ETH OSA", "BTC DEPTH", "ETH TAS", "BTC BUY", "PORT", "BLOT", "NVDA ALRT", "PREF", "PRO", "HELP"])
    }

    @MainActor
    private func auditScreens(_ screens: [String]) throws {
        // Opt-in: about 20 minutes and a full app run, so the normal test pass skips it.
        // Run with: KESTREL_A11Y_AUDIT=1 (TEST_RUNNER_KESTREL_A11Y_AUDIT=1 on the xcodebuild command line).
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KESTREL_A11Y_AUDIT"] == "1", "set KESTREL_A11Y_AUDIT=1 to run the audit")
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        let command = app.textFields["command-line"]
        XCTAssertTrue(command.waitForExistence(timeout: 90), "terminal never appeared")
        sleep(22)   // quotes load, then the app freezes live updates (see TerminalView, -uitest)

        var found = 0
        #if os(iOS)
        let types = XCUIAccessibilityAuditType.all.subtracting(.dynamicType)   // text size has its own check
        #else
        let types = XCUIAccessibilityAuditType.all                              // macOS has no Dynamic Type audit
        #endif
        for screen in screens {
            if screen != "TERMINAL" {
                // The command line normally keeps keyboard focus; if a screen took it, click the field's right end
                // (clear of the placeholder overlay) to give it back.
                if !((command.value(forKey: "hasKeyboardFocus") as? Bool) ?? false) {
                    command.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                }
                app.typeText(screen + "\n")
                sleep(screen.contains("OMON") || screen.contains("OSA") || screen == "EQS" || screen.hasPrefix("ECST") || screen == "CORR" ? 7 : 4)
            }
            do {
                try app.performAccessibilityAudit(for: types) { issue in
                    let who = issue.element.map { "type=\($0.elementType.rawValue) label='\($0.label.prefix(50))' id='\($0.identifier)'" } ?? "-"
                    let frame = issue.element.map { "\($0.frame.integral)" } ?? "-"
                    print("AUDIT-ISSUE | \(screen) | \(issue.auditType.rawValue) | \(issue.compactDescription) | \(who) | \(frame) | \(issue.detailedDescription.prefix(160))")
                    found += 1
                    return true   // record every issue instead of failing on the first
                }
            } catch {
                print("AUDIT-ISSUE | \(screen) | error | \(error) | -")
                found += 1
            }
        }
        print("AUDIT-GROUP-END \(screens.first ?? "") issues=\(found)")
        XCTAssertEqual(found, 0, "\(found) accessibility issues (see AUDIT-ISSUE lines)")
    }
}
