/*
 * MobileEditorAdapter
 * The upstream editor is a fixed three-column desktop layout.  This adapter
 * tags the layout containers so MobileEditor.css can turn them into a single
 * scrollable phone layout.  Home and editor have different component trees,
 * so they are handled separately.
 */
(function () {
  var BREAKPOINT = 900;
  var scheduled = false;

  function add(el, name) {
    if (el && el.classList) el.classList.add(name);
  }

  function clearTags() {
    var names = [
      'mf-shell', 'mf-content', 'mf-root', 'mf-topbar', 'mf-toolbar',
      'mf-toolbar-nav', 'mf-main', 'mf-left', 'mf-center', 'mf-right',
      'mf-workbench', 'mf-workbench-wrap', 'mf-workbench-outer-wrap',
      'mf-preview-tab', 'mf-resize', 'mf-footer', 'mf-home-page'
    ];
    names.forEach(function (name) {
      document.querySelectorAll('.' + name).forEach(function (el) {
        el.classList.remove(name);
      });
    });
  }

  function tag() {
    var mobile = window.innerWidth <= BREAKPOINT;
    var isEditor = (location.hash || '').indexOf('/editor') !== -1;

    document.documentElement.classList.toggle('miface-mobile', mobile);
    document.body.classList.toggle('miface-mobile', mobile);
    document.body.classList.toggle('mf-page-editor', isEditor);
    document.body.classList.toggle('mf-page-home', !isEditor);

    if (!mobile) return;

    clearTags();

    var shell = document.querySelector('#app > div');
    if (!shell) return;

    var topbar = shell.children[0];
    var content = shell.children[1];
    var root = content && content.firstElementChild;

    add(shell, 'mf-shell');
    add(topbar, 'mf-topbar');
    add(content, 'mf-content');
    add(root, 'mf-root');

    if (!root) return;

    if (isEditor) {
      var toolbar = root.children[0];
      var main = root.children[1];
      add(toolbar, 'mf-toolbar');
      add(main, 'mf-main');

      if (main) {
        var left = main.children[0];
        var center = main.children[1];
        var right = main.children[2];
        add(left, 'mf-left');
        add(center, 'mf-center');
        add(right, 'mf-right');

        add(main.querySelector('.cursor-col-resize'), 'mf-resize');

        if (center) {
          var workbench = center.querySelector('#workbench-outer');
          if (workbench) {
            add(workbench, 'mf-workbench');
            var parent = workbench.parentElement;
            add(parent, 'mf-workbench-wrap');
            if (parent && parent.parentElement) add(parent.parentElement, 'mf-workbench-outer-wrap');
          }
          add(center.querySelector('.absolute.right-0'), 'mf-preview-tab');
          add(center.children[center.children.length - 1], 'mf-footer');
        }
      }

      if (toolbar) {
        var nav = null;
        var descendants = toolbar.querySelectorAll('div');
        for (var i = 0; i < descendants.length; i++) {
          var cls = descendants[i].className;
          if (typeof cls === 'string' && cls.indexOf('left-1/2') !== -1) {
            nav = descendants[i];
            break;
          }
        }
        add(nav, 'mf-toolbar-nav');
      }
    } else {
      var left = root.querySelector('[class~="flex-[15]"]');
      var right = root.querySelector('[class~="flex-[85]"]');
      add(left, 'mf-left');
      add(right, 'mf-right');
      var page = (left && left.parentElement) || root.firstElementChild;
      add(page, 'mf-home-page');
    }
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    window.requestAnimationFrame(function () {
      scheduled = false;
      tag();
    });
  }

  window.addEventListener('hashchange', function () {
    window.setTimeout(tag, 80);
    window.setTimeout(tag, 500);
  });
  window.addEventListener('resize', schedule);
  window.addEventListener('orientationchange', function () {
    window.setTimeout(tag, 250);
  });
  document.addEventListener('DOMContentLoaded', tag);

  if (window.MutationObserver) {
    new MutationObserver(schedule).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  window.setTimeout(tag, 100);
  window.setTimeout(tag, 700);
  window.setTimeout(tag, 1800);
})();
