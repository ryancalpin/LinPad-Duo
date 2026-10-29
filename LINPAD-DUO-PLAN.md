# LinPad Duo: build plan for Claude Code

This is the brief for turning a fork of LinPad into a Linux desktop made for the iPhone Duo and its fold poses. It lives as LINPAD-DUO-PLAN.md in the root of the forked repo. To start, tell Claude Code: "Read LINPAD-DUO-PLAN.md and start Phase 1."

## Read this first, Claude Code

The owner, Ryan, is not a developer. He builds apps with AI tools. So:

- Explain every step, choice and error in plain English. Define any technical term the first time you use it.
- Work on one phase at a time. When a phase is done, stop, summarise what changed and what Ryan should test on the phone, and wait for his go-ahead before starting the next phase.
- Make a git commit at the end of each phase with a clear message, on the branch called `duo`, so any phase can be undone.
- Don't change the Linux engine folders (`emu`, `jit`, `kernel`, `fs`, `vdso`, `gpu`, `linux`) unless a phase says so. If you think one needs changing, explain why and ask first.
- Use only public Apple APIs. If iOS doesn't allow something, say so plainly and suggest the nearest thing that works. Never use private APIs or hacks that could brick the phone or the account.
- Never store passwords, keys or tokens in the repo or in plain text.
- Keep the GPLv3 licence files (`LICENSE.md`, `LICENSE.IOS`) and credit LinPad (fspecii/LinPad) and iSH in the README.
- Every new feature gets its own on/off switch in the app's Settings, off by default if it costs battery.
- Build with Xcode 27.1 or newer and the iOS 27.1 SDK. Apps built with older SDKs get black bars on the Duo's inner screen.
- Keep the deployment target (the oldest iOS the app runs on) at 16.0. Building with the new SDK is enough; wrap every Duo-only API in an availability check (`if #available(iOS 27.1, *)`) so iPads and older iPhones keep working.
- Builds, installs and device tests happen on Ryan's Mac. A Claude Code cloud session runs on Linux and can read and edit the code but cannot build or install the iOS app.
- The phone is the test device. Add small debug overlays where they help Ryan see what the app thinks is happening.
- At the start of each phase, read the parts of the code that phase touches before changing anything, and tell Ryan if the plan below doesn't match what the code actually does.
- Much of LinPad already exists. Where a phase lists something under "Already in the code", extend that code. Never build a second copy alongside it.

## Background

### What LinPad is

LinPad runs a real Alpine Linux desktop inside one sideloaded iPad app, with no virtual machine and no jailbreak. Its layers, from the README:

- Emulator: a fork of iSH and iSH-ARM64 that translates Linux system calls to iOS, plus LinPad's own ARM64 JIT ("fast mode", switched on through StikDebug).
- ishwl (`wl-bridge/`): a Wayland compositor running inside Linux. Window pixels are shared through memory-mapped files, and input comes back through FIFOs.
- DesktopKit (`desktop/DesktopKit/`): a SwiftUI desktop shell that shows Linux windows as native windows, with tiling and workspaces.
- Bridges: PulseAudio to AVAudioEngine for sound. virtio-gpu to virglrenderer (Venus) to MoltenVK to Metal for graphics. Cameras to Linux webcam devices.
- Apps: Firefox, VS Code, Thunar, VLC, foot, Node, git and Claude Code run as Linux apps.
- Built with Swift, SwiftUI, UIKit, C, ARM64 assembly and meson. Xcode project `iSH.xcodeproj`, target `iSH-ARM64`, deployment target 16.0.
- Build guide: `release/INSTALL-DEVICE.md`. The rootfs build (`release/build-rootfs.sh`) takes about 50 minutes.
- Officially iPad only (Apple Silicon, M1 or newer). Known weak spots: slow page loads and app launches, and VS Code using lots of memory on 8GB iPads.
- Licence: GPLv3.

### What the code already has (checked against the repo)

