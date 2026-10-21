# Reproduce

## Bug fix: file link lost on relaunch

### What the app used to do wrong, and why

MDacViewer used to remember the text you had typed by copying it inside the app after
every change you made. It saved the *text*, but it never saved *which file* that text
came from — the file's location lived only in memory, so it vanished the moment you
quit.

The result was a confusing half-remembered state. After you quit and reopened the app,
the editor still showed your words, but the app no longer knew where those words
belonged. The window title fell back to plain "MDacViewer", and pressing Save had no
file to write back to, so it opened a *Save As* panel and asked you to choose a folder
and name again — as if the document had never been opened. In other words, the text came
back but the link to the file did not, and the app could no longer write back to the
file on disk.

### What it does now

The app no longer remembers the editor's text at all. Every launch starts with an empty
editor, and the window title reads exactly "MDacViewer". This is the normal behaviour of
a single-document Mac app: closing the app closes the document, and reopening it gives
you a fresh, empty page. A file is only "current" while the app is actually running.

Because nothing is half-restored any more, everything stays consistent — no file is
open, the title is plain, and Save correctly asks where to save. That *Save As* panel is
the right thing to show now, because there genuinely is no file attached, rather than
because a link was lost.

There is one deliberate exception: the very first time you ever launch the app it still
shows the built-in syntax guide, so new users have something to look at. After that
first launch the editor opens empty. Your dark-mode and sync-scroll preferences are still
remembered between launches; only the editor text is not.

### How to verify this manually on a Mac

1. Open MDacViewer.
2. Open a Markdown file, for example with ⌘O. The title should become
   "MDacViewer — <filename>".
3. Edit the text.
4. Press ⌘S to save. No save panel appears and the change is written straight back to
   the same file.
5. Quit the app with ⌘Q.
6. Reopen MDacViewer.
7. Check that the editor is empty and the window title is exactly "MDacViewer".
8. Press ⌘S. A *Save As* panel appears. This is now CORRECT behaviour: no file is open,
   so the app has to ask where to save. Pick a name and place, and the title becomes
   "MDacViewer — <filename>" again.

Running these steps requires a Mac with Xcode or the Command Line Tools; use
`make run` as described in the "Build from source" section of `README.md`.

## Feature: unsaved-changes indicator + save nudge

### What it does

Any edit — with or without an open file — puts an asterisk in the window title:
`MDacViewer — notes.md *`, or `MDacViewer *` for untitled text. Saving removes
it.

If the window is closed (red button) or the app is quit (⌘Q) while there are
unsaved edits, the standard three-button alert appears: **Save** (default),
**Cancel**, and **Don't Save** (destructive). Save writes to the open file (or
asks where to save untitled text) and then closes; Cancel leaves everything as
it was; Don't Save closes and discards the edit.

Notes:

- ⌘W is not wired to anything in this app (there is no Close menu item), so the red
  button is the window-close path; ⌘Q is the quit path. Both show the same alert.
- Save As, Open and Reset all clear the flag.
- Implementation note: SwiftUI owns the main window's `NSWindowDelegate` and relies
  on it (replacing the delegate makes the window close itself on the next scene
  update, e.g. when a file is opened), so the red button's action is intercepted
  instead, and quitting is handled by `applicationShouldTerminate`.

### How to verify this manually on a Mac

1. Open a Markdown file and edit it. The title becomes `MDacViewer — <filename> *`.
2. Press ⌘S. No save panel appears, the file on disk is updated, and the asterisk
   disappears.
3. Edit again, then click the red close button (or press ⌘Q). The Save / Cancel /
   Don't Save alert appears.
4. Choose Cancel. The window stays open and the asterisk is still there.
5. Close again and choose Don't Save. The app quits and the file on disk is unchanged
   from the last save.
6. Edit once more, press ⌘Q, and choose Save. The app writes the file and then quits.
7. With no file open, type some text: the title shows `MDacViewer *`, and
   closing prompts; Save opens a Save As panel.

## Bug fix: red close button crash + unsaved asterisk for untitled text

### What the app used to do wrong, and why

Two problems showed up together in a fresh session (no file opened yet).

First, typing did not put the asterisk in the title. The dirty flag was only
tracked while a file was open — `markDirty()` ignored every edit when there was
no file — so the title stayed plain "MDacViewer" even with unsaved text in the
editor, and closing would have discarded that text without asking.

Second, clicking the red close button crashed the app. Since 1.0.2 the button's
action is intercepted so the Save / Don't Save / Cancel nudge can run before the
window closes. When there was nothing to save, that action called
`performClose(nil)` — but `performClose` simulates a click on the same close
button, so the action ran again, and again, until the main thread's stack
overflowed. The crash report shows roughly 10,000 recursive
`WindowFrameSaver.Coordinator.closeButtonPressed` frames and an `EXC_BAD_ACCESS`
in the stack guard region.

### What it does now

- Typing in a fresh session shows `MDacViewer *` in the title, exactly like
  editing an open file.
- Closing the window (red button) or quitting (⌘Q) with untitled unsaved text
  shows the same Save / Don't Save / Cancel alert. Save opens the Save As panel;
  Don't Save discards the text.
- A close-button click with nothing to save closes the window normally — the app
  quits immediately instead of recursing until the stack overflows.

### How to verify this manually on a Mac

1. Launch MDacViewer without opening a file. The title is exactly "MDacViewer".
2. Type a few characters. The title becomes `MDacViewer *`.
3. Click the red close button. The Save / Don't Save / Cancel alert appears —
   the app does NOT crash.
4. Choose Cancel. The window stays open with the text intact.
5. Click the red button again and choose Don't Save. The app quits.
6. Relaunch and click the red button without typing anything. The app closes
   cleanly with no alert and no crash.

Automated check: `./Scripts/verify-close-button.sh` compiles the window and
title-tracking code into a small harness that clicks the close button
in-process, then asserts the window actually closes and the asterisk appears.
It needs no Accessibility permission. (Before the fix, it dies with the same
SIGSEGV as the crash report.)