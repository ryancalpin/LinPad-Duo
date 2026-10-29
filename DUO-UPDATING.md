# Getting fixes from the original LinPad

LinPad Duo is a fork (a copy that has gone its own way) of
[fspecii/LinPad](https://github.com/fspecii/LinPad). When LinPad gets fixes, you can bring
them into LinPad Duo. The phone can't rebuild its own app, so this happens on the Mac.

## The quick way

In the Terminal, in the `LinPad-Duo` folder:

```sh
git checkout duo
tools/duo-merge-upstream.sh
```

It says one of three things:

- **"Already up to date"**: nothing new in LinPad. Nothing to do.
- **"Merged cleanly"**: LinPad's changes are in. Build and install as in DUO-SETUP.md, check
  the app still works, then run `git push` to save it to GitHub.
- **"These files changed in both…"**: LinPad and LinPad Duo both changed the same lines,
  and someone has to decide how to combine them (a "merge conflict"). Open Claude Code in the
  folder and say: *"Resolve the merge conflicts from fspecii/LinPad and explain each one."*
  If you'd rather not, `git merge --abort` puts everything back as it was.

Only want to know whether there's anything new? `tools/duo-merge-upstream.sh --check`.

## For Claude Code: how to resolve conflicts

1. `git diff --name-only --diff-filter=U` lists the conflicted files.
2. For each one, read both sides. Keep LinPad's fix, and keep the Duo change on top of it.
   Most Duo changes live in their own files (`desktop/DesktopKit/Sources/DesktopKit/Core/Duo/`,
   `app/Desktop/Duo*.swift`, `duo-widgets/`), so conflicts should be in the few shared files
   the Duo work touched:
   - `Core/WindowManager.swift`: pose layouts and the frame memory.
   - `Core/DesktopRootView.swift`, `Core/DesktopController.swift`: Duo hooks.
   - `Linux/LinuxSurfaceView.swift`, `Linux/LinuxGUIBridge.swift`: zoom and Pencil.
   - `Apps/SettingsApp.swift`: the iPhone Duo section.
   - `app/Info.plist`, `app/iSH.xcconfig`, `app/AppARM64.xcconfig`: names, bundle ID, scenes.
   - `iSH.xcodeproj/project.pbxproj`: the Duo app files. Keep both sides' file entries.
   - `Core/System/Updates/ReleaseFeed.swift`: always keep `ryancalpin/LinPad-Duo`.
3. Explain each choice to Ryan in plain English, then `git add` the files and `git commit`.
4. Build (DUO-SETUP.md, step 3). Fix anything that no longer compiles before pushing.

## Done so far

- 29 October 2026: checked. LinPad Duo was made from LinPad's latest commit
  (`b7571be`), so there was nothing to merge yet.