- iPhone is already an allowed device: `TARGETED_DEVICE_FAMILY = 1,2` in `app/iOS.xcconfig`, and `app/Info.plist` has iPhone orientations. The work in Phase 1 is making the desktop fit a phone, not unlocking the device.
- Per-app scaling: ishwl reads `/etc/ishwl/app-scale` (lines like `firefox-esr 2 1`) in `wl-bridge/src/misc.c`. Whole steps 1 to 3 only. The default output scale is set with `--scale` in `wl-bridge/src/main.c`.
- Mounting folders the user picks in Files (including USB drives) into Linux at `/mnt/ipad/<name>`, remembered across launches: `DragDrop/IPadPlaces.swift` and iOSFS.
- Cameras as Linux webcams (`/dev/video0` front, `/dev/video1` back): `app/Desktop/ISHCameraBridge.swift`.
- Backups, including iCloud Drive and USB, with a schedule setting: `Core/System/Maintenance/Backup/`.
- Background keep-alive using audio or location, with an Off / Always setting: `app/Desktop/ISHBackgroundKeeper.swift` and `Core/System/Lifecycle/LifecycleCoordinator.swift`. `Info.plist` already declares the `audio` and `location` background modes.
- An extra-keys row (Esc, Tab, Ctrl, arrows) and on-screen keyboard handling: `Core/OnScreenKeyboard.swift`. Hardware keyboard detection: `Core/DesktopInput.swift` and `Linux/LinuxKeyboardLayoutMonitor.swift`.
- A performance overlay (memory use): `Core/PerformanceOverlay.swift`.
- A classic terminal UI inherited from iSH (`app/TerminalViewController.m`), used when the desktop is switched off (`desktop.enabled`).
- An in-app updater that checks **fspecii/LinPad** on GitHub: `Core/System/Updates/ReleaseFeed.swift`.
- Not there yet: external display support, game controllers, Face ID lock, thermal and Low Power Mode handling, Live Activities, App Intents and widgets, Foundation Models, Apple Pencil handling, `BGContinuedProcessingTask`.

### The iPhone Duo

- Apple's first foldable, released 23 October 2026 with iOS 27.1. Book-style fold.
- Outer screen: 5.4 inches, 1398 by 2034. Inner screen: 7.6 inches, 1878 by 2670. Both 120Hz, same 1.41 to 1 shape.
- A20 Pro chip, 12GB of memory (more than the 8GB iPads LinPad already runs on). An iPhone app may still get a smaller share of that memory than an iPad app.
- The hinge holds partway, so it can be used half folded in portrait (book) or landscape (laptop), in a tent shape, or propped up.
- USB-C port. Apple Pencil support is due later in 2026.

### Apple APIs for the Duo (iOS 27.1 SDK)

- Hinge: SwiftUI `onHingeChange(isEnabled:_:)`, UIKit `UIHingeInteraction`. Gives `hinge.angle` (180 degrees when flat) and `hinge.status` (`.closed`, `.partiallyOpen`, `.fullyOpen`, plus `.unknown` in UIKit). Apple says to use it for interactions and effects, not layout. Its update rate is set by the system. It is nil on devices without a hinge.
- Reserved regions: `GeometryProxy.reservedRegions(kind:options:)` and `UIView.reservedRegions(kind:options:)`. Kind `.division` is the fold, active only when partially open. Kind `.occlusion` covers camera areas. Use `.includeInactive` to plan for regions before they appear.
- ArrangementView: split and overlay layouts that follow the fold (`.arrangementViewStyle(.split)` / `.overlay`). UIKit: `UIArrangementViewController`.
- Vertical toolbars and tab bars: `toolbarVerticalBehavior`, `axisBehavior`, `toolbarVerticalEdge`.
- Direction-aware cameras: a virtual front camera that picks whichever physical camera faces the user, `.builtInOuterUltraWideCamera`, `.builtInInnerUltraWideCamera`, `AVCaptureDeviceDirectionCoordinator`.
- Camera capture accessory: `CameraCaptureAccessory` / `UISceneAccessory.cameraCapture` to show content on the outer screen while capturing from the inner one.
- Check the real SDK headers before relying on any exact name above. These come from early write-ups, not Apple's docs.

### Limits to know up front

- iPhone apps cannot talk to arbitrary USB devices. DriverKit is Mac and iPad only, and Apple's engineers have said general USB access isn't possible on iPhone, even through MFi. USB support here means bridging device types iOS already handles.
- iOS can pause or close any app in the background. Phase 11 makes this as rare and as harmless as possible, but it cannot be ruled out.
- Fast mode (JIT) is a real unknown. `release/INSTALL-DEVICE.md` says the JIT "has not run end to end on a TXM device yet", and the Duo's chip will have TXM (a newer Apple code-signing protection). TrollStore does not work on current iOS versions, so StikDebug is the only route. Plan for the app to run in the slower compatibility mode at first.
- Signing: apps installed with a free Apple account expire after 7 days and can't use some features. A paid Apple Developer account ($99 a year) is needed for the extra-memory entitlement (`increased-memory-limit`, which the build lacks today, see `release/CHECKLIST.md`) and is the safe choice for widgets and Live Activities, which need an extra signed app extension.
- Unconfirmed: whether USB webcams work on the Duo.

