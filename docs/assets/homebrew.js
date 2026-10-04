/*
 * Homebrew catalogue (homebrew.html).
 *
 * Renders every bundle, group and retired entry from assets/install-groups.json.
 * Depends on window.macSite from app.js (both are loaded with `defer`, app.js first).
 * Copy buttons are handled by app.js's delegated click handler.
 */

(() => {
  "use strict";

  const site = window.macSite;
  const bundlesNode = document.querySelector("[data-homebrew='bundles']");
  const groupsNode = document.querySelector("[data-homebrew='groups']");
  const retiredNode = document.querySelector("[data-homebrew='retired']");

  if (!site || !bundlesNode || !groupsNode) {
    return;
  }

  const { escapeHtml, collect, commandLines, commandBlock, countText, noteHtml, BREWFILE_BASE } = site;

  function notesList(notes) {
    if (!notes.length) {
      return "";
    }
    return `<ul class="list tight">${notes.map((note) => `<li>${noteHtml(note)}</li>`).join("")}</ul>`;
  }

  function showError(message) {
    const html = `<li><p class="aside warn">${escapeHtml(message)} The same commands are in <a href="https://github.com/joanmarcriera/setup-a-mac-for-me/blob/main/brew/README.md">brew/README.md</a> on GitHub.</p></li>`;
    bundlesNode.innerHTML = html;
  }

  site
    .loadInstallData()
    .then((data) => {
      const groups = data.groups || [];
      const bundles = data.bundles || [];
      const groupsById = Object.fromEntries(groups.map((group) => [group.id, group]));

      bundlesNode.innerHTML = bundles
        .map((bundle) => {
          const set = collect(bundle.include, groupsById);
          const groupLinks = bundle.include
            .filter((id) => groupsById[id])
            .map((id) => `<a href="#group-${escapeHtml(id)}">${escapeHtml(groupsById[id].label)}</a>`)
            .join(", ");
          return `
            <li id="bundle-${escapeHtml(bundle.id)}">
              <h3>${escapeHtml(bundle.label)}</h3>
              <p>${escapeHtml(bundle.description)} ${escapeHtml(countText(set))}.</p>
              <p class="muted">Groups: ${groupLinks}.</p>
              ${commandBlock(commandLines(set), `${bundle.label} bundle`)}
              ${commandBlock([`curl -fsSL ${BREWFILE_BASE}${bundle.id} | brew bundle --file=-`], `Brewfile.${bundle.id}, re-runnable`)}
            </li>`;
        })
        .join("");

      groupsNode.innerHTML = groups
        .map((group) => {
          const set = collect([group.id], groupsById);
          const inBundles = bundles.filter((b) => b.include.includes(group.id)).map((b) => b.label);
          return `
            <li id="group-${escapeHtml(group.id)}">
              <h3>${escapeHtml(group.label)}</h3>
              <p>${escapeHtml(group.description)} ${escapeHtml(countText(set))}.</p>
              <p class="muted">${inBundles.length ? `In ${escapeHtml(inBundles.join(", "))}.` : "Not in any bundle; install it on its own."}</p>
              ${commandBlock(commandLines(set), `${group.label} group`)}
              ${notesList(group.notes || [])}
            </li>`;
        })
        .join("");

      if (retiredNode) {
        const retired = data.retired || [];
        retiredNode.innerHTML = retired.length
          ? retired
              .map(
                (item) =>
                  `<li><code>${escapeHtml(item.name)}</code> (${escapeHtml(item.kind || "package")}): ${noteHtml(item.reason || "")}</li>`
              )
              .join("")
          : "<li>Nothing has been dropped yet.</li>";
      }

      // Re-apply a deep link such as homebrew.html#group-cli now that the target exists.
      if (window.location.hash) {
        document.getElementById(window.location.hash.slice(1))?.scrollIntoView({ behavior: "instant" });
      }
    })
    .catch((error) => {
      console.error(error);
      showError("The catalogue data did not load.");
    });
})();
