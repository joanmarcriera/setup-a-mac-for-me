/*
 * mac.riera.co.uk — shared page behaviour (loaded with `defer` on every page).
 *
 * Progressive enhancement only: every page reads fine without this file.
 * With it, pages get:
 *   - copy buttons on command blocks (copies the command lines, never the prompt
 *     glyph or `#` comment lines, because zsh rejects pasted comments by default)
 *   - the rebuild-path progress ticks, saved per browser in localStorage
 *   - the sticky on-page nav: current-section highlight and the mobile toggle
 *   - the bundle chooser rendered from assets/install-groups.json
 *   - the "last reviewed" date from install-groups.json meta
 *
 * Helpers are exposed as window.macSite for homebrew.js and search.js.
 */

(() => {
  "use strict";

  const DATA_URL = "assets/install-groups.json";
  const BREWFILE_BASE =
    "https://raw.githubusercontent.com/joanmarcriera/setup-a-mac-for-me/main/brew/Brewfile.";
  const PROGRESS_KEY = "mac-rebuild-done-v1";
  const BUNDLE_KEY = "mac-rebuild-bundle-v1";

  // ---------- Small helpers ----------

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function unique(items) {
    return [...new Set(items)];
  }

  // localStorage can throw (private mode, blocked storage); never let that break the page.
  function storeGet(key, fallback) {
    try {
      const raw = window.localStorage.getItem(key);
      return raw === null ? fallback : JSON.parse(raw);
    } catch {
      return fallback;
    }
  }

  function storeSet(key, value) {
    try {
      window.localStorage.setItem(key, JSON.stringify(value));
    } catch {
      /* storage unavailable: progress simply is not remembered */
    }
  }

  let dataPromise = null;
  function loadInstallData() {
    if (!dataPromise) {
      dataPromise = fetch(DATA_URL).then((response) => {
        if (!response.ok) {
          throw new Error(`Could not load ${DATA_URL} (HTTP ${response.status}).`);
        }
        return response.json();
      });
    }
    return dataPromise;
  }

  // "2026-10-04" -> "4 October 2026" (parsed as a calendar date, no timezone shift).
  function formatDate(iso) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
    if (!match) {
      return iso || "";
    }
    const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    return date.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
  }

  // mas entries may be bare IDs or {id, name} objects.
  function masEntry(item) {
    return typeof item === "object" && item !== null
      ? { id: String(item.id), name: item.name || String(item.id) }
      : { id: String(item), name: String(item) };
  }

  // Merge a list of group IDs into one de-duplicated install set.
  function collect(groupIds, groupsById) {
    const out = { formulae: [], casks: [], mas: [], taps: [], notes: [] };
    const masSeen = new Set();
    groupIds.forEach((id) => {
      const group = groupsById[id];
      if (!group) {
        return;
      }
      out.formulae.push(...(group.formulae || []));
      out.casks.push(...(group.casks || []));
      out.taps.push(...(group.taps || []));
      out.notes.push(...(group.notes || []));
      (group.mas || []).forEach((item) => {
        const entry = masEntry(item);
        if (!masSeen.has(entry.id)) {
          masSeen.add(entry.id);
          out.mas.push(entry);
        }
      });
    });
    out.formulae = unique(out.formulae);
    out.casks = unique(out.casks);
    out.taps = unique(out.taps);
    out.notes = unique(out.notes);
    return out;
  }

  // Command lines for an install set. Lines starting with "#" are shown but not copied.
  function commandLines(set) {
    const lines = [];
    set.taps.forEach((tap) => lines.push(`brew tap ${tap}`));
    if (set.formulae.length) {
      lines.push(`brew install ${set.formulae.join(" ")}`);
    }
    if (set.casks.length) {
      lines.push(`brew install --cask ${set.casks.join(" ")}`);
    }
    if (set.mas.length) {
      lines.push(`# App Store: ${set.mas.map((m) => m.name).join(", ")}`);
      lines.push(`mas install ${set.mas.map((m) => m.id).join(" ")}`);
    }
    return lines;
  }

  // Browsers wrap after hyphens, which splits package names such as "rectangle-pro"
  // across lines. Wrapping short hyphenated tokens in a no-wrap span keeps names whole;
  // other tokens only break as a last resort (overflow-wrap), so nothing overflows a
  // 390px screen. Copy reads textContent, so the spans never reach the clipboard.
  const WRAP_LIMIT = 28;
  function tokensHtml(line) {
    return line
      .split(" ")
      .map((token) =>
        token.includes("-") && token.length <= WRAP_LIMIT
          ? `<span class="w">${escapeHtml(token)}</span>`
          : escapeHtml(token)
      )
      .join(" ");
  }

  function wrapStaticLines(scope = document) {
    scope.querySelectorAll(".cmd:not(.cmd-file) .ln:not([data-wrapped])").forEach((line) => {
      if (line.children.length) {
        return;
      }
      line.innerHTML = tokensHtml(line.textContent);
      line.dataset.wrapped = "";
    });
  }

  // HTML for a command block. `lines` are plain strings; `label` is the caption.
  function commandBlock(lines, label, extraClass = "") {
    const body = lines
      .map((line) => {
        const comment = line.startsWith("#") ? " c" : "";
        return `<span class="ln${comment}" data-wrapped>${tokensHtml(line)}</span>`;
      })
      .join("");
    return `
      <figure class="cmd ${extraClass}">
        <div class="cmd-bar">
          <figcaption>${escapeHtml(label)}</figcaption>
          <button type="button" class="copy">Copy</button>
        </div>
        <pre><code>${body}</code></pre>
      </figure>`;
  }

  // "53 formulae, 47 casks, 3 App Store apps", leaving out empty kinds.
  function countText(set) {
    const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
    const parts = [];
    if (set.formulae.length) {
      parts.push(plural(set.formulae.length, "formula", "formulae"));
    }
    if (set.casks.length) {
      parts.push(plural(set.casks.length, "cask", "casks"));
    }
    if (set.mas.length) {
      parts.push(plural(set.mas.length, "App Store app", "App Store apps"));
    }
    return parts.join(", ");
  }

  // Escape a note from the data file, then turn `backticks` into <code>.
  function noteHtml(text) {
    return escapeHtml(text).replace(/`([^`]+)`/g, "<code>$1</code>");
  }

  window.macSite = {
    escapeHtml,
    unique,
    loadInstallData,
    formatDate,
    collect,
    commandLines,
    commandBlock,
    countText,
    noteHtml,
    BREWFILE_BASE
  };

  // ---------- Copy buttons (delegated, so rendered blocks work too) ----------

  const liveRegion = document.createElement("p");
  liveRegion.className = "visually-hidden";
  liveRegion.setAttribute("role", "status");
  liveRegion.setAttribute("aria-live", "polite");
  document.body.appendChild(liveRegion);

  function textToCopy(block) {
    const code = block.querySelector("code");
    if (!code) {
      return "";
    }
    const lines = [...code.querySelectorAll(".ln")];
    if (!lines.length) {
      return code.textContent.trim();
    }
    const isFile = block.classList.contains("cmd-file");
    return lines
      .filter((line) => isFile || !line.classList.contains("c"))
      .map((line) => line.textContent)
      .join("\n");
  }

  async function writeClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    // Fallback for file:// previews and older browsers.
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand("copy");
    area.remove();
    if (!ok) {
      throw new Error("Copy command was rejected.");
    }
  }

  document.addEventListener("click", async (event) => {
    const button = event.target.closest(".copy");
    if (!button) {
      return;
    }
    const block = button.closest(".cmd");
    const label = block?.querySelector("figcaption, .cmd-label")?.textContent.trim() || "command";
    try {
      await writeClipboard(textToCopy(block));
      button.textContent = "Copied";
      button.classList.add("is-copied");
      liveRegion.textContent = `Copied: ${label}`;
    } catch {
      button.textContent = "Select and copy";
      liveRegion.textContent = "Copy failed. Select the text and press Command-C.";
    }
    window.clearTimeout(button._reset);
    button._reset = window.setTimeout(() => {
      button.textContent = "Copy";
      button.classList.remove("is-copied");
    }, 1600);
  });

  // ---------- "/" focuses the header search ----------

  window.addEventListener("keydown", (event) => {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) {
      return;
    }
    const active = document.activeElement;
    if (active && (["INPUT", "TEXTAREA", "SELECT"].includes(active.tagName) || active.isContentEditable)) {
      return;
    }
    const input = document.querySelector(".site-search input, [data-search-page-input]");
    if (input) {
      event.preventDefault();
      input.focus();
      input.select();
    }
  });

  // Keep the header search field in step with ?q= on the search page.
  const query = new URLSearchParams(window.location.search).get("q");
  if (query) {
    document.querySelectorAll(".site-search input").forEach((input) => {
      input.value = query;
    });
  }

  // ---------- Rebuild-path progress ----------

  function setupProgress() {
    const steps = [...document.querySelectorAll(".step[id]")];
    if (!steps.length) {
      return;
    }
    const done = new Set(storeGet(PROGRESS_KEY, []));
    const resetButton = document.querySelector("[data-progress-reset]");

    const paint = () => {
      steps.forEach((step) => {
        const isDone = done.has(step.id);
        step.classList.toggle("is-done", isDone);
        const box = step.querySelector("[data-step-done]");
        if (box) {
          box.checked = isDone;
        }
        const link = document.querySelector(`.toc a[href="#${step.id}"]`);
        if (link) {
          link.parentElement.classList.toggle("is-done", isDone);
          const flag = link.querySelector(".done-flag");
          if (flag) {
            flag.textContent = isDone ? " (done)" : "";
          }
        }
      });
      if (resetButton) {
        resetButton.hidden = done.size === 0;
      }
    };

    steps.forEach((step) => {
      const box = step.querySelector("[data-step-done]");
      if (!box) {
        return;
      }
      box.addEventListener("change", () => {
        if (box.checked) {
          done.add(step.id);
        } else {
          done.delete(step.id);
        }
        storeSet(PROGRESS_KEY, [...done]);
        paint();
      });
    });

    if (resetButton) {
      resetButton.addEventListener("click", () => {
        done.clear();
        storeSet(PROGRESS_KEY, []);
        paint();
      });
    }

    paint();
  }

  // ---------- Sticky nav: current section + mobile toggle ----------

  function setupNav() {
    const wrap = document.querySelector(".toc-wrap");
    if (!wrap) {
      return;
    }
    const toggle = wrap.querySelector(".toc-toggle");
    const toggleText = toggle?.querySelector("[data-toc-current]");
    const links = [...wrap.querySelectorAll(".toc a[href^='#']")];
    const targets = links
      .map((link) => document.getElementById(link.getAttribute("href").slice(1)))
      .filter(Boolean);
    const stepCount = document.querySelectorAll(".step[id]").length;

    const setOpen = (open) => {
      wrap.classList.toggle("is-open", open);
      toggle?.setAttribute("aria-expanded", String(open));
    };

    toggle?.addEventListener("click", () => setOpen(!wrap.classList.contains("is-open")));
    links.forEach((link) => link.addEventListener("click", () => setOpen(false)));
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && wrap.classList.contains("is-open")) {
        setOpen(false);
        toggle?.focus();
      }
    });

    const markCurrent = (target) => {
      links.forEach((link) => {
        if (link.getAttribute("href") === `#${target.id}`) {
          link.setAttribute("aria-current", "location");
          if (toggleText) {
            const num = target.dataset.step;
            const text = link.textContent.replace(/\s*\(done\)$/, "").replace(/^\d+/, "").trim();
            toggleText.textContent = num ? `Step ${num} of ${stepCount}: ${text}` : text;
          }
        } else {
          link.removeAttribute("aria-current");
        }
      });
    };

    if (!targets.length) {
      return;
    }

    // The current section is the last target whose top has scrolled above 30% of the
    // viewport. Targets are in document order, so a reverse scan finds it.
    let scheduled = false;
    const update = () => {
      scheduled = false;
      const line = window.innerHeight * 0.3;
      const current = [...targets].reverse().find((target) => target.getBoundingClientRect().top <= line);
      if (current) {
        markCurrent(current);
      } else {
        links.forEach((link) => link.removeAttribute("aria-current"));
        if (toggleText) {
          toggleText.textContent = "Jump to a step";
        }
      }
    };
    window.addEventListener(
      "scroll",
      () => {
        if (!scheduled) {
          scheduled = true;
          window.requestAnimationFrame(update);
        }
      },
      { passive: true }
    );
    update();
  }

  // ---------- Last reviewed ----------

  function paintMeta(data) {
    const meta = data.meta || {};
    if (meta.last_reviewed) {
      document.querySelectorAll("[data-last-reviewed]").forEach((node) => {
        node.textContent = formatDate(meta.last_reviewed);
        node.setAttribute("datetime", meta.last_reviewed);
      });
    }
    if (meta.reviewed_against) {
      document.querySelectorAll("[data-reviewed-against]").forEach((node) => {
        node.textContent = meta.reviewed_against;
        node.closest("[hidden]")?.removeAttribute("hidden");
      });
    }
  }

  // ---------- Bundle chooser (index page) ----------

  function renderChooser(root, data) {
    const groups = data.groups || [];
    const bundles = data.bundles || [];
    if (!bundles.length) {
      return;
    }
    const groupsById = Object.fromEntries(groups.map((group) => [group.id, group]));
    const fallbackId = bundles.some((b) => b.id === "workstation") ? "workstation" : bundles[0].id;
    const defaultId = (data.meta && data.meta.default_bundle) || fallbackId;
    let selected = storeGet(BUNDLE_KEY, defaultId);
    if (!bundles.some((b) => b.id === selected)) {
      selected = defaultId;
    }

    root.innerHTML = `
      <fieldset class="chooser">
        <legend>Choose a bundle (${escapeHtml(bundles.find((b) => b.id === defaultId)?.label || defaultId)} is the default)</legend>
        <div class="segmented">
          ${bundles
            .map(
              (bundle) => `
            <label>
              <input type="radio" name="bundle" value="${escapeHtml(bundle.id)}"${bundle.id === selected ? " checked" : ""}>
              <span>${escapeHtml(bundle.label)}</span>
            </label>`
            )
            .join("")}
        </div>
      </fieldset>
      <div data-bundle-detail aria-live="polite"></div>`;

    const detail = root.querySelector("[data-bundle-detail]");

    const paint = (bundleId) => {
      const bundle = bundles.find((b) => b.id === bundleId);
      const set = collect(bundle.include, groupsById);
      const brewfileUrl = `${BREWFILE_BASE}${bundle.id}`;
      const groupHtml = bundle.include
        .filter((id) => groupsById[id])
        .map((id) => {
          const group = groupsById[id];
          const groupSet = collect([id], groupsById);
          const pkgs = [
            ...groupSet.formulae,
            ...groupSet.casks,
            ...groupSet.mas.map((m) => `${m.name} (App Store)`)
          ];
          const notes = (group.notes || []).map((note) => `<li>${noteHtml(note)}</li>`).join("");
          return `
            <details class="group">
              <summary><strong>${escapeHtml(group.label)}</strong><span class="muted">${escapeHtml(group.description)}</span></summary>
              <div class="group-body">
                <p class="pkgs">${pkgs.map(escapeHtml).join(", ")}</p>
                ${notes ? `<ul class="list tight">${notes}</ul>` : ""}
              </div>
            </details>`;
        })
        .join("");

      detail.innerHTML = `
        <p class="bundle-summary">${escapeHtml(bundle.description)} ${escapeHtml(countText(set))}.</p>
        ${commandBlock(commandLines(set), `${bundle.label} bundle`)}
        ${set.mas.length ? `<p class="aside">The <code>mas install</code> line needs you signed in to the App Store app first, and only installs apps your Apple Account has already got once.</p>` : ""}
        <h3>Or install from the Brewfile</h3>
        <p>Same bundle, but re-runnable: <code>brew bundle</code> skips anything already installed.</p>
        ${commandBlock([`curl -fsSL ${brewfileUrl} | brew bundle --file=-`], `Brewfile.${bundle.id}`)}
        <h3>What is in it</h3>
        <div class="groups">${groupHtml}</div>`;
    };

    root.querySelectorAll("input[name='bundle']").forEach((input) => {
      input.addEventListener("change", () => {
        storeSet(BUNDLE_KEY, input.value);
        paint(input.value);
      });
    });

    paint(selected);
  }

  // ---------- Start ----------

  wrapStaticLines();
  setupProgress();
  setupNav();

  const needsData = document.querySelector("[data-install], [data-last-reviewed], [data-reviewed-against]");
  if (needsData) {
    loadInstallData()
      .then((data) => {
        paintMeta(data);
        const root = document.querySelector("[data-install]");
        if (root) {
          renderChooser(root, data);
        }
      })
      .catch((error) => {
        // The server-rendered fallback stays in place; say why in the console.
        console.error(error);
      });
  }
})();
