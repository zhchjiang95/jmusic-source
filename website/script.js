// JMusic landing — minimal interactions
(function () {
  "use strict";

  // 1. Reveal-on-scroll using IntersectionObserver
  const reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const delay = parseInt(entry.target.dataset.delay || "0", 10);
            setTimeout(() => entry.target.classList.add("is-visible"), delay);
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
    );
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add("is-visible"));
  }

  // 2. Navbar elevation on scroll
  const nav = document.getElementById("nav");
  const onScroll = () => {
    if (!nav) return;
    if (window.scrollY > 8) {
      nav.classList.add("ring-1", "ring-white/10");
      nav.style.boxShadow = "0 12px 40px rgba(0,0,0,0.45)";
    } else {
      nav.classList.remove("ring-1", "ring-white/10");
      nav.style.boxShadow = "";
    }
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // 3. Copy-to-clipboard for code snippets
  document.querySelectorAll("[data-copy-target]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const targetId = btn.getAttribute("data-copy-target");
      const target = document.getElementById(targetId);
      if (!target) return;
      const text = target.textContent || "";
      try {
        await navigator.clipboard.writeText(text.trim());
        const label = btn.querySelector(".copy-label");
        if (!label) return;
        const original = label.textContent;
        label.textContent = "已复制";
        btn.classList.add("text-accent-500");
        setTimeout(() => {
          label.textContent = original;
          btn.classList.remove("text-accent-500");
        }, 1500);
      } catch (err) {
        console.warn("Copy failed", err);
      }
    });
  });

  // 4. Update copyright year if any element wants it (future-proof)
  const yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());
})();
