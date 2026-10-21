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

  var bridge = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bridge) || null;
  function post(message) { if (bridge) { bridge.postMessage(message); } }

  var editorEl = document.getElementById('editor');
  var editorPane = document.getElementById('editor-pane');
  var previewPane = document.getElementById('preview-pane');
  var outputEl = document.getElementById('output');
  var dividerEl = document.getElementById('divider');

  var state = {
    dark: localStorage.getItem(STORE_DARK) === 'true',
    sync: localStorage.getItem(STORE_SYNC) === 'true',
    guardUntil: 0,
    adapter: null,
  };

  var renderTimer = null;

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
      if (!state.sync || !state.adapter) { return; }

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
    return {
      kind: 'textarea',
      getValue: function () { return textarea.value; },
      setValue: function (value) { textarea.value = value; },
      onChange: function (cb) { textarea.addEventListener('input', cb); },
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

    // The editor always starts empty — we deliberately do not restore any
    // previously typed text. The only exception is the very first launch,
    // which shows the syntax guide as a one-off onboarding touch.
    if (localStorage.getItem(STORE_GUIDE) === null) {
      try { localStorage.setItem(STORE_GUIDE, 'true'); } catch (e) {}
      loadSample(function (text) {
        if (text && adapter.getValue() === '') {
          adapter.setValue(text);
        }
        scheduleRender();
      });
    }

    adapter.onChange(function () {
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
    scheduleRender();
    refreshPreviewMetrics();

    post({ type: 'ready', dark: state.dark, sync: state.sync });
  }

  /* ------------------------------ API used by the native app ------------------------------ */

  window.mdac = {
    setText: function (text) {
      state.adapter.setValue(text);
      scheduleRender();
    },
    getText: function () {
      return state.adapter.getValue();
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
    resetEditor: function () {
      state.adapter.setValue('');
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
