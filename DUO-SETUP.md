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

**Paid account (what Ryan uses):** one command builds a signed app with the hinge code, the
GPU libraries and the Linux system inside. It signs with the App Store Connect API key on this
Mac, so no Apple ID is needed in Xcode:

```sh
ASC_KEY_ID=XC34FF49ML ASC_ISSUER_ID=fd826a8b-f5db-43d1-bac1-5ef15fe201e7 \
  ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XC34FF49ML.p8 APPLE_TEAM_ID=X6PM238Q98 \
  release/duo-build-ipa.sh
```

- The first build takes about 20 minutes; later ones reuse most of the work.
- The app keeps its Linux files in the app group `group.com.ryancalpin.linpadduo.arm64`. It is
  registered and assigned to the app ID already; Xcode can't do that by itself with an API key
  (`asc web app-groups create` / `assign` does, after `asc web auth login`).
- It also needs `brew install libarchive coreutils pkgconf` and `pip3 install --user mako` for
  the GPU libraries.

**Free account:**

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
- **Paid account only, for more memory:** add `LINPAD_ENTITLEMENTS=app/iSH-MoreMemory.entitlements`
  to the `xcodebuild` line (the one-command build above does this for you).

## 4. Install on the phone

**After a signed build (paid account):**

```sh
release/duo-install.sh
```

It finds the iPhone Duo, installs the new build and opens it. The first time, plug the phone in
(unlock it, tap **Trust**). After that it works **over Wi-Fi**: the phone just has to be
unlocked and on the same network as the Mac. No cable needed for later changes.

**Free account:** plug the phone into the Mac, unlock it and tap **Trust**. Then:

```sh
idevice_id -l          # prints the phone's ID; copy it
ideviceinstaller -u PHONE_ID install "build-ios-release/Release-iphoneos/iSH ARM64.app"
```

- If the phone says "Untrusted Developer": Settings › General › VPN & Device Management › your
  account › Trust.
- The app is called **LinPad Duo** and has its own bundle ID (`com.ryancalpin.linpadduo.arm64`),
  so it sits next to stock LinPad if you have that too.
- The first launch unpacks Linux, which takes a few minutes. Leave the app open.

## 4b. Building in the cloud instead (for an Intel Mac): GitHub

Xcode 27 doesn't run on Intel Macs, so GitHub builds the app on its own Macs, free for this
public repository. Every push to the `duo` branch starts a build (about 20 minutes); you can
also start one by hand: the repository on github.com › **Actions** › **LinPad Duo IPA** ›
**Run workflow** › branch `duo`.

1. On github.com, open the repository › **Actions** › the newest green **LinPad Duo IPA** run.
2. Under **Artifacts**, download **LinPad-Duo-ipa** (you must be signed in to GitHub). It's a
   zip of about 600 MB; double-click it to get **LinPad-Duo.ipa**.
3. Install it from your Intel Mac with **Sideloadly** (free, works on Intel): plug the phone
   in, drag the IPA onto Sideloadly, type your Apple ID, Start. It signs the app with your
   Apple ID. AltStore (AltServer on the Mac) or SideStore work too.
4. On the phone: Developer Mode on, and trust your Apple ID in Settings › General › VPN &
   Device Management.

What's different about a cloud build:
- With a free Apple ID the app stops opening after 7 days; Sideloadly or SideStore can
  refresh it. The widget extension (5b) isn't in it, so no Dynamic Island jobs or widget.
- GitHub's Macs have Xcode 26.6 right now, not 27.1. The build notices and leaves out the
  hinge code, so **closed and open work, but book, laptop and tent poses don't** yet. Apple
  also says apps built with Xcode 26 don't draw under the status bar and camera on the Duo,
  so expect a strip at the top. Both go away once GitHub adds Xcode 27.1; the build picks
  the newest Xcode by itself.
- `codemagic.yaml` does the same on Codemagic, if you ever prefer it.

## 4c. Signed builds that install from Safari (paid Apple Developer account)

Once these are set up, every cloud build is signed for your phone. You open
**https://ryancalpin.github.io/LinPad-Duo/** in Safari on the phone and tap Install: no Mac,
no cable, no Sideloadly, and the app keeps working for a year.

**A. Register the phone** (once per phone)
1. Plug the phone into the Mac and select it in a Finder window's sidebar.
2. Under its name, click the grey line of text until it shows **UDID**. Right-click it ›
   **Copy UDID**.
3. developer.apple.com › Account › **Certificates, Identifiers & Profiles** › **Devices** › **+**.
   Name it "iPhone Duo", paste the UDID, Continue, Register.

**B. Find your Team ID**: developer.apple.com › Account › **Membership details** › Team ID
(10 letters and numbers).

**C. Make an API key** (lets the cloud build sign apps for you)
1. appstoreconnect.apple.com › **Users and Access** › **Integrations** › **App Store Connect API**.
   If it asks, click **Request Access** first.
2. **Team Keys** › **+**. Name: `LinPad Duo builds`. Access: **Admin** (needed so it can make
   signing certificates). Generate.
