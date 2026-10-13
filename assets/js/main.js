/* SibWatch — лендинг «Ремонт часов». Скрипт: форма, лайтбокс, слайдер «до/после». */
(function () {
  'use strict';

  // Текущий год в подвале
  var years = document.querySelectorAll('[data-year]');
  for (var i = 0; i < years.length; i++) years[i].textContent = new Date().getFullYear();

  /* ---------- Форма заявки ----------
     Сейчас отправляет через WhatsApp. Замените на реальный приём заявок
     (backend, Formspree, CRM). */
  var form = document.querySelector('[data-lead-form]');
  if (form) {
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var data = new FormData(form);
      var name = (data.get('name') || '').toString().trim();
      var phone = (data.get('phone') || '').toString().trim();
      var service = (data.get('service') || '').toString().trim();
      var comment = (data.get('comment') || '').toString().trim();

      var ok = form.querySelector('.form__ok');
      if (ok) {
        ok.style.display = 'block';
        ok.textContent = 'Спасибо' + (name ? ', ' + name : '') + '! Заявка отправлена, мы свяжемся с вами в рабочее время.';
      }

      var text = 'Заявка с сайта (ремонт часов)\n' +
        'Имя: ' + name + '\nТелефон: ' + phone + '\nУслуга: ' + service + '\nКомментарий: ' + comment;
      try { window.open('https://wa.me/73832879217?text=' + encodeURIComponent(text), '_blank'); } catch (err) {}
      form.reset();
    });
  }

  /* ---------- Лайтбокс для фото «до/после» ---------- */
  var lb = document.querySelector('[data-lightbox-modal]');
  if (lb) {
    var lbImg = lb.querySelector('img');
    document.addEventListener('click', function (e) {
      var item = e.target.closest ? e.target.closest('[data-lightbox]') : null;
      if (item) {
        lbImg.src = item.getAttribute('data-lightbox');
        var real = item.querySelector('img');
        lbImg.alt = real ? real.alt : '';
        lb.classList.add('is-open');
        return;
      }
      if (e.target === lb || (e.target.closest && e.target.closest('.lightbox__close'))) {
        lb.classList.remove('is-open');
        lbImg.src = '';
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { lb.classList.remove('is-open'); lbImg.src = ''; }
    });
  }

  /* ---------- Слайдер «было → стало» ---------- */
  var ba = document.querySelector('[data-ba]');
  if (ba) {
    var after = ba.querySelector('[data-ba-after]');
    var handle = ba.querySelector('[data-ba-handle]');
    var dragging = false;

    function setPos(clientX) {
      var rect = ba.getBoundingClientRect();
      var x = Math.max(0, Math.min(clientX - rect.left, rect.width));
      var pct = (x / rect.width) * 100;
      after.style.width = pct + '%';
      handle.style.left = pct + '%';
    }

    function start(e) { dragging = true; setPos(e.clientX || (e.touches && e.touches[0].clientX)); }
    function move(e) { if (!dragging) return; setPos(e.clientX || (e.touches && e.touches[0].clientX)); }
    function end() { dragging = false; }

    ba.addEventListener('mousedown', start);
    ba.addEventListener('touchstart', start, { passive: true });
    window.addEventListener('mousemove', move);
    window.addEventListener('touchmove', move, { passive: true });
    window.addEventListener('mouseup', end);
    window.addEventListener('touchend', end);

    // корректная ширина внутреннего изображения при ресайзе
    function resize() { after.querySelector('img').style.width = ba.getBoundingClientRect().width + 'px'; }
    window.addEventListener('resize', resize);
    resize();
  }

  /* ---------- FAQ-аккордеон ---------- */
  var faqLists = document.querySelectorAll('[data-faq]');
  for (var f = 0; f < faqLists.length; f++) {
    faqLists[f].addEventListener('click', function (e) {
      var btn = e.target.closest ? e.target.closest('.faq__q') : null;
      if (!btn || !this.contains(btn)) return;
      var item = btn.closest('.faq__item');
      var isOpen = item.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });
  }
  /* ---------- Мобильное меню в шапке ---------- */
  var shHead = document.getElementById('site-head');
  if (shHead) {
    var shToggle = shHead.querySelector('.sh-head__toggle');
    if (shToggle) {
      shToggle.addEventListener('click', function () {
        var open = shHead.classList.toggle('is-open');
        shToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        shToggle.setAttribute('aria-label', open ? 'Закрыть меню' : 'Открыть меню');
      });
      var shLinks = shHead.querySelectorAll('.sh-head__dropdown a');
      for (var s = 0; s < shLinks.length; s++) {
        shLinks[s].addEventListener('click', function () {
          shHead.classList.remove('is-open');
          shToggle.setAttribute('aria-expanded', 'false');
          shToggle.setAttribute('aria-label', 'Открыть меню');
        });
      }
    }
  }
})();
