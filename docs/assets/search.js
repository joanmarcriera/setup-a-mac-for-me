/*
 * Client-side search (search.html).
 *
 * Reads the generated assets/search-index.json (built by scripts/build_search_index.py)
 * and ranks entries by where each query term appears: title > summary > body.
 * Every term must match somewhere for an entry to show.
 *
 * Package and group results link straight to their group on the Homebrew catalogue
 * (homebrew.html#group-<id>) when install-groups.json can be loaded.
 */

(() => {
  "use strict";

  const resultsNode = document.querySelector("[data-search-results]");
  if (!resultsNode) {
    return;
  }

  const countNode = document.querySelector("[data-search-count]");
  const input = document.querySelector("[data-search-page-input]");
  const form = document.querySelector("[data-search-page-form]");

  const KIND_LABELS = {
    page: "Page",
    bundle: "Bundle",
    group: "Group",
    formula: "Formula",
    cask: "Cask"
  };

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  async function loadSearchIndex() {
    const response = await fetch("assets/search-index.json");
    if (!response.ok) {
      throw new Error(`Could not load the search index (HTTP ${response.status}).`);
    }
    return response.json();
  }

  // Redirect stubs (old page URLs) are indexed too; they only say "Moved to ...".
  function isRedirectStub(entry) {
    return entry.kind === "page" && !entry.summary && /\bMoved to\b/.test(entry.body || "");
  }

  function scoreEntry(entry, terms) {
    const title = (entry.title || "").toLowerCase();
    const summary = (entry.summary || "").toLowerCase();
    const body = (entry.body || "").toLowerCase();
    let score = 0;
    for (const term of terms) {
      const inTitle = title.includes(term);
      const inSummary = summary.includes(term);
      const inBody = body.includes(term);
      if (!inTitle && !inSummary && !inBody) {
        return -1;
      }
      score += (inTitle ? 5 : 0) + (inSummary ? 3 : 0) + (inBody ? 1 : 0);
    }
    return score;
  }

  // Map group labels to catalogue anchors, e.g. "Productivity" -> homebrew.html#group-productivity.
  function buildLinker(data) {
    const byLabel = {};
    (data?.groups || []).forEach((group) => {
      byLabel[group.label] = `homebrew.html#group-${group.id}`;
    });
    (data?.bundles || []).forEach((bundle) => {
      byLabel[`bundle:${bundle.label}`] = `homebrew.html#bundle-${bundle.id}`;
    });
    return (entry) => {
      if (entry.kind === "group" && byLabel[entry.title]) {
        return byLabel[entry.title];
      }
      if (entry.kind === "bundle" && byLabel[`bundle:${entry.title}`]) {
        return byLabel[`bundle:${entry.title}`];
      }
      if (entry.kind === "formula" || entry.kind === "cask") {
        const match = /\bin (.+)$/.exec(entry.summary || "");
        if (match && byLabel[match[1]]) {
          return byLabel[match[1]];
        }
      }
      return entry.url;
    };
  }

  function render(results, query, linkFor) {
    if (!query) {
      countNode.textContent = "";
      resultsNode.innerHTML = "";
      return;
    }

    countNode.textContent = `${results.length} result${results.length === 1 ? "" : "s"} for “${query}”`;

    if (!results.length) {
      resultsNode.innerHTML = `
        <li>
          <h2>No matches</h2>
          <p>Try one word, or a Homebrew package name such as <code>keepassxc</code>.</p>
        </li>`;
      return;
    }

    resultsNode.innerHTML = results
      .map(
        (entry) => `
        <li>
          <p class="kind">${escapeHtml(KIND_LABELS[entry.kind] || entry.kind)}</p>
          <h2><a href="${escapeHtml(linkFor(entry))}">${escapeHtml(entry.title.replace(/ \| mac\.riera\.co\.uk$/, ""))}</a></h2>
          <p>${escapeHtml(entry.summary || entry.body || "")}</p>
        </li>`
      )
      .join("");
  }

  async function init() {
    const initialQuery = (new URLSearchParams(window.location.search).get("q") || "").trim();
    if (input) {
      input.value = initialQuery;
    }

    const [entries, data] = await Promise.all([
      loadSearchIndex(),
      window.macSite ? window.macSite.loadInstallData().catch(() => null) : Promise.resolve(null)
    ]);
    // The search page itself only matches because its examples mention package names.
    const searchable = entries.filter((entry) => !isRedirectStub(entry) && entry.url !== "search.html");
    const linkFor = buildLinker(data);

    const run = (query) => {
      const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
      const results = terms.length
        ? searchable
            .map((entry) => ({ entry, score: scoreEntry(entry, terms) }))
            .filter((item) => item.score >= 0)
            .sort((a, b) => b.score - a.score || a.entry.title.localeCompare(b.entry.title))
            .map((item) => item.entry)
        : [];
      render(results, query, linkFor);
    };

    run(initialQuery);

    form?.addEventListener("submit", (event) => {
      event.preventDefault();
      const value = input ? input.value.trim() : "";
      window.history.replaceState({}, "", value ? `search.html?q=${encodeURIComponent(value)}` : "search.html");
      run(value);
    });
  }

  init().catch((error) => {
    console.error(error);
    countNode.textContent = "Search could not load its index. Reload the page to try again.";
  });
})();