## Before Phase 1 (Ryan does these)

- [x] Fork fspecii/LinPad on GitHub (done: `ryancalpin/linpad-duo`).
- [ ] Clone the fork to the Mac and switch to the `duo` branch (`git checkout duo`).
- [ ] Check which Apple account will sign the app: free or paid Developer Program. Tell Claude Code which.
- [ ] Install Xcode 27.1 or newer, plus the Homebrew tools from `release/INSTALL-DEVICE.md`.
- [ ] Open Claude Code in the repo folder on the Mac and say: "Read LINPAD-DUO-PLAN.md and start Phase 1."

## Progress

All twelve phases were written in one go on 29 October 2026, without a Mac to build on. Each
is its own commit on `duo`. Next: build on the Mac and test each phase on the phone with
DUO-SETUP.md section 6, fixing build errors first.


- [x] Phase 1: Run on the Duo (code written; not yet built or tested on the phone)
- [x] Phase 2: Pose detection (code written; not yet built or tested on the phone)
- [x] Phase 3: Automatic scaling per screen (code written; not yet built or tested on the phone)
- [x] Phase 4: Laptop pose keyboard and trackpad (code written; not yet built or tested on the phone)
- [x] Phase 5: Closing to the outer screen (code written; not yet built or tested on the phone)
- [x] Phase 6: Book pose with two workspaces (code written; not yet built or tested on the phone)
- [x] Phase 7: Tent status board (code written; not yet built or tested on the phone)
- [x] Phase 8: USB devices (code written; not yet built or tested on the phone)
- [x] Phase 9: External monitor (code written; not yet built or tested on the phone)
- [x] Phase 10: iPhone features (code written; not yet built or tested on the phone)
- [x] Phase 11: Safety and polish (code written; not yet built or tested on the phone)
- [x] Phase 12: Staying alive in the background (code written; not yet built or tested on the phone)

## Phase 1: Run on the Duo

Goal: the stock LinPad desktop opens and works on the iPhone Duo.

Already in the code: iPhone is an allowed device, and the iPhone orientations are set. See "What the code already has".

