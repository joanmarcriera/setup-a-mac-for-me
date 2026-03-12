function unique(items) {
  return [...new Set(items)];
}

function arraysEqual(left, right) {
  if (left.length !== right.length) {
    return false;
  }
  return left.every((value, index) => value === right[index]);
}

function orderGroupIds(selectedIds, groups) {
  const groupOrder = groups.map((group) => group.id);
  return [...selectedIds].sort((a, b) => groupOrder.indexOf(a) - groupOrder.indexOf(b));
}

function collectItems(groupIds, groupsById) {
  const formulae = [];
  const casks = [];
  const notes = [];

  groupIds.forEach((groupId) => {
    const group = groupsById[groupId];
    formulae.push(...group.formulae);
    casks.push(...group.casks);
    notes.push(...(group.notes || []));
  });

  return {
    formulae: unique(formulae),
    casks: unique(casks),
    notes: unique(notes)
  };
}

function matchingBundle(selectedIds, bundles, groups) {
  const ordered = orderGroupIds(selectedIds, groups);
  return (
    bundles.find((bundle) =>
      arraysEqual(ordered, orderGroupIds(bundle.include, groups))
    ) || null
  );
}

async function loadHomebrewData() {
  const response = await fetch("assets/install-groups.json");
  if (!response.ok) {
    throw new Error("Unable to load Homebrew data.");
  }
  return response.json();
}

async function initInstaller() {
  const root = document.getElementById("homebrew-installer");
  if (!root) {
    return;
  }

  const data = await loadHomebrewData();
  const groups = data.groups;
  const bundles = data.bundles;
  const groupsById = Object.fromEntries(groups.map((group) => [group.id, group]));

  const state = {
    selectedGroups: new Set((bundles.find((bundle) => bundle.id === "workstation") || bundles[0]).include),
    outputMode: "bundle"
  };

  const presetGrid = root.querySelector("[data-installer='presets']");
  const groupGrid = root.querySelector("[data-installer='groups']");
  const outputNode = root.querySelector("[data-installer='output']");
  const copyButton = root.querySelector("[data-installer='copy']");
  const resetButton = root.querySelector("[data-installer='reset']");
  const modeButtons = root.querySelectorAll("[data-output-mode]");
  const matchNode = root.querySelector("[data-installer='match']");
  const badgeNode = root.querySelector("[data-installer='badges']");
  const notesNode = root.querySelector("[data-installer='notes']");
  const breakdownNode = root.querySelector("[data-installer='breakdown']");
  const formulaCount = root.querySelector("[data-installer='formulae']");
  const caskCount = root.querySelector("[data-installer='casks']");
  const groupCount = root.querySelector("[data-installer='group-count']");

  const render = () => {
    const selectedIds = orderGroupIds(state.selectedGroups, groups);
    const bundle = matchingBundle(selectedIds, bundles, groups);
    const items = collectItems(selectedIds, groupsById);

    presetGrid.innerHTML = bundles
      .map((preset) => {
        const includedItems = collectItems(preset.include, groupsById);
        const selectedClass = bundle && bundle.id === preset.id ? "is-selected" : "";
        return `
          <button type="button" class="option-card ${selectedClass}" data-preset="${preset.id}">
            <header>
              <div>
                <h3>${preset.label}</h3>
                <small>${preset.description}</small>
              </div>
              <span class="badge badge-accent">${preset.include.length} groups</span>
            </header>
            <div class="pill-row">
              <span class="badge">${includedItems.formulae.length} formulae</span>
              <span class="badge">${includedItems.casks.length} casks</span>
            </div>
          </button>
        `;
      })
      .join("");

    groupGrid.innerHTML = groups
      .map((group) => {
        const selected = state.selectedGroups.has(group.id);
        return `
          <button type="button" class="toggle-card ${selected ? "is-selected" : ""}" data-group="${group.id}">
            <header>
              <div>
                <h3>${group.label}</h3>
                <small>${group.description}</small>
              </div>
              <span class="badge badge-forest">${selected ? "Included" : "Optional"}</span>
            </header>
            <div class="pill-row">
              <span class="badge">${group.formulae.length} formulae</span>
              <span class="badge">${group.casks.length} casks</span>
            </div>
          </button>
        `;
      })
      .join("");

    modeButtons.forEach((button) => {
      button.classList.toggle("button-subtle", button.dataset.outputMode !== state.outputMode);
    });

    let output = "# Select at least one group.";
    if (selectedIds.length > 0) {
      if (state.outputMode === "bundle") {
        output = bundle
          ? `brew bundle --file brew/Brewfile.${bundle.id}`
          : selectedIds.map((groupId) => `brew bundle --file brew/Brewfile.${groupId}`).join("\n");
      } else {
        const commands = [];
        if (items.formulae.length > 0) {
          commands.push(`brew install ${items.formulae.join(" ")}`);
        }
        if (items.casks.length > 0) {
          commands.push(`brew install --cask ${items.casks.join(" ")}`);
        }
        output = commands.join("\n\n");
      }
    }

    outputNode.textContent = output;
    copyButton.dataset.copyValue = output;
    copyButton.disabled = selectedIds.length === 0;

    matchNode.textContent = bundle
      ? `Exact preset match: ${bundle.label}`
      : "Custom selection using grouped install slices.";

    badgeNode.innerHTML = selectedIds
      .map((groupId) => `<span class="badge">${groupsById[groupId].label}</span>`)
      .join("");

    notesNode.innerHTML = items.notes.length
      ? `<ul class="stacked-list">${items.notes.map((note) => `<li>${note}</li>`).join("")}</ul>`
      : `<p class="muted">No extra notes for the current selection.</p>`;

    breakdownNode.innerHTML = selectedIds
      .map((groupId) => {
        const group = groupsById[groupId];
        return `
          <article class="card">
            <h3>${group.label}</h3>
            <p>${group.description}</p>
            <div class="list-inline">
              ${group.formulae.map((item) => `<span>${item}</span>`).join("")}
              ${group.casks.map((item) => `<span>${item}</span>`).join("")}
            </div>
          </article>
        `;
      })
      .join("");

    formulaCount.textContent = String(items.formulae.length);
    caskCount.textContent = String(items.casks.length);
    groupCount.textContent = String(selectedIds.length);

    presetGrid.querySelectorAll("[data-preset]").forEach((button) => {
      button.addEventListener("click", () => {
        const preset = bundles.find((entry) => entry.id === button.dataset.preset);
        state.selectedGroups = new Set(preset.include);
        render();
      });
    });

    groupGrid.querySelectorAll("[data-group]").forEach((button) => {
      button.addEventListener("click", () => {
        const groupId = button.dataset.group;
        if (state.selectedGroups.has(groupId)) {
          state.selectedGroups.delete(groupId);
        } else {
          state.selectedGroups.add(groupId);
        }
        render();
      });
    });
  };

  modeButtons.forEach((button) => {
    button.addEventListener("click", () => {
      state.outputMode = button.dataset.outputMode;
      render();
    });
  });

  copyButton.addEventListener("click", async () => {
    const value = copyButton.dataset.copyValue || "";
    await navigator.clipboard.writeText(value);
    const original = copyButton.textContent;
    copyButton.textContent = "Copied";
    window.setTimeout(() => {
      copyButton.textContent = original;
    }, 1200);
  });

  resetButton.addEventListener("click", () => {
    state.selectedGroups = new Set((bundles.find((bundle) => bundle.id === "workstation") || bundles[0]).include);
    state.outputMode = "bundle";
    render();
  });

  render();
}

initInstaller().catch((error) => {
  console.error(error);
});