3. Note the **Issuer ID** (above the list) and the key's **Key ID**. Click **Download API Key**:
   you get a `.p8` file, and Apple only lets you download it once.

**D. Give them to GitHub** (stored encrypted; never in the code)
github.com/ryancalpin/LinPad-Duo › **Settings** › **Secrets and variables** › **Actions** ›
**New repository secret**, four times:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `ASC_KEY_P8` | open the `.p8` file in TextEdit and paste all of it, including the BEGIN and END lines |
| `APPLE_TEAM_ID` | your Team ID |

**E. Two GitHub settings**
1. **Settings › Pages** › Build and deployment › Source: **GitHub Actions**.
2. **Settings › General** › Default branch: switch it to **duo** (the install page can only be
   published from the default branch; `main` is just the untouched copy of stock LinPad).

**F. Build**: **Actions** › **LinPad Duo IPA** › **Run workflow** (or ask Claude Code to start
it). When it's green, open the install page on the phone in Safari.

Good to know:
- A phone registered after a build needs a new build before it can install.
- The key can manage your account's signing certificates, so treat it like a password: it
  only works from workflows in your repository, don't give anyone else write access to the
  repository, and you can revoke it in App Store Connect at any time.
- Builds are signed for development, which keeps fast mode possible (StikDebug needs it).
  With a paid account they also get the extra-memory entitlement.

## 5. Fast mode (optional, makes Linux several times faster)

Fast mode needs **StikDebug** and **LocalDevVPN** from the App Store, plus a "pairing file"
made on the Mac. Follow `release/INSTALL-DEVICE.md` section 3b, reading "iPhone" for "iPad".

Honest expectation: fast mode has never been tested on a phone with Apple's newer code
protection (TXM), and the Duo has it. If StikDebug can't switch it on, LinPad starts in
"Compatibility mode" after about 20 seconds. Everything still works, just slower.
Settings › Fast Mode › Status says which mode is running.

## 5b. Adding the widget extension (for Live Activities and the Home Screen widget)

Once, in Xcode. The app works without it; only the Dynamic Island, Lock Screen jobs and the
Home Screen widget need it. Apple only lets Xcode itself create this kind of target safely,
which is why it's a manual step.

1. Open `iSH.xcodeproj` in Xcode.
2. **File › New › Target…** › iOS › **Widget Extension** › Next.
3. Product Name: `LinPadDuoWidgets`. Tick **Include Live Activity**. Untick "Include Configuration
   App Intent" if it's there. Finish. When asked "Activate scheme?", choose **Cancel**.
4. In the left sidebar, open the new **LinPadDuoWidgets** group. Select every `.swift` file
   Xcode made in it, right-click › **Delete** › **Move to Trash**. Keep `Info.plist` and `Assets`.
5. Right-click the **LinPadDuoWidgets** group › **Add Files to "iSH"…** › pick
   `duo-widgets/LinPadDuoWidgets.swift`. Under "Add to targets", tick only **LinPadDuoWidgets**.
6. In the sidebar, select `app/Desktop/LinuxJobAttributes.swift`. In the right-hand panel
   (File inspector) under **Target Membership**, tick **LinPadDuoWidgets** as well
   (iSH-ARM64 stays ticked).
7. Click the project at the top of the sidebar › **LinPadDuoWidgets** target › **General** ›
   Minimum Deployments: **16.2**. Then **Signing & Capabilities**: pick your team.
8. Build again with the command in step 3. The widget extension is built and put inside the app.

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
      bottom half becomes a MacBook-style keyboard.
- [ ] Open foot (Terminal), type `echo hello` and press return.
- [ ] `control` then `C` stops a running command (try `sleep 100`). Tap a modifier twice to
      lock it (a green dot shows); a third tap releases it. `caps lock` lights up too.
- [ ] Top row: brightness, overview, search (the app launcher), dictation, Do Not Disturb,
      media keys and volume. The **F1–F12** switch (or `fn` for one key) makes them F-keys.
- [ ] The big blue mic (hold to talk, the default): hold it and speak, let go, and the words
      are typed into the focused app. Slide up while holding to lock it on (a lock shows; tap
      to finish). Slide left to cancel without typing.
- [ ] Settings › Laptop Keyboard › Microphone button › "Tap to start and stop" switches to
      tap-on, tap-off instead.
- [ ] Customize: Settings › Laptop Keyboard. Change bottom-bar button 3 on the left to
      Firefox, and F1 to "Lock the desktop". The keyboard changes straight away. Touch and
      hold any bottom-bar button on the keyboard to jump to these settings. "Reset Keyboard"
      puts everything back.
- [ ] The hand button (bottom left) swaps the keyboard for a trackpad: one finger moves the
      pointer, tap clicks, two-finger tap right-clicks, two fingers scroll, tap then drag
      selects. Clicks work in Linux apps and on LinPad's own buttons, panels and title bars.
