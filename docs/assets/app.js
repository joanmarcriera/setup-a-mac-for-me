const sitePages = [
  { id: "index", label: "Overview", href: "index.html" },
  { id: "homebrew", label: "Homebrew", href: "homebrew.html" },
  { id: "macos-defaults", label: "macOS Defaults", href: "macos-defaults.html" },
  { id: "browser", label: "Browser", href: "browser.html" },
  { id: "terminal", label: "Terminal", href: "terminal.html" },
  { id: "coding", label: "Coding", href: "coding.html" },
  { id: "apps", label: "Apps", href: "apps.html" },
  { id: "backup", label: "Backup", href: "backup.html" },
  { id: "audit", label: "Audit", href: "audit.html" },
  { id: "restore-state", label: "Restore State", href: "restore-state.html" },
  { id: "post-install", label: "Post-Install", href: "post-install.html" }
];

async function loadInstallData() {
  const response = await fetch("assets/install-groups.json");
  if (!response.ok) {
    throw new Error("Failed to load install groups.");
  }
  return response.json();
}

function renderShell() {
  const currentPage = document.body.dataset.page || "index";
  const header = document.querySelector('[data-site-shell="header"]');
  const footer = document.querySelector('[data-site-shell="footer"]');

  if (header) {
    header.innerHTML = `
      <header class="site-header">
        <div class="site-header-inner">
          <a class="brand" href="index.html" aria-label="Go to site overview">
            <span class="brand-mark">MR</span>
            <span class="brand-copy">
              <strong>mac.riera.co.uk</strong>
              <span>Opinionated MacBook Pro rebuild notes</span>
            </span>
          </a>
          <nav class="main-nav" aria-label="Primary">
            ${sitePages
              .map(
                (page) => `
                  <a href="${page.href}" class="${page.id === currentPage ? "is-active" : ""}">
                    ${page.label}
                  </a>
                `
              )
              .join("")}
          </nav>
          <form class="site-search" data-site-search>
            <input
              type="search"
              name="q"
              placeholder="Search pages, packages, notes"
              aria-label="Search the site"
              data-site-search-input
            >
            <button type="submit">Search</button>
          </form>
        </div>
      </header>
    `;
  }

  if (footer) {
    footer.innerHTML = `
      <footer class="footer">
        <p>
          Built from <code>data/install-groups.json</code> so the site, scripts, and Brewfiles stay aligned.
        </p>
      </footer>
    `;
  }
}

function updateMetrics(data) {
  const groups = data.groups || [];
  const bundles = data.bundles || [];
  const formulae = new Set();
  const casks = new Set();

  groups.forEach((group) => {
    group.formulae.forEach((item) => formulae.add(item));
    group.casks.forEach((item) => casks.add(item));
  });

  const values = {
    "formula-total": String(formulae.size),
    "cask-total": String(casks.size),
    "bundle-total": String(bundles.length)
  };

  document.querySelectorAll("[data-metric]").forEach((node) => {
    const metric = node.dataset.metric;
    if (metric && values[metric]) {
      node.textContent = values[metric];
    }
  });
}

function setupCopyButtons() {
  document.querySelectorAll("[data-copy-text]").forEach((button) => {
    button.addEventListener("click", async () => {
      const value = button.dataset.copyText || "";
      await navigator.clipboard.writeText(value);
      const original = button.textContent;
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = original;
      }, 1200);
    });
  });
}

function setupSiteSearch() {
  const query = new URLSearchParams(window.location.search).get("q") || "";

  document.querySelectorAll("[data-site-search-input]").forEach((input) => {
    input.value = query;
  });

  document.querySelectorAll("[data-site-search]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const input = form.querySelector("[data-site-search-input]");
      const value = input ? input.value.trim() : "";
      const target = value ? `search.html?q=${encodeURIComponent(value)}` : "search.html";
      window.location.href = target;
    });
  });

  window.addEventListener("keydown", (event) => {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) {
      return;
    }

    const active = document.activeElement;
    if (active && ["INPUT", "TEXTAREA"].includes(active.tagName)) {
      return;
    }

    const input = document.querySelector("[data-site-search-input]");
    if (input instanceof HTMLInputElement) {
      event.preventDefault();
      input.focus();
      input.select();
    }
  });
}

async function start() {
  renderShell();
  setupCopyButtons();
  setupSiteSearch();

  try {
    const data = await loadInstallData();
    updateMetrics(data);
  } catch (error) {
    console.error(error);
  }

  requestAnimationFrame(() => {
    document.body.classList.add("is-ready");
  });
}

start();
