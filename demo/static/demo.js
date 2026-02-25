/**
 * Demo site interactive features.
 *
 * Progressive enhancement — all content is accessible without JS.
 * JS adds: artifact expand/collapse, diff/full toggle, scroll-based
 * hash updates, phase progress bar sync, j/k keyboard navigation.
 */

(function () {
  'use strict';

  // --- Artifact expand/collapse ---

  // Collapse all panels on init — without JS they render open (no-JS fallback).
  document.querySelectorAll('.artifact-toggle').forEach(function (btn) {
    var contentId = btn.getAttribute('aria-controls');
    var content = document.getElementById(contentId);
    if (content) {
      content.hidden = true;
      btn.setAttribute('aria-expanded', 'false');
      btn.querySelector('.artifact-toggle-icon').textContent = '+';
    }
  });

  document.querySelectorAll('.artifact-toggle').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var expanded = btn.getAttribute('aria-expanded') === 'true';
      var contentId = btn.getAttribute('aria-controls');
      var content = document.getElementById(contentId);
      if (!content) return;

      if (expanded) {
        content.hidden = true;
        btn.setAttribute('aria-expanded', 'false');
        btn.querySelector('.artifact-toggle-icon').textContent = '+';
      } else {
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

  // --- Scroll-based hash updates via Intersection Observer ---

  var exchangeCards = document.querySelectorAll('.exchange-card');
  var currentHash = '';

  if (exchangeCards.length > 0 && 'IntersectionObserver' in window) {
    var hashObserver = new IntersectionObserver(function (entries) {
      // Find the most visible entry that is intersecting.
      var best = null;
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          if (!best || entry.intersectionRatio > best.intersectionRatio) {
            best = entry;
          }
        }
      });

      if (best) {
        var id = best.target.id;
        if (id && id !== currentHash) {
          currentHash = id;
          history.replaceState(null, '', '#' + id);
          updateProgressBar(best.target);
        }
      }
    }, {
      threshold: [0.3, 0.5, 0.7],
      rootMargin: '-10% 0px -40% 0px'
    });

    exchangeCards.forEach(function (card) {
      hashObserver.observe(card);
    });
  }

  // --- Progress bar sync ---

  var progressPhases = document.querySelectorAll('.progress-phase');

  function updateProgressBar(activeCard) {
    if (!activeCard || progressPhases.length === 0) return;

    // Determine which phase this card belongs to by checking its class.
    var phaseNum = null;
    for (var i = 1; i <= 5; i++) {
      if (activeCard.classList.contains('phase-' + i)) {
        phaseNum = i;
        break;
      }
    }
    if (!phaseNum) return;

    progressPhases.forEach(function (link) {
      var linkPhase = link.getAttribute('data-phase');
      link.classList.remove('is-active', 'phase-active--1', 'phase-active--2',
        'phase-active--3', 'phase-active--4', 'phase-active--5');
      if (linkPhase === String(phaseNum)) {
        link.classList.add('is-active', 'phase-active--' + phaseNum);
      }
    });
  }

  // --- Hash navigation on page load ---

  function scrollToHash() {
    var hash = window.location.hash;
    if (!hash) return;

    var target = document.querySelector(hash);
    if (target) {
      // Small delay to ensure layout is settled.
      setTimeout(function () {
        var barHeight = document.querySelector('.progress-bar');
        var offset = barHeight ? barHeight.offsetHeight + 16 : 16;
        var top = target.getBoundingClientRect().top + window.pageYOffset - offset;
        window.scrollTo({ top: top, behavior: 'smooth' });
      }, 100);
    }
  }

  scrollToHash();

  // Also handle hash changes (e.g. clicking progress bar links).
  window.addEventListener('hashchange', scrollToHash);

  // --- Keyboard navigation: j/k ---

  var cardArray = Array.prototype.slice.call(exchangeCards);

  function getCurrentCardIndex() {
    var scrollY = window.pageYOffset || document.documentElement.scrollTop;
    var barHeight = document.querySelector('.progress-bar');
    var offset = barHeight ? barHeight.offsetHeight + 32 : 32;
    var viewTop = scrollY + offset;

    for (var i = cardArray.length - 1; i >= 0; i--) {
      if (cardArray[i].offsetTop <= viewTop + 10) {
        return i;
      }
    }
    return 0;
  }

  function navigateToCard(index) {
    if (index < 0) index = 0;
    if (index >= cardArray.length) index = cardArray.length - 1;

    var card = cardArray[index];
    if (!card) return;

    var barHeight = document.querySelector('.progress-bar');
    var offset = barHeight ? barHeight.offsetHeight + 16 : 16;
    var top = card.getBoundingClientRect().top + window.pageYOffset - offset;
    window.scrollTo({ top: top, behavior: 'smooth' });
  }

  document.addEventListener('keydown', function (e) {
    // Don't intercept if user is typing in an input/textarea.
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' ||
        e.target.isContentEditable) return;

    if (e.key === 'j') {
      e.preventDefault();
      navigateToCard(getCurrentCardIndex() + 1);
    } else if (e.key === 'k') {
      e.preventDefault();
      navigateToCard(getCurrentCardIndex() - 1);
    }
  });

  // --- Initialize progress bar on load ---
  // Set the first phase as active initially.
  if (progressPhases.length > 0) {
    var initialCard = document.querySelector('.exchange-card');
    if (initialCard) {
      updateProgressBar(initialCard);
    }
  }

})();
