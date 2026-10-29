# LinPad Duo: building it and putting it on the phone

Plain-English steps for Ryan's Mac. Every command goes in the Terminal app, run from the
`LinPad-Duo` folder (the clone of this repo). Lines starting with `#` are notes, not commands.

## 0. Once: what you need

- A Mac with **Xcode 27.1 or newer** (from the App Store). Open it once and let it install its extras.
- The **Homebrew** tools LinPad's build uses:

  ```sh
  brew install meson ninja llvm lld libimobiledevice ideviceinstaller
  ```

- **Your Apple account in Xcode**: Xcode › Settings › Accounts › add your Apple ID.
  - A **free** account works, but the app stops opening after 7 days, and you then have to build
    and install it again. It also can't use the "more memory" option (below).
  - A **paid** Apple Developer account ($99 a year) lasts a year and allows the extra memory.
- Your **Team ID**: Xcode › Settings › Accounts › your account › the team's ID (10 letters and
  numbers). The commands below call it `YOUR_TEAM_ID`.
- On the phone: **Developer Mode** on (Settings › Privacy & Security › Developer Mode), then restart.

## 1. Get the code

```sh
git clone https://github.com/ryancalpin/LinPad-Duo.git
cd LinPad-Duo
git checkout duo
git submodule update --init --recursive
```

## 2. Get the Linux system (no 50-minute build needed)

The original LinPad project publishes its Linux system. Download it and its version stamp:

```sh
mkdir -p release/out
curl -L -o release/out/linpad-rootfs.tar.gz \
  https://github.com/fspecii/LinPad/releases/download/v1.5.0/linpad-rootfs-1.5.0.tar.gz
echo 202610031701 > release/out/linpad-rootfs.version
```

That's about 620 MB. (Building it yourself is `release/build-rootfs.sh`; it needs the `ish`
command-line tool built first and takes about an hour, so only do it if you change the Linux side.)

## 3. Build the app

```sh
export PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH
xcodebuild -skipMacroValidation -project iSH.xcodeproj -scheme iSH-ARM64 \
  -configuration Release -destination generic/platform=iOS -allowProvisioningUpdates \
  SYMROOT=$PWD/build-ios-release DEVELOPMENT_TEAM=YOUR_TEAM_ID ISH_JIT_BUILD=enabled build
release/embed-rootfs.sh --device "build-ios-release/Release-iphoneos/iSH ARM64.app" \
  release/out/linpad-rootfs.tar.gz
```

- The first build takes a while (it builds the Linux engine too).
- **If it fails**, copy the last 30 lines of the output to Claude Code and ask it to fix the build.
  This code was written without a Mac, so the first build is expected to need a few fixes.
