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