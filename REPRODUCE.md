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

- ⌘W closes the current tab (⌘T opens a new one); the red button closes the
  window and ⌘Q quits. All of them show the same Save / Don't Save / Cancel alert,
  and a quit with several edited tabs asks once per tab.
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

## Feature: resizable preview text

### What it does

The rendered preview has its own text size, independent of the editor. Open the
text-size button in the toolbar (the `A A`-style icon beside Dark mode) and drag
the slider, or use its stepper, to pick any size from **6 px to 72 px** in 1 px
steps. The change is live: body text, headings, lists, tables, code blocks and
Mermaid diagram labels all scale together.

The current size is shown in the popover (for example “16 px”) and is saved for
next launch. **Reset** returns it to 16 px. The same actions are available from
the View menu and with the keyboard:

| Shortcut | Action |
| --- | --- |
| ⌘+ | Increase preview text size by 1 px |
| ⌘− | Decrease preview text size by 1 px |
| ⌘0 | Reset preview text size to 16 px |

The editor's own font size is deliberately unchanged.

### How to verify this manually on a Mac

1. Launch MDacViewer and open the built-in sample (or paste some Markdown with a
   heading, body text, a table and a code block).
2. Click the text-size toolbar icon. The popover shows “16 px”.
3. Drag the slider to 6 px. The preview shrinks to the 6 px minimum; the editor
   on the left stays exactly as it was.
4. Drag to the far right: the preview stops at 72 px.
5. Press ⌘+ and ⌘− a few times: the preview grows and shrinks by 1 px each time.
   Press ⌘0: the preview returns to 16 px.
6. Choose 23 px, quit and relaunch. Open the popover again: it still reads
   “23 px”, and the preview renders at that size.

Automated check: `./Scripts/verify-preview-font-size.sh` loads the real `Web/`
app in a WKWebView and verifies live resizing, heading scaling, the 6 px/72 px
limits, persistence across a reload, and the native Swift clamp/persistence
logic. It needs a logged-in Mac desktop session but no Accessibility permission.

## Feature: document tabs + width-safe preview

### What it does

The window now has a tab bar above the editor, like a browser. **+** (or ⌘T)
opens a new tab, **×** (or ⌘W) closes the current one, and clicking a tab
switches to it. Opening several files at once, or double-clicking files in
Finder, gives each its own tab; opening a file that is already open just brings
its tab forward.

Each tab keeps its own Monaco editor model, so its text and undo history
survive switching tabs, along with both panes' scroll positions. A dot appears
on a tab with unsaved changes, and the window title shows the usual asterisk.
Closing a tab, closing the window or quitting asks Save / Don't Save / Cancel
for every edited tab — saving a hidden tab writes its text back to its own file.

The preview no longer scrolls sideways. Long code lines wrap, long URLs and
inline code break, and wide tables size to the pane instead of becoming a
horizontal scroller. This is what fixes the screenshot in the original report,
where a long line inside a fenced code block produced a scrollbar.

### How to verify this manually on a Mac

1. Open two Markdown files (⌘O allows selecting several, or double-click them
   in Finder). Two tabs appear, and the second file is active.
2. Type in the first tab, switch to the second, then back. The text and cursor
   position are preserved, and the first tab shows an unsaved dot.
3. Press ⌘W. The Save / Don't Save / Cancel alert names the edited tab. Choose
   Cancel and the tab stays.
4. Press ⌘W again, choose Don't Save: only that tab closes; the other tab and
   its text remain.
5. Paste a very long line inside a fenced code block, a long unbroken URL, and
   a wide table. The preview wraps all of them; dragging the preview pane
   narrower never reveals a horizontal scrollbar.
6. Press ⌘Q with two edited tabs. The save prompt appears once per tab, naming
   each file; choose Save for one and don't save the other, then check that only
   the saved file changed on disk.

Automated check: `./Scripts/verify-tabs-and-layout.sh` loads the real `Web/`
app in a WKWebView, drives the native `AppState` tab API, and verifies
independent tab text, tab switching, dirty state and model disposal. It also
renders a long code line, a long URL and a wide table and asserts that neither
the preview pane nor any of those elements overflows horizontally. It needs a
logged-in Mac desktop session but no Accessibility permission.

## Bug fix: copying from the preview pasted a styled "box"

### What the app used to do wrong, and why

Selecting text in the rendered preview and pressing ⌘C put **two** things on the
clipboard: the plain text and a rich `text/html` version of the selection.
WebKit builds that HTML from the preview's CSS, so a copied code block carried
its grey background with it. Rich-text destinations — Claude, Notes, Word —
prefer the HTML, which is why pasting produced a grey box around the words
instead of plain text.

### What it does now

Copying anywhere inside the preview writes **only** `text/plain` to the
clipboard. Paragraphs, lists, code blocks and tables keep their words, line
breaks and table tabs, but every bit of preview styling is dropped. Copying in
the editor is untouched: Monaco still handles its own copy as usual.

### How to verify this manually on a Mac

1. Open a Markdown file with a fenced code block, such as the built-in sample.
2. Select a paragraph or the contents of a code block in the preview and press
   ⌘C.
3. Paste into Claude, Notes, TextEdit or another rich-text app. The text appears
   as plain text — no grey box, no background colour.
4. Click into the editor, select some source text and press ⌘C. It still copies
   normally (Monaco's own copy path).

Automated check: `./Scripts/verify-preview-copy.sh` loads the real `Web/` app in
a WKWebView, selects a code block, a paragraph, a table and the whole preview,
and dispatches a copy event. It asserts that `text/plain` contains the expected
words and that `text/html` is empty; it also checks that copying in the editor
is not intercepted. It needs a logged-in Mac desktop session but no
Accessibility permission.

## Feature: Sublime-style tabs

### What it does

The tab strip above the editor now follows Sublime Text's visual language:

- flat, square tabs instead of rounded pills;
- the active tab uses the same background as the editor — white in light mode,
  `#1e1e1e` in dark mode — while inactive tabs sit on a contrasting grey and
  their labels are dimmed;
- a 2 px separator at the top separates the tab strip from the window toolbar,
  so the active tab never looks like it bleeds up into the toolbar;
- the thin separators between tabs disappear next to the active tab, so it
  reads as one continuous surface with the editor below;
- the close × appears only on the active tab or the tab under the pointer, as in
  Sublime — inactive tabs stay uncluttered, with the unsaved dot still visible;
- the **+** button stays at the right-hand end of the strip.

The tab strip is a fixed 32 px high, with the same tab order, ⌘T / ⌘W
behaviour, dirty dots and save prompts as before — only the look changed.

### How to verify this manually on a Mac

1. Open two or three Markdown files so several tabs are visible.
2. Click between the tabs. The active tab should be unmistakable in both light
   and dark mode: bright surface, full-strength label and a visible ×; the
   others are dimmed and have no × until hovered.
3. Type in a tab to make it dirty: the dot still appears on its tab (and on
   hidden tabs), and the title asterisk still works.
4. Hover an inactive tab: it lightens slightly and its × fades in.
5. Check that the active tab still merges into the editor below it (no divider
   line under the selected tab).

Automated check: `./Scripts/verify-tabs-and-layout.sh` still covers the
functional side — independent tab text, switching, dirty state, closing and
model disposal — and must keep passing. The tab styling itself is visual and is
confirmed by eye in both appearances.