- **The Duo hinge code** is the part most likely to fail if Apple renames anything. It lives in
  `desktop/DesktopKit/Sources/DesktopKit/Core/Duo/DuoHinge.swift`. To build without it while
  that gets fixed, delete the line `.define("LINPAD_HINGE_API")` in
  `desktop/DesktopKit/Package.swift`. The app then guesses the pose from the screen size alone
  (closed and open work; book, laptop and tent don't).
- **Paid account only, for more memory:** in `app/App.xcconfig`, change
  `app/iSH.entitlements` to `app/iSH-MoreMemory.entitlements`, then build again.

## 4. Install on the phone

Plug the phone into the Mac, unlock it and tap **Trust**. Then:

```sh
idevice_id -l          # prints the phone's ID; copy it
ideviceinstaller -u PHONE_ID install "build-ios-release/Release-iphoneos/iSH ARM64.app"
```

- If the phone says "Untrusted Developer": Settings › General › VPN & Device Management › your
  account › Trust.
- The app is called **LinPad Duo** and has its own bundle ID (`com.ryancalpin.linpadduo.arm64`),
  so it sits next to stock LinPad if you have that too.
- The first launch unpacks Linux, which takes a few minutes. Leave the app open.

## 5. Fast mode (optional, makes Linux several times faster)

Fast mode needs **StikDebug** and **LocalDevVPN** from the App Store, plus a "pairing file"
made on the Mac. Follow `release/INSTALL-DEVICE.md` section 3b, reading "iPhone" for "iPad".

Honest expectation: fast mode has never been tested on a phone with Apple's newer code
protection (TXM), and the Duo has it. If StikDebug can't switch it on, LinPad starts in
"Compatibility mode" after about 20 seconds. Everything still works, just slower.
Settings › Fast Mode › Status says which mode is running.

## 6. What to test, phase by phase

Tick these off on the phone. If something's wrong, tell Claude Code what you did and what you saw.

### Phase 1: runs on the Duo
- [ ] LinPad Duo installs and opens.
- [ ] Unfolded, the desktop fills the inner screen with no black bars.
- [ ] Firefox and the terminal open; tapping and typing work.
- [ ] Close the phone: nothing crashes; the desktop shows on the outer screen.
- [ ] Open it again: windows are back where they were.
- [ ] Settings › Fast Mode › Status: note whether it says fast mode or Compatibility mode.
- [ ] Background check: Settings › Background › "Always". Start `sleep 600; echo done` in a
      terminal, switch to another app for 10 minutes, come back. Did it print `done`?

### Phase 2: pose detection
- [ ] Settings › iPhone Duo › "Show pose and hinge angle" on. A label appears at the top.
- [ ] Fold through each pose and check the name: **Closed** (outer screen), **Flat**, **Book**
      (half-open, upright), **Laptop** (half-open, sideways), **Tent** (standing on its edges,
      outer screen showing).
- [ ] Hold the hinge near the point where book becomes flat: the name doesn't flicker.
- [ ] If it always says "No hinge", the hinge code was switched off for the build (step 3).

### Phase 3: sizes per screen
- [ ] Open Firefox or VS Code on the inner screen, then close the phone: the app gets a bit
      smaller on the outer screen and fits more in. Open it again: back to normal size.
- [ ] Settings › Screen Sizes: move a slider for the screen you're on ("(now)" marks it).
      Open Linux apps resize straight away, without restarting.
- [ ] Under "Per app", make VS Code 80% and Firefox 120%. Each keeps its own size.
- [ ] iPhone Settings › Display & Brightness › Text Size, make it bigger: Linux apps grow too
      (turn off "Follow the iPhone's text size" to stop that).
- [ ] Menus and pop-ups inside a resized app appear in the right place and at the same size.
- Note: every Linux app resizes live, because LinPad tells the app its new size and it redraws.
  If one doesn't (old X11 apps can be stubborn), tell Claude Code which.

### Phase 4: laptop pose
- [ ] Half-open the phone sideways like a laptop. The desktop moves to the top half; the
      bottom half shows a keyboard and a trackpad.
- [ ] Open foot (Terminal), type `echo hello` with the bottom keyboard and press return.
- [ ] `ctrl` then `c` stops a running command (try `sleep 100`). Tap `ctrl` twice to lock it.
- [ ] `fn` swaps the number row for F1–F12.
- [ ] Trackpad: one finger moves the pointer, tap clicks, two-finger tap right-clicks, two
      fingers scroll, tap then drag selects text.
- [ ] Connect a Bluetooth keyboard: only the trackpad stays. Add a mouse: both go away.
- [ ] Open the phone flat: back to the normal desktop, windows where they were.
- Limits: the trackpad clicks inside Linux apps. On LinPad's own panels, title bars and
  built-in apps a click only brings that window forward (iOS doesn't let an app fake a
  touch), so touch those on the top half directly. The built-in Terminal app may still
  bring up the iPhone's own keyboard; foot (the Linux terminal) doesn't.

### Phase 5: closing to the outer screen
- [ ] With two or three windows open, start `sleep 30; echo finished` in foot, then close the phone.
- [ ] On the outer screen the focused window fills it. The button in the bottom corner lists
      the windows; tap one to switch. "New Terminal" and "Apps" are there too.
- [ ] After 30 seconds the terminal shows `finished`: Linux kept running.
- [ ] Open the phone: every window is back where it was, same size.

### Phase 6: book pose
- [ ] Open VS Code and Firefox, then half-open the phone like a book. One app fills each half.
- [ ] Drag a window by its title bar to the other half: it snaps to that side. Nothing sits
      across the fold.
- [ ] The round ⇄ button at the bottom of the fold swaps the two sides.
- [ ] Open a third app: it opens on the side the focused window isn't on.
- [ ] Open the phone flat: back to the normal tiling desktop.

### Phase 7: tent status board
- [ ] In foot: `notify-phone run "Test job" -- sleep 120`
- [ ] Stand the phone up like a tent. The outer screen shows the time, CPU, memory and
      "Test job" with a running timer.
- [ ] Start Claude Code or a build (`make`, `npm install`): after 30 seconds it shows up too.
- [ ] Tap the board: the desktop shows. Close and re-tent the phone: the board is back.
- [ ] `notify-phone` commands: `start`, `update`, `done`, `fail`, `run` (type `notify-phone`
      on its own to see how to use them).

### Phase 8: USB devices
- [ ] Plug in a USB stick. Settings › USB › Connect Drive…, pick the stick under Locations.
- [ ] In foot: `ls /mnt/usb` (or `ls ~/USB`) shows it. Copy a file onto it.
- [ ] Settings › USB › Eject, then unplug. Plug it into a computer: the file is there.
- [ ] Connect a game controller (Bluetooth or USB). Settings › USB lists it. In a Linux game
      or app, the D-pad moves and A presses Space.
- [ ] Plug in USB headphones or a USB mic: Linux sound and recording use them (iOS switches
      on its own).
- [ ] A USB keyboard, mouse and Ethernet adapter still work.
- Not possible on iPhone: serial cables, Arduinos and printers that need drivers. iOS
  doesn't let apps reach USB devices directly. A real Linux joystick device would need the
  emulator's kernel changed; controllers type keys instead.
