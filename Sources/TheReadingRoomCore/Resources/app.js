// Page-side behavior: syntax highlighting, Mermaid diagrams, code copy
// buttons, scroll reporting. Navigation is handled natively in Swift, not here.
(function () {
  "use strict";

  function post(message) {
    if (window.webkit && window.webkit.messageHandlers.app) {
      window.webkit.messageHandlers.app.postMessage(message);
    }
  }

  function highlight() {
    if (typeof hljs === "undefined") return;
    document.querySelectorAll('pre code[class*="language-"]').forEach(function (block) {
      var language = (block.className.match(/language-([\w+#-]+)/) || [])[1];
      if (!language || !hljs.getLanguage(language)) return;
      try {
        block.innerHTML = hljs.highlight(block.textContent, {
          language: language,
          ignoreIllegals: true,
        }).value;
        block.classList.add("hljs");
      } catch (error) {
        /* leave the block unhighlighted */
      }
    });
  }

  function addCopyButton(pre) {
    var button = document.createElement("button");
    button.className = "copy-button";
    button.type = "button";
    button.textContent = "Copy";
    button.addEventListener("click", function () {
      var code = pre.querySelector("code");
      // Copy through the app: a custom-scheme page is not a secure context,
      // so navigator.clipboard is unavailable here.
      post({ kind: "copy", text: code ? code.textContent : pre.textContent });
      button.textContent = "Copied";
      setTimeout(function () {
        button.textContent = "Copy";
      }, 1200);
    });
    var wrapper = document.createElement("div");
    wrapper.className = "code-wrapper";
    pre.parentNode.insertBefore(wrapper, pre);
    wrapper.appendChild(pre);
    wrapper.appendChild(button);
  }

  function addCopyButtons() {
    // Diagram sources are about to be drawn over; one that fails to draw gets
    // its button when it falls back to a code block.
    document.querySelectorAll("pre:not(.mermaid)").forEach(addCopyButton);
  }

  // Mermaid diagrams. The renderer leaves each ```mermaid fence as a
  // <pre class="mermaid"> holding the source; this draws the SVG in its place.
  // A diagram that will not parse falls back to the source as a code block
  // with the parser's complaint under it, rather than Mermaid's error graphic.
  var diagrams = [];
  var diagramCount = 0;

  function configureMermaid() {
    var dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    mermaid.initialize({
      startOnLoad: false,
      theme: dark ? "dark" : "default",
      securityLevel: "strict",
      suppressErrorRendering: true,
      fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif',
    });
  }

  function drawDiagram(diagram) {
    var id = "mermaid-" + ++diagramCount;
    return mermaid.render(id, diagram.source).then(
      function (result) {
        var figure = document.createElement("figure");
        figure.className = "mermaid-diagram";
        figure.innerHTML = result.svg;
        diagram.node.replaceWith(figure);
        diagram.node = figure;
        if (result.bindFunctions) result.bindFunctions(figure);
        window.dispatchEvent(new Event("mdv:relayout"));
      },
      function (error) {
        var pre = document.createElement("pre");
        var code = document.createElement("code");
        code.className = "language-mermaid";
        code.textContent = diagram.source;
        pre.appendChild(code);
        var note = document.createElement("div");
        note.className = "mermaid-error";
        note.textContent = "Mermaid could not draw this diagram: " + String(error && error.message ? error.message : error);
        diagram.node.replaceWith(pre);
        pre.parentNode.insertBefore(note, pre.nextSibling);
        addCopyButton(pre);
        diagram.node = pre;
        diagram.failed = true;
        window.dispatchEvent(new Event("mdv:relayout"));
      }
    );
  }

  function renderDiagrams() {
    if (typeof mermaid === "undefined") return;
    var nodes = document.querySelectorAll(".mermaid");
    if (!nodes.length) return;
    configureMermaid();
    nodes.forEach(function (node) {
      var diagram = { node: node, source: node.textContent.trim(), failed: false };
      diagrams.push(diagram);
      drawDiagram(diagram);
    });
    // The theme is baked into the SVG, so switching light/dark draws again.
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
      configureMermaid();
      diagrams.forEach(function (diagram) {
        if (!diagram.failed) drawDiagram(diagram);
      });
    });
  }

  // Task checkboxes are inert in the rendered HTML; the app turns them on so a
  // tick rewrites the marker in the file. It is the only editing there is.
  function enableTaskCheckboxes() {
    if (!(window.webkit && window.webkit.messageHandlers.app)) return;
    document.querySelectorAll('input[type="checkbox"][data-line]').forEach(function (box) {
      box.disabled = false;
      box.addEventListener("change", function () {
        post({
          kind: "toggle",
          line: Number(box.getAttribute("data-line")),
          was: !box.checked,
          now: box.checked,
        });
      });
    });
  }

  // Let the app persist scroll position per file.
  function reportScroll() {
    post({ kind: "scroll", y: window.scrollY });
  }

  var scrollTimer = null;
  window.addEventListener(
    "scroll",
    function () {
      if (scrollTimer) return;
      scrollTimer = setTimeout(function () {
        scrollTimer = null;
        reportScroll();
      }, 120);
    },
    { passive: true }
  );

  highlight();
  addCopyButtons();
  enableTaskCheckboxes();
  renderDiagrams();

  // Images loading and diagrams drawing above the viewport shift the layout
  // after the first scroll, so whatever put the page at its starting position
  // — a remembered offset or a #fragment — keeps re-asserting it until the
  // page settles, or the reader scrolls on their own, whichever comes first.
  var settle = null;
  if (window.__restoreScroll) {
    var restore = window.__restoreScroll;
    settle = function () {
      window.scrollTo(0, restore);
    };
  } else if (location.hash) {
    var target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (target) {
      settle = function () {
        target.scrollIntoView();
      };
    }
  }
  if (settle) {
    var holding = true;
    var release = function () {
      holding = false;
    };
    ["wheel", "touchstart", "keydown", "mousedown"].forEach(function (type) {
      window.addEventListener(type, release, { passive: true, once: true });
    });
    var assertPosition = function () {
      if (holding) settle();
    };
    assertPosition();
    document.querySelectorAll("img").forEach(function (img) {
      if (!img.complete) img.addEventListener("load", assertPosition, { once: true });
    });
    window.addEventListener("mdv:relayout", assertPosition);
    window.addEventListener("load", assertPosition, { once: true });
    setTimeout(release, 2000);
  }
})();
