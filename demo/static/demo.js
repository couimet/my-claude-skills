/**
 * Demo site interactive features.
 *
 * Progressive enhancement — all content is accessible without JS.
 * JS adds: artifact expand/collapse, diff/full view toggle.
 * S005 will add: scroll-based hash updates, keyboard navigation, progress bar.
 */

(function () {
  'use strict';

  // --- Artifact expand/collapse ---

  document.querySelectorAll('.artifact-toggle').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var expanded = btn.getAttribute('aria-expanded') === 'true';
      var contentId = btn.getAttribute('aria-controls');
      var content = document.getElementById(contentId);
      if (!content) return;

      if (expanded) {
        // Collapse.
        content.hidden = true;
        btn.setAttribute('aria-expanded', 'false');
        btn.querySelector('.artifact-toggle-icon').textContent = '+';
      } else {
        // Expand.
        content.hidden = false;
        btn.setAttribute('aria-expanded', 'true');
        btn.querySelector('.artifact-toggle-icon').textContent = '\u2212';
      }
    });
  });

  // --- Diff / Full view toggle ---

  document.querySelectorAll('.view-toggle').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var view = btn.getAttribute('data-view');
      var targetId = btn.getAttribute('data-target');
      var container = document.getElementById(targetId);
      if (!container) return;

      var diffView = container.querySelector('.artifact-diff-view');
      var fullView = container.querySelector('.artifact-full-view');
      if (!diffView || !fullView) return;

      // Update active toggle state.
      container.querySelectorAll('.view-toggle').forEach(function (t) {
        t.classList.remove('view-toggle--active');
      });
      btn.classList.add('view-toggle--active');

      if (view === 'diff') {
        diffView.hidden = false;
        fullView.hidden = true;
      } else {
        diffView.hidden = true;
        fullView.hidden = false;
      }
    });
  });
})();
