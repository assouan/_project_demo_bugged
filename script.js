// Date du jour
(function(){
  const d = new Date();
  const opts = {weekday:'long',year:'numeric',month:'long',day:'numeric'};
  const el = document.getElementById('currentDate');
  if(el) el.textContent = d.toLocaleDateString('fr-FR',opts).charAt(0).toUpperCase() + d.toLocaleDateString('fr-FR',opts).slice(1);
})();

// Header scroll effect
(function(){
  const header = document.getElementById('siteHeader');
  let last = 0;
  window.addEventListener('scroll',()=>{
    const y = window.scrollY;
    header.classList.toggle('scrolled',y>50);
    last=y;
  },{passive:true});
})();

// Search overlay
(function(){
  const overlay = document.getElementById('searchOverlay');
  const openBtn = document.getElementById('searchBtn');
  const closeBtn = document.getElementById('searchClose');
  openBtn.addEventListener('click',()=>overlay.classList.add('active'));
  closeBtn.addEventListener('click',()=>overlay.classList.remove('active'));
  overlay.addEventListener('click',(e)=>{if(e.target===overlay)overlay.classList.remove('active')});
  document.addEventListener('keydown',(e)=>{if(e.key==='Escape')overlay.classList.remove('active')});
})();

// Mobile menu
(function(){
  const menu = document.getElementById('mobileMenu');
  const overlay = document.getElementById('mobileOverlay');
  const toggle = document.getElementById('menuToggle');
  const close = document.getElementById('mobileClose');
  function open(){menu.classList.add('active');overlay.classList.add('active');document.body.style.overflow='hidden'}
  function closeMenu(){menu.classList.remove('active');overlay.classList.remove('active');document.body.style.overflow=''}
  toggle.addEventListener('click',open);
  close.addEventListener('click',closeMenu);
  overlay.addEventListener('click',closeMenu);
})();

// Back to top
(function(){
  const btn = document.getElementById('backToTop');
  window.addEventListener('scroll',()=>{btn.classList.toggle('visible',window.scrollY>500)},{passive:true});
  btn.addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'}));
})();

// Newsletter form
(function(){
  const form = document.getElementById('newsletterForm');
  if(form){
    form.addEventListener('submit',(e)=>{
      e.preventDefault();
      const input = form.querySelector('input[type="email"]');
      const btn = form.querySelector('button');
      const original = btn.textContent;
      btn.textContent = '\u2705 Inscrit !';
      btn.style.background = '#10B981';
      input.value = '';
      setTimeout(()=>{btn.textContent=original;btn.style.background=''},3000);
    });
  }
})();

// Bookmark toggle
document.querySelectorAll('.bookmark-btn').forEach(btn=>{
  btn.addEventListener('click',()=>btn.classList.toggle('active'));
});

// Share button animation
document.querySelectorAll('.share-btn').forEach(btn=>{
  btn.addEventListener('click',function(){
    this.style.transform='scale(1.2)';
    setTimeout(()=>this.style.transform='',200);
    if(navigator.share){
      navigator.share({title:'Le Chronicle',url:location.href});
    }
  });
});

// Intersection Observer for scroll animations
(function(){
  const observer = new IntersectionObserver((entries)=>{
    entries.forEach(entry=>{
      if(entry.isIntersecting){
        entry.target.style.opacity='1';
        entry.target.style.transform='translateY(0)';
      }
    });
  },{threshold:0.1,rootMargin:'0px 0px -50px 0px'});

  document.querySelectorAll('.news-card,.opinion-card,.sidebar-card,.trending-item').forEach(el=>{
    el.style.opacity='0';
    el.style.transform='translateY(30px)';
    el.style.transition='opacity .6s ease, transform .6s ease';
    observer.observe(el);
  });
})();

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(a=>{
  a.addEventListener('click',(e)=>{
    const href=a.getAttribute('href');
    if(href==='#')e.preventDefault();
  });
});

// Ticker animation speed on hover
(function(){
  const ticker = document.querySelector('.ticker-scroll');
  if(ticker){
    ticker.addEventListener('mouseenter',()=>ticker.style.animationPlayState='paused');
    ticker.addEventListener('mouseleave',()=>ticker.style.animationPlayState='running');
  }
})();

console.log('\u2728 Le Chronicle - Chargement termin\u00e9');