- Read `README.md`, `release/INSTALL-DEVICE.md` and `release/CHECKLIST.md`.
- Find what still assumes an iPad: idiom checks (`app/TerminalViewController.m` has several), iPad-sized layouts in DesktopKit (for example the onboarding's `width < 800` checks), fixed sizes, and "iPad" wording in the UI. Make them work on the phone's screens.
- Build with the iOS 27.1 SDK so the inner screen isn't letterboxed. Keep the deployment target at 16.0.
- Point the in-app updater (`ReleaseFeed.swift`) at `ryancalpin/linpad-duo`, or turn it off for this fork, so the app never installs stock LinPad updates over the fork's changes.
- Add the `increased-memory-limit` entitlement if Ryan's account allows it. If not, explain what that means for memory.
- Make sure closing the phone doesn't crash or wreck the layout, even before Phase 5 makes the outer screen nice.
- Don't change the engine folders.
- Walk Ryan through building the rootfs, embedding it and installing to the phone, step by step.
- Try fast mode (JIT) through StikDebug, following section 3b of `release/INSTALL-DEVICE.md`. Explain the result. If it doesn't work, Phase 1 still counts as done in compatibility mode.

Done when: LinPad installs on the Duo, the desktop fills the inner screen, Firefox and the terminal open, touch input works, and closing the phone doesn't crash the app.

## Phase 2: Pose detection

Goal: one shared service that knows how the phone is folded.

- Add a Swift service, `PoseMonitor`, that the rest of the app can observe.
- Track `hinge.status`, `hinge.angle` and device orientation, and turn them into named poses: `closed` (outer screen), `flat`, `book` (portrait, part open), `laptop` (landscape, part open) and `tent` (propped up on the outer screen).
- Smooth out jitter so poses don't flicker at the boundaries.
- Add a debug overlay, switched on in Settings, that shows the current pose and angle. Put it alongside the existing performance overlay.
- Do nothing on devices without a hinge, so iPads keep working as before.

Done when: folding the phone through every pose shows the right name in the overlay, with no flicker.

## Phase 3: Automatic scaling per screen

Goal: Linux apps are the right size wherever the desktop appears.

Already in the code: ishwl's per-app scale file `/etc/ishwl/app-scale` and its `--scale` option. Both support whole steps 1 to 3 only.

- Give each place the desktop can appear its own scaling profile: outer screen, inner screen flat, each half in book pose, the top half in laptop pose, and an external monitor.
- For each profile, set the Linux side to match: the Wayland output scale in ishwl, GTK and Qt scale settings, font DPI and cursor size, so apps redraw sharp rather than stretched. Fractional scaling (for example 1.5x) would be new ishwl work: say how big it is before doing it, and fall back to whole steps plus font DPI if it's too much.
- Build per-app overrides (for example VS Code smaller, Firefox bigger) on the existing `app-scale` file rather than a new system. Remember them.
- Make touch targets bigger when no keyboard or trackpad is connected.
- Use the iPhone's own text size setting as the starting point.
- Let Ryan adjust each profile with a slider.
- Switch smoothly when folding, unfolding or plugging in a monitor, without restarting apps. If some apps can't resize while running, say which and why.

Done when: the same app looks comfortable on the outer screen and the inner screen, and changes size on its own when the pose changes.

## Phase 4: Laptop pose keyboard and trackpad

Goal: a pocket laptop.

Already in the code: the extra-keys row in `Core/OnScreenKeyboard.swift` and hardware keyboard detection.

- In laptop pose, find the fold with the `.division` reserved region and split the inner screen there.
- Top half: the Linux desktop.
- Bottom half: a touch keyboard with Ctrl, Alt, Esc, Tab, function and arrow keys (reuse the existing extra keys), plus a trackpad strip that sends pointer moves, clicks, right clicks and two-finger scrolling into Linux through the existing input path.
- If a hardware keyboard is connected, show only the trackpad. If a mouse or trackpad is connected too, hide both.
- Leaving laptop pose goes back to the normal layout with nothing lost.

Done when: Ryan can write and run code in the terminal in laptop pose using only the bottom half of the screen.

## Phase 5: Closing to the outer screen

Goal: closing the phone never interrupts Linux.

- When the phone closes and moves to the outer screen, don't squeeze the full desktop onto it.
- Show a compact view sized for the outer screen: a terminal and a simple list of open Linux windows to pick from, keeping the same session. Check whether the existing classic terminal UI (`TerminalViewController`) can be reused while the desktop is running. It currently only runs when the desktop is off, so explain what reusing it would take.
- Reopening restores the desktop exactly as it was.
- Linux keeps running through the switch.

Done when: a command started on the inner screen keeps running when the phone closes, its output can be checked on the outer screen, and reopening shows the desktop untouched.

## Phase 6: Book pose with two workspaces

Goal: two apps side by side, one on each half.

- In book pose, treat each half of the inner screen as its own workspace, divided at the `.division` reserved region. Build on the existing workspaces and tiling in `Core/WindowManager.swift`.
- Let Ryan drag a window to either side. Never let a window sit across the fold.
- Add a quick gesture to swap the two sides.
- When fully flat, go back to the normal tiling desktop.

Done when: VS Code on one half and Firefox on the other each fill their half, and swapping works.

## Phase 7: Tent status board

Goal: something useful when the phone is propped up on the outer screen. Has its own Settings switch.

- When in tent pose, show a clock, CPU and memory use (reuse `Core/PanelSystemMonitor.swift`), and any long jobs like builds or Claude Code sessions.

Done when: tent pose shows the board, it updates live, and it can be switched off.

## Phase 8: USB devices

Goal: plug things into the USB-C port and use them in Linux, using only public iOS APIs.

Already in the code: mounting a folder picked in Files into Linux at `/mnt/ipad/<name>`, remembered across launches (`DragDrop/IPadPlaces.swift`).

- Storage: check the existing folder mount works with a USB drive on the Duo. Add a clear "Connect drive" button and a safe eject, and handle the drive being unplugged.
- Game controllers: map GameController devices to a Linux joystick device. This needs a new device in the engine (`fs/`), so explain and ask first.
- Audio: check the existing audio bridge picks up USB headsets, mics and audio interfaces.
- Keyboards, mice and Ethernet adapters already work through iOS. Confirm they still do.
- Explain anything iOS won't allow (serial cables, Arduinos, printers that need drivers) instead of working around it.

Done when: a USB stick shows up in Linux, ejects safely, and a controller works in a Linux game.

## Phase 9: External monitor

Goal: plug in a USB-C display and use LinPad like a desktop computer. This is new: the code has no external display support yet.

- When a USB-C display is connected, show the full Linux desktop on it (using the Phase 3 monitor profile).
- Turn the phone into a keyboard and trackpad (reuse Phase 4), unless a hardware keyboard and mouse are connected.
- Unplugging the monitor brings the desktop back to the phone with nothing lost.

Done when: a monitor shows the desktop at a comfortable size, the phone works as its trackpad, and unplugging is safe.

## Phase 10: iPhone features

Each with its own Settings switch.

- Live Activities: when a long Linux job runs, show its progress in the Dynamic Island and on the Lock Screen, with a tap to jump back. Add a Linux command, `notify-phone`, that any script can call to start, update or finish one. This needs a new widget extension target and the existing App Group (`app/AppGroup.m`). Check signing works with Ryan's account first.
- Shortcuts and widgets: App Intents for "open LinPad in a workspace", "run a script" and "start my dev setup", usable from Siri, the Action button and a Home Screen widget.
- On-device AI: a Linux command, `ask`, that sends a question to Apple's Foundation Models framework on the phone and prints the answer in the terminal, with no internet needed. Needs Apple Intelligence switched on.
- Duo cameras: the cameras already reach Linux as webcams (`ISHCameraBridge.swift`). Check they work on the Duo, and use the direction-aware front camera so `/dev/video0` is always the camera facing Ryan.

Done when: a long build shows progress in the Dynamic Island, a Shortcut runs a script, and `ask` answers a question offline.

## Phase 11: Safety and polish

Each with its own Settings switch.

- Backups: already in the code (`Core/System/Maintenance/Backup/`). Check it works on the Duo, that it covers `/root` and `/home`, and that restore works. Only add what's missing.
- Battery and heat guard: watch the phone's thermal state and Low Power Mode, slow or pause heavy Linux processes when it's hot or low, and show what's using the most power.
- Faster launches: find why apps open slowly and keep the most-used ones ready in the background where memory allows.
- Security: Face ID or passcode to open the app. LinPad doesn't ship a remote-login (SSH) server, so if one gets installed later, show a clear warning. No passwords stored in plain text.
- Getting fixes from LinPad: the phone can't rebuild the app, so this can't be an in-app button. Instead, write `DUO-UPDATING.md`: plain-English steps for Claude Code on the Mac to merge changes from fspecii/LinPad into the `duo` branch and explain any clashes with this fork's changes. Do one real merge to test it.
- Apple Pencil: get ready for Pencil on the Duo, so it can draw and write in Linux apps once Apple switches it on.

Done when: a backup restores cleanly, the app locks with Face ID, and one merge from the original project has been done with the written steps.

## Phase 12: Staying alive in the background

Goal: survive in the background as well as iOS allows, and be honest about the limits.

Already in the code: the audio and location keep-alive (`ISHBackgroundKeeper.swift`, Off / Always), and the lifecycle handling in `LifecycleCoordinator.swift`.

- Early check: in Phase 1 or 2, test how the existing keep-alive behaves on the Duo, because Phases 5 and 7 depend on Linux staying awake. Report the result before the rest of this phase.
- Use `BGContinuedProcessingTask` so a job Ryan starts with a tap keeps running after switching apps, reporting real progress. Tie it to the Phase 10 Live Activity. Note that developers have reported these tasks pausing when the phone locks.
- Add a "while a job runs" option to the existing keep-alive: hold it only while a job is running, with a battery warning, and switch off automatically when the job ends.
- Make restore after iOS closes the app bulletproof: save session state often, reopen everything where it was, and say if a job was cut off.
- Add "Run on my PC": send a long command over SSH to Ryan's always-on Linux computer inside tmux, and show its output in LinPad on return. Ryan enters the connection details in Settings, and they are stored in the Keychain.

Done when: a 20-minute job started in LinPad finishes while Ryan uses other apps, and a job sent to the PC can be checked from the phone.

## Ideas for later

- Hinge dial: while holding a chosen on-screen button, moving the hinge a little scrolls, zooms or changes volume. (Moved here because Apple says hinge readings are for effects only and sets their update rate, so it may feel unreliable.)
- Close slowly to save: closing the phone over about two seconds saves open work and pauses heavy Linux processes. (Moved here for the same reason, and the existing lifecycle handling already pauses on background.)
- Use the Duo's two cameras for Linux video calls with the camera that faces the user.
- Hand off a Linux window to a Mac or iPad running LinPad.
- A "focus" pose: half closed, the top half shows one app full screen and the bottom half shows notes.
