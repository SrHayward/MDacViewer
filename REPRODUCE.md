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

While a file is open, any edit puts an asterisk in the window title —
`MDacViewer — notes.md *` — and saving removes it. With no file open the title stays
exactly as before, and untitled text never gets an asterisk.

If the window is closed (red button) or the app is quit (⌘Q) while an open file has
unsaved edits, the standard three-button alert appears: **Save** (default),
**Cancel**, and **Don't Save** (destructive). Save writes to the open file and then
closes; Cancel leaves everything as it was; Don't Save closes and discards the edit.

Notes:

- ⌘W is not wired to anything in this app (there is no Close menu item), so the red
  button is the window-close path; ⌘Q is the quit path. Both show the same alert.
- Save As, Open and Reset all clear the flag.
- Untitled pasted text never prompts — only an open file can lose its link.
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
7. With no file open, paste some text: the title stays exactly `MDacViewer` and
   closing the window does not prompt.