/* MDacViewer — web layer.
 *
 * Editor + live Markdown preview, running fully offline inside WKWebView.
 * Rendering stack mirrors markdownlivepreview.com:
 *   marked (Markdown → HTML) + DOMPurify (sanitising) + mermaid (diagrams)
 *   + github-markdown-css (themes), with Monaco as the editor.
 *
 * The native Swift side talks to this file through `window.mdac` (below)
 * and receives status messages through the WKWebView bridge.
 */

(function () {
  'use strict';

  var STORE_DARK = 'mdac.dark';
  var STORE_SYNC = 'mdac.sync';
  var STORE_GUIDE = 'mdac.guide';
  var STORE_PREVIEW_FONT_SIZE = 'mdac.previewFontSize';

  var MIN_PREVIEW_FONT_SIZE = 6;
  var MAX_PREVIEW_FONT_SIZE = 72;
  var DEFAULT_PREVIEW_FONT_SIZE = 16;

  var bridge = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) || null;
  function post(message) { if (bridge) { bridge.postMessage(message); } }

  var editorEl = document.getElementById('editor');
  var editorPane = document.getElementById('editor-pane');
  var previewPane = document.getElementById('preview-pane');
  var outputEl = document.getElementById('output');
  var dividerEl = document.getElementById('divider');

  function clampPreviewFontSize(value) {
    var size = Math.round(Number(value));
    if (!isFinite(size)) { size = DEFAULT_PREVIEW_FONT_SIZE; }
    return Math.min(MAX_PREVIEW_FONT_SIZE, Math.max(MIN_PREVIEW_FONT_SIZE, size));
  }

  function storedPreviewFontSize() {
    var stored = localStorage.getItem(STORE_PREVIEW_FONT_SIZE);
    if (stored === null || stored === '') { return DEFAULT_PREVIEW_FONT_SIZE; }
    return clampPreviewFontSize(stored);
  }

  function normalizeViewMode(mode) {
    return (mode === 'editor' || mode === 'preview') ? mode : 'split';
  }

  var state = {
    dark: localStorage.getItem(STORE_DARK) === 'true',
    sync: localStorage.getItem(STORE_SYNC) === 'true',
    previewFontSize: storedPreviewFontSize(),
    viewMode: 'split',
    guardUntil: 0,
    adapter: null,
  };

  var renderTimer = null;

  // Programmatic loads (opening a file, resetting, the first-run sample) must
  // not mark the document dirty: Monaco fires its change event synchronously
  // from setValue, so the flag is toggled around the call.
  var suppressDirty = false;

  function setEditorText(text) {
    suppressDirty = true;
    state.adapter.setValue(text);
    suppressDirty = false;
  }

  /* ------------------------------ tabs ------------------------------ */

  // Each tab owns one editor model — Monaco models keep their own text and
  // undo history — plus both panes' scroll positions. Only the active tab is
  // attached to the editor, so switching tabs swaps models instead of loading
  // another copy of Monaco.
  var tabs = Object.create(null);
  var activeTabId = null;
  var claimedBootModel = false;

  function createTab(id, text) {
    if (!id || tabs[id]) { return; }
    var hasText = typeof text === 'string';

    var entry = { model: null, viewState: null, previewScroll: 0 };

    if (!claimedBootModel) {
      // The first tab carries over the editor's boot content (the one-off
      // first-run sample) into its own model, unless the native side has an
      // explicit document for it. The editor's implicit boot model is owned
      // by Monaco and is replaced — and disposed — when the first tab is
      // attached, so its text must be copied first.
      claimedBootModel = true;
      entry.model = state.adapter.createModel(hasText ? text : state.adapter.getValue());
    } else {
      entry.model = state.adapter.createModel(hasText ? text : '');
    }

    tabs[id] = entry;
    if (activeTabId === null) {
      activeTabId = id;
      state.adapter.setModel(entry.model);
      render();
    }
  }

  function saveActiveTabState() {
    if (!activeTabId || !tabs[activeTabId]) { return; }
    tabs[activeTabId].viewState = state.adapter.saveViewState();
    tabs[activeTabId].previewScroll = previewPane.scrollTop;
  }

  function activateTab(id) {
    if (!id || id === activeTabId || !tabs[id]) { return; }
    saveActiveTabState();
    activeTabId = id;
    state.adapter.setModel(tabs[id].model);
    state.adapter.restoreViewState(tabs[id].viewState);
    previewPane.scrollTop = tabs[id].previewScroll || 0;
    render();
  }

  function closeTab(id) {
    var entry = tabs[id];
    if (!entry) { return; }
    if (id === activeTabId) { saveActiveTabState(); }

    delete tabs[id];
    if (id === activeTabId) {
      activeTabId = null;
      var remaining = Object.keys(tabs);
      if (remaining.length) {
        // Attach another tab before disposing the model we are leaving.
        activateTab(remaining[0]);
      } else {
        // Defensive: the native side keeps at least one tab, but leave the
        // editor with a valid empty model if every tab is ever removed.
        var blank = state.adapter.createModel('');
        state.adapter.setModel(blank);
        outputEl.innerHTML = '';
      }
    }
    state.adapter.disposeModel(entry.model);
  }

  function setTabText(id, text) {
    var entry = tabs[id];
    if (!entry) { return; }
    suppressDirty = true;
    state.adapter.setModelValue(entry.model, text);
    suppressDirty = false;
    if (id === activeTabId) { scheduleRender(); }
  }

  function getTabText(id) {
    var entry = tabs[id];
    return entry ? state.adapter.modelValue(entry.model) : '';
  }

  /* ------------------------------ rendering ------------------------------ */

  marked.setOptions({ gfm: true });

  function render() {
    var html = marked.parse(state.adapter.getValue());
    outputEl.innerHTML = DOMPurify.sanitize(html);

    // Turn ```mermaid blocks into live diagrams.
    var blocks = outputEl.querySelectorAll('pre > code.language-mermaid');
    for (var i = 0; i < blocks.length; i++) {
      var code = blocks[i];
      var div = document.createElement('div');
      div.className = 'mermaid';
      div.textContent = code.textContent;
      code.parentElement.replaceWith(div);
    }

    var diagrams = outputEl.querySelectorAll('.mermaid');
    if (diagrams.length) {
      mermaid.initialize({
        startOnLoad: false,
        theme: state.dark ? 'dark' : 'default',
        securityLevel: 'strict',
        themeVariables: { fontSize: state.previewFontSize + 'px' },
        flowchart: { useMaxWidth: true },
      });
      mermaid.run({
        nodes: Array.prototype.slice.call(diagrams),
        suppressErrors: true,
      }).then(function () {
        refreshPreviewMetrics();
      }).catch(function (err) {
        console.warn('mermaid render failed:', err);
      });
    }

    refreshPreviewMetrics();
  }

  function scheduleRender() {
    clearTimeout(renderTimer);
    renderTimer = setTimeout(render, 150);
  }

  /* ------------------------------ theme / sync scroll ------------------------------ */

  function applyTheme(dark) {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    document.getElementById('gh-markdown-css').href =
      dark ? 'vendor/github-markdown-dark-dimmed.css' : 'vendor/github-markdown-light.css';
    if (state.adapter) {
      state.adapter.setDark(dark);
      scheduleRender(); // re-render diagrams with the new theme
    }
  }

  function applyPreviewFontSize(size) {
    state.previewFontSize = clampPreviewFontSize(size);
    document.documentElement.style.setProperty(
      '--mdac-preview-font-size', state.previewFontSize + 'px');
    refreshPreviewMetrics();
  }

  function applyViewMode(mode) {
    state.viewMode = normalizeViewMode(mode);
    document.documentElement.setAttribute('data-view-mode', state.viewMode);

    // In Preview Only the editor is hidden but Monaco's textarea can still
    // hold focus. Drop it so typing cannot change an invisible document.
    if (state.viewMode === 'preview' && editorPane.contains(document.activeElement)) {
      document.activeElement.blur();
    }

    if (!state.adapter) { return; }
    // Wait one frame so the pane visibility change has been laid out before
    // Monaco and the preview scroll metrics recalculate.
    requestAnimationFrame(function () {
      state.adapter.layout();
      refreshPreviewMetrics();
    });
  }

  // Cached scroll metrics. Reading scrollHeight forces a layout pass, so we
  // refresh these only when content/size actually changes — never inside the
  // scroll handler itself (that caused the preview to stutter during sync).
  var previewMax = 0;
  function refreshPreviewMetrics() {
    previewMax = Math.max(0, previewPane.scrollHeight - previewPane.clientHeight);
  }

  // Scroll syncing is batched to one update per display frame.
  var syncFrame = null;
  var syncSource = null;

  function scheduleSync(source) {
    syncSource = source;
    if (syncFrame !== null) { return; }
    syncFrame = requestAnimationFrame(function () {
      syncFrame = null;
      var source = syncSource;
      syncSource = null;
      // Sync scroll only has meaning while both panes are visible.
      if (!state.sync || state.viewMode !== 'split' || !state.adapter) { return; }

      var now = Date.now();
      if (now < state.guardUntil) { return; }

      if (source === 'editor') {
        var ratio = state.adapter.scrollRatio();
        var target = ratio * previewMax;
        if (Math.abs(target - previewPane.scrollTop) < 1) { return; }
        state.guardUntil = now + 70;
        previewPane.scrollTop = target;
      } else if (source === 'preview') {
        var previewRatio = previewMax > 0 ? previewPane.scrollTop / previewMax : 0;
        state.guardUntil = now + 70;
        state.adapter.setScrollRatio(previewRatio);
      }
    });
  }

  /* ------------------------------ editor adapters ------------------------------ */

  // Minimal fallback used only if Monaco fails to load for some reason.
  function createTextareaAdapter(el) {
    var textarea = document.createElement('textarea');
    textarea.className = 'fallback-editor';
    textarea.spellcheck = false;
    el.appendChild(textarea);

    var current = { text: '' };

    return {
      kind: 'textarea',
      getValue: function () { return current.text; },
      setValue: function (value) { current.text = value; textarea.value = value; },
      createModel: function (text) { return { text: text || '' }; },
      setModel: function (model) {
        current = model;
        textarea.value = model.text;
      },
      modelValue: function (model) { return model.text; },
      setModelValue: function (model, text) {
        model.text = text;
        if (model === current) { textarea.value = text; }
      },
      disposeModel: function () {},
      saveViewState: function () { return textarea.scrollTop; },
      restoreViewState: function (scrollTop) {
        if (typeof scrollTop === 'number') { textarea.scrollTop = scrollTop; }
      },
      onChange: function (cb) {
        textarea.addEventListener('input', function () {
          current.text = textarea.value;
          cb();
        });
      },
      onScroll: function (cb) { textarea.addEventListener('scroll', cb); },
      scrollRatio: function () {
        var max = textarea.scrollHeight - textarea.clientHeight;
        return max > 0 ? textarea.scrollTop / max : 0;
      },
      setScrollRatio: function (ratio) {
        textarea.scrollTop = ratio * (textarea.scrollHeight - textarea.clientHeight);
      },
      setDark: function (dark) {
        document.documentElement.classList.toggle('dark-editor', dark);
      },
      layout: function () {},
    };
  }

  function createMonacoAdapter(el, onReady) {
    // Monaco normally uses web workers for advanced language features; the
    // Markdown editor does not need them, so give them a harmless stub.
    self.MonacoEnvironment = {
      getWorker: function () {
        return new Worker(URL.createObjectURL(new Blob([''], { type: 'text/javascript' })));
      },
    };

    require.config({ paths: { vs: 'vendor/monaco/min/vs' } });
    require(['vs/editor/editor.main'], function () {
      var editor = monaco.editor.create(el, {
        value: '',
        language: 'markdown',
        theme: 'vs',
        automaticLayout: true,
        fontSize: 13,
        lineHeight: 20,
        fontFamily: '"SF Mono", Menlo, Monaco, monospace',
        wordWrap: 'on',
        minimap: { enabled: false },
        scrollBeyondLastLine: false,
        renderLineHighlight: 'all',
        padding: { top: 8, bottom: 8 },
        smoothScrolling: true,
      });

      onReady({
        kind: 'monaco',
        getValue: function () { return editor.getValue(); },
        setValue: function (value) { editor.setValue(value); },
        createModel: function (text) { return monaco.editor.createModel(text || '', 'markdown'); },
        setModel: function (model) { editor.setModel(model); },
        modelValue: function (model) { return model.getValue(); },
        setModelValue: function (model, text) { model.setValue(text); },
        disposeModel: function (model) {
          try { if (model && !model.isDisposed()) { model.dispose(); } } catch (e) {}
        },
        saveViewState: function () { return editor.saveViewState(); },
        restoreViewState: function (viewState) {
          if (viewState) { editor.restoreViewState(viewState); }
        },
        onChange: function (cb) { editor.onDidChangeModelContent(cb); },
        onScroll: function (cb) { editor.onDidScrollChange(cb); },
        scrollRatio: function () {
          var scrollable = editor.getScrollHeight() - editor.getLayoutInfo().height;
          return scrollable > 0 ? editor.getScrollTop() / scrollable : 0;
        },
        setScrollRatio: function (ratio) {
          var scrollable = editor.getScrollHeight() - editor.getLayoutInfo().height;
          editor.setScrollTop(ratio * scrollable);
        },
        setDark: function (dark) { monaco.editor.setTheme(dark ? 'vs-dark' : 'vs'); },
        layout: function () { editor.layout(); },
      });
    }, function (err) {
      console.error('Monaco failed to load; falling back to a plain editor.', err);
      onReady(createTextareaAdapter(el));
    });
  }

  /* ------------------------------ pane divider ------------------------------ */

  function initDivider() {
    var dragging = false;

    dividerEl.addEventListener('mousedown', function (e) {
      dragging = true;
      e.preventDefault();
      document.body.classList.add('resizing');
    });

    window.addEventListener('mousemove', function (e) {
      if (!dragging) { return; }
      var total = document.getElementById('split').clientWidth;
      var leftWidth = Math.min(Math.max(e.clientX, 220), total - 220);
      editorPane.style.flex = '0 0 ' + leftWidth + 'px';
      previewPane.style.flex = '1 1 auto';
    });

    window.addEventListener('mouseup', function () {
      if (!dragging) { return; }
      dragging = false;
      document.body.classList.remove('resizing');
      if (state.adapter) { state.adapter.layout(); }
      refreshPreviewMetrics();
    });
  }

  /* ------------------------------ preview copy ------------------------------ */

  // Copying rendered Markdown must produce plain text only. WebKit's default
  // copy writes text/html alongside the text, and rich-text destinations
  // (Claude, Notes, Word…) then keep the preview's code-block background — the
  // grey "box" around the pasted words. Writing only text/plain keeps the
  // words and drops every bit of preview styling.
  function selectionIsInPreview(selection) {
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      return false;
    }
    var node = selection.getRangeAt(0).commonAncestorContainer;
    if (node.nodeType !== Node.ELEMENT_NODE) { node = node.parentNode; }
    return !!node && outputEl.contains(node);
  }

  function initPreviewCopy() {
    document.addEventListener('copy', function (event) {
      var selection = window.getSelection();
      if (!selectionIsInPreview(selection)) { return; }

      var text = selection.toString();
      var clipboard = event.clipboardData;
      if (!text || !clipboard) { return; }

      event.preventDefault();
      clipboard.setData('text/plain', text);
    });
  }

  /* ------------------------------ sample content ------------------------------ */

  function loadSample(callback) {
    // XMLHttpRequest (not fetch) — fetch() is unreliable for custom URL schemes.
    var xhr = new XMLHttpRequest();
    xhr.open('GET', 'sample.md', true);
    xhr.onload = function () {
      callback((xhr.status === 200 || xhr.status === 0) ? xhr.responseText : '');
    };
    xhr.onerror = function () { callback(''); };
    xhr.send();
  }

  /* ------------------------------ boot ------------------------------ */

  function boot(adapter) {
    state.adapter = adapter;

    applyTheme(state.dark);
    applyPreviewFontSize(state.previewFontSize);
    applyViewMode(state.viewMode);

    // The editor always starts empty — we deliberately do not restore any
    // previously typed text. The only exception is the very first launch,
    // which shows the syntax guide as a one-off onboarding touch.
    if (localStorage.getItem(STORE_GUIDE) === null) {
      try { localStorage.setItem(STORE_GUIDE, 'true'); } catch (e) {}
      loadSample(function (text) {
        if (text && adapter.getValue() === '') {
          setEditorText(text);
        }
        scheduleRender();
      });
    }

    adapter.onChange(function () {
      if (!suppressDirty) {
        post({ type: 'dirty', dirty: true, tab: activeTabId });
      }
      scheduleRender();
    });
    adapter.onScroll(function () {
      if (state.sync) { scheduleSync('editor'); }
    });
    previewPane.addEventListener('scroll', function () {
      if (state.sync) { scheduleSync('preview'); }
    });
    window.addEventListener('resize', function () {
      adapter.layout();
      refreshPreviewMetrics();
    });

    initDivider();
    initPreviewCopy();
    scheduleRender();
    refreshPreviewMetrics();

    post({ type: 'ready', dark: state.dark, sync: state.sync, fontSize: state.previewFontSize });
    window.mdac.isReady = true;
  }

  /* ------------------------------ API used by the native app ------------------------------ */

  window.mdac = {
    setText: function (text) {
      setEditorText(text);
      scheduleRender();
    },
    getText: function () {
      return activeTabId ? getTabText(activeTabId) : state.adapter.getValue();
    },
    createTab: function (id, text) {
      createTab(id, text);
    },
    activateTab: function (id) {
      activateTab(id);
    },
    closeTab: function (id) {
      closeTab(id);
    },
    setTabText: function (id, text) {
      setTabText(id, text);
    },
    getTabText: function (id) {
      return getTabText(id);
    },
    getActiveTabId: function () {
      return activeTabId;
    },
    setTheme: function (dark) {
      dark = !!dark;
      state.dark = dark;
      try { localStorage.setItem(STORE_DARK, String(dark)); } catch (e) {}
      applyTheme(dark);
    },
    setSync: function (enabled) {
      enabled = !!enabled;
      state.sync = enabled;
      try { localStorage.setItem(STORE_SYNC, String(enabled)); } catch (e) {}
    },
    setViewMode: function (mode) {
      applyViewMode(mode);
    },
    getViewMode: function () {
      return state.viewMode;
    },
    setPreviewFontSize: function (size) {
      applyPreviewFontSize(size);
      try { localStorage.setItem(STORE_PREVIEW_FONT_SIZE, String(state.previewFontSize)); } catch (e) {}
      // Diagram labels are baked into the SVG, so redraw them at the new size.
      if (outputEl.querySelector('.mermaid')) { scheduleRender(); }
      return state.previewFontSize;
    },
    getPreviewFontSize: function () {
      return state.previewFontSize;
    },
    resetEditor: function () {
      setEditorText('');
      scheduleRender();
    },
  };

  /* ------------------------------ start ------------------------------ */

  if (window.require && window.require.config) {
    createMonacoAdapter(editorEl, boot);
  } else {
    boot(createTextareaAdapter(editorEl));
  }
})();
