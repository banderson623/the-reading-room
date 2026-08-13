// Page-side behavior: syntax highlighting, code copy buttons, scroll reporting.
// Navigation is handled natively in Swift, not here.
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

  function addCopyButtons() {
    document.querySelectorAll("pre").forEach(function (pre) {
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

  if (window.__restoreScroll) {
    // Images loading above the viewport shift the layout after the first
    // scroll, so keep re-asserting the offset until the page settles — or the
    // reader scrolls on their own, whichever comes first.
    var restore = window.__restoreScroll;
    var holding = true;
    var release = function () {
      holding = false;
    };
    ["wheel", "touchstart", "keydown", "mousedown"].forEach(function (type) {
      window.addEventListener(type, release, { passive: true, once: true });
    });
    var assertScroll = function () {
      if (holding) window.scrollTo(0, restore);
    };
    assertScroll();
    document.querySelectorAll("img").forEach(function (img) {
      if (!img.complete) img.addEventListener("load", assertScroll, { once: true });
    });
    window.addEventListener("load", assertScroll, { once: true });
    setTimeout(release, 2000);
  } else if (location.hash) {
    var target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (target) target.scrollIntoView();
  }
})();
