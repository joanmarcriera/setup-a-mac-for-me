async function loadSearchIndex() {
  const response = await fetch("assets/search-index.json");
  if (!response.ok) {
    throw new Error("Unable to load the site search index.");
  }
  return response.json();
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function normalize(text) {
  return text.toLowerCase();
}

function scoreEntry(entry, terms) {
  const title = normalize(entry.title || "");
  const summary = normalize(entry.summary || "");
  const body = normalize(entry.body || "");
  const combined = `${title} ${summary} ${body}`;

  let score = 0;

  for (const term of terms) {
    if (!combined.includes(term)) {
      return -1;
    }
    if (title.includes(term)) {
      score += 5;
    }
    if (summary.includes(term)) {
      score += 3;
    }
    if (body.includes(term)) {
      score += 1;
    }
  }

  return score;
}

function renderResults(results, query, container, countNode) {
  countNode.textContent = query
    ? `${results.length} result${results.length === 1 ? "" : "s"} for “${query}”`
    : "Type a search query to scan the site.";

  if (!query) {
    container.innerHTML = `
      <article class="search-empty">
        <h2>Search suggestions</h2>
        <p>Try package names like <code>mailmate</code>, <code>kopia</code>, <code>keepassxc</code>, or page topics like <code>backup</code> and <code>keyboard maestro</code>.</p>
      </article>
    `;
    return;
  }

  if (results.length === 0) {
    container.innerHTML = `
      <article class="search-empty">
        <h2>No matches</h2>
        <p>Try a broader query or search for a Homebrew package name rather than a full sentence.</p>
      </article>
    `;
    return;
  }

  container.innerHTML = results
    .map(
      (entry) => `
        <article class="search-card">
          <div class="pill-row">
            <span class="badge badge-accent">${escapeHtml(entry.kind)}</span>
          </div>
          <h2><a href="${escapeHtml(entry.url)}">${escapeHtml(entry.title)}</a></h2>
          <p>${escapeHtml(entry.summary || entry.body || "")}</p>
        </article>
      `
    )
    .join("");
}

async function initSearchPage() {
  const resultsNode = document.querySelector("[data-search-results]");
  if (!resultsNode) {
    return;
  }

  const countNode = document.querySelector("[data-search-count]");
  const input = document.querySelector("[data-search-page-input]");
  const form = document.querySelector("[data-search-page-form]");
  const params = new URLSearchParams(window.location.search);
  const initialQuery = (params.get("q") || "").trim();

  if (input instanceof HTMLInputElement) {
    input.value = initialQuery;
  }

  const entries = await loadSearchIndex();

  const runSearch = (query) => {
    const normalizedQuery = query.trim();
    const terms = normalizedQuery.toLowerCase().split(/\s+/).filter(Boolean);

    const results = terms.length
      ? entries
          .map((entry) => ({ entry, score: scoreEntry(entry, terms) }))
          .filter((item) => item.score >= 0)
          .sort((left, right) => right.score - left.score || left.entry.title.localeCompare(right.entry.title))
          .map((item) => item.entry)
      : [];

    renderResults(results, normalizedQuery, resultsNode, countNode);
  };

  runSearch(initialQuery);

  if (form) {
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const value = input instanceof HTMLInputElement ? input.value.trim() : "";
      const next = value ? `?q=${encodeURIComponent(value)}` : "";
      window.history.replaceState({}, "", `search.html${next}`);
      runSearch(value);
    });
  }
}

initSearchPage().catch((error) => {
  console.error(error);
});