- [ ] Bottom bar: Terminal and Files open those apps; ↩ is Return; ⌘ opens the Command Menu.
- [ ] Connect a Bluetooth keyboard: the trackpad takes the keyboard's place. Add a mouse: the
      deck goes away and the desktop fills the screen.
- [ ] Open the phone flat: back to the normal desktop, windows where they were.

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

### Phase 9: monitor
- [ ] Plug a USB-C monitor (or a USB-C hub with HDMI) into the phone. The whole desktop moves
      to the monitor; the phone shows "Showing on the monitor" with a trackpad and keyboard.
- [ ] Move the pointer with the trackpad and click into foot; type with the phone's keyboard.
- [ ] With a Bluetooth keyboard connected, typing goes to the monitor's desktop.
- [ ] Settings › Screen Sizes › Monitor changes how big Linux apps are on it.
- [ ] "Show on iPhone" brings the desktop back; unplugging the monitor does too. Nothing closes.
- [ ] Settings › iPhone Duo › "Use a USB-C monitor" off: the monitor mirrors the phone instead.

### Phase 10: iPhone features
- [ ] (Needs step 5b.) In foot: `notify-phone run "Test build" -- sleep 60`. The Dynamic Island
      shows "Test build" with a timer; lock the phone and it's on the Lock Screen too. When it
      finishes it shows Done. Tap it to come back to LinPad.
- [ ] Progress: `id=$(notify-phone start "Copying")`, then `notify-phone update $id 50`,
      then `notify-phone done $id`.
- [ ] Shortcuts app › new shortcut › search "LinPad": "Run Script in LinPad" with `echo hi`.
      Running it opens LinPad and runs it in a terminal.
- [ ] Say "Hey Siri, start my dev setup in LinPad Duo". It opens VS Code and a terminal, or runs
      `~/.config/linpad/dev-setup.sh` if you've written one.
- [ ] The Action button can run any of these (iPhone Settings › Action Button › Shortcut).
- [ ] (Needs step 5b.) Add the LinPad widget to the Home Screen; its buttons open a workspace,
      a terminal or the dev setup (the dev setup asks first).
- [ ] With Apple Intelligence on, in foot: `ask "How do I see which programs use the most memory?"`
      With Wi-Fi off it still answers. `cat file.txt | ask "Summarise this"` works too.
- [ ] Cameras: a Linux video app (or `ffmpeg -f v4l2 -i /dev/video0 -frames 1 shot.jpg`) uses
      the camera facing you, on whichever screen you're using.

### Phase 11: safety and polish
- [ ] Backups (already in LinPad): Settings › Maintenance › Back Up Now, choose iCloud Drive.
      Set it to weekly. Delete a test file in `~`, then Restore: the file is back.
- [ ] Settings › Safety and Battery › Require Face ID on. Switch away and back: LinPad asks for
      Face ID. The app switcher shows it covered. A command left running in foot kept running.
- [ ] Heat and battery guard: turn on Low Power Mode. Within 15 seconds the "Now" row says
      it's slowing busy programs; "Check Now" lists what uses the most CPU. Turn Low Power
      Mode off: everything goes back to normal.
- [ ] If you ever install and start an SSH server in Linux, LinPad warns you once.
- [ ] Getting fixes from LinPad: `tools/duo-merge-upstream.sh` (DUO-UPDATING.md). Today it
      says "Already up to date".
- [ ] Apple Pencil (once Apple switches it on for the Duo): drawing in a Linux paint app
      draws instead of scrolling.
- Faster launches, what I found: LinPad already keeps Thunar ready in the background
  (`/etc/ishwl/prewarm`). The big cost is the CPU emulator: measured on a fast Mac, Firefox
  takes 8–12 s to open and Thunar 1.3 s. Fast mode (step 5) is what makes the biggest
  difference. Keeping Firefox or VS Code running in the background would cost 1–2 GB of
  memory each, which on a phone gets LinPad closed by iOS, so I didn't add that.

### Phase 12: staying alive in the background
- [ ] Settings › Background › **While jobs run** (allow location when asked).
      Run `notify-phone run "Long test" -- sleep 1200` (20 minutes), switch to other apps,
      lock the phone. The blue location arrow shows while it runs. Come back after 20 minutes:
      the job shows Done in the tent board or Live Activity. After it ends the blue arrow goes.
- [ ] Settings › Safety and Battery › "Keep jobs running in other apps" on (iOS 26 or later):
      start a job, switch apps; iOS shows its own progress banner for it.
- [ ] Force-close LinPad in the app switcher during a job, then open it: your windows come
      back, and a message says the job stopped when iOS closed LinPad.
- [ ] Run on My PC (Settings › Run on My PC): fill in your PC's address and user, tap Save,
      then Set Up Key… (a terminal asks for the PC's password once). Send `sleep 60; echo done`.
      Close LinPad; come back after a minute; the job says Finished with "done" in its output.
      "Open in Terminal" shows it live.
- If "Keep jobs running" never shows iOS's banner: Apple may want the job names in Info.plist
  written differently. Tell Claude Code; the line is `BGTaskSchedulerPermittedIdentifiers`.
