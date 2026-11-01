# Mac acceptance checks

These checks require a Mac. They have not been run in the Linux implementation workspace. Linux test results are not evidence that SwiftUI views render correctly or that a signed `.app` launches.

## Build and launch

- Run `swift test`, then `Scripts/compile_and_run.sh --test` with Swift 6 / Xcode 16 or later.
- Verify the app stays open in the menu bar, shows no Dock icon, and opens a 360-point popover when clicked. Check positioning with the menu bar at both sides of a notched screen, and on a second display.
- Check standard, compact, and icon-only labels. Number changes from zero through billions must not move neighboring menu bar items.
- Verify Settings opens by mouse and `⌘,`, pause/resume works, and Quit exits cleanly. Reopen and verify saved source folders, filter, and density.

## Measurement and recovery

- Test installed Claude Code and Codex clients separately and concurrently, including nested agents and resumed/forked sessions. Compare deduplicated log counters against the day's displayed totals; do not compare consumption to subscription quota percentages.
- Start with existing large logs: today's totals should load while the live graph remains empty. Append a new response and observe the 10-second rate, then zero after the window expires.
- Pause during a response and resume: totals catch up, live throughput does not spike. Repeat across sleep/wake and app restart.
- Use missing, inaccessible, malformed, and corrected source folders. Verify the source status identifies the issue and recovers without relaunch.
- Verify a partially written final JSON line appears only after its terminating newline, and moving a session into the archive does not duplicate usage.
- Clear history and restart. Cleared totals must remain cleared; subsequent usage must count.
- Change the system day/time zone and verify Today moves to the current local day.

## Visual and accessibility review

- Capture actual popover screenshots in light and dark appearance, including reporting, waiting, paused, a single unavailable source, unsupported logs, and a long error. Save them under `.impeccable/review/` for design review; do not substitute Xcode preview screenshots for live-state validation.
- Check the 60-second graph, cyan solid Claude trace, amber dashed Codex trace, explicit labels, and cache footnote. Check long paths and error strings for wrapping and clipping in Settings.
- Verify keyboard focus, segmented filter navigation, toggles, menus, file chooser, and clear-history confirmation. Run VoiceOver and confirm labels distinguish unavailable values from zero.
- Enable Reduce Motion and Reduce Transparency. Number/graph animations should stop and the popover should use an opaque native background.
- Measure text and trace contrast in both appearances. Check larger accessibility text settings for clipping; the body must remain scrollable.

## Efficiency and distribution

- With Instruments or Activity Monitor, sample idle, an active session, and initial import of a large log corpus. Confirm no busy loop, stable memory, responsive popover controls, and no repeated full-file parsing or writes to an unchanged SQLite database.
- Enable launch at login from the installed bundle, approve Login Items if requested, log out/in, and verify launch. Disable it and repeat. Check the toggle after changing Login Items externally.
- Build universal output, inspect it with `lipo -archs`, and verify signing with `codesign --verify --deep --strict`.
- For distribution, run the notarization script with real signing credentials, validate the stapled ticket, then test a downloaded ZIP under Gatekeeper on a clean Mac. Development ad-hoc signing is not notarization.
