function unique(items) {
  return [...new Set(items)];
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

function brewCommands(formulae, casks) {
  const commands = [];

  if (formulae.length > 0) {
    commands.push(`brew install ${formulae.join(" ")}`);
  }

  if (casks.length > 0) {
    commands.push(`brew install --cask ${casks.join(" ")}`);
  }

  return commands;
}

function renderRows(items) {
  return items
    .map((item) => {
      const commandText = brewCommands(item.formulae, item.casks).join("\n");
      const included = item.includeLabels ? item.includeLabels.join(", ") : item.packageSummary;

      return `
        <tr>
          <td>
            <strong>${item.label}</strong>
            <div class="muted">${item.description}</div>
          </td>
          <td>${included}</td>
          <td>
            <div class="command-stack">
              <button type="button" class="button button-subtle" data-copy-value="${encodeURIComponent(commandText)}">Copy</button>
              <pre>${commandText}</pre>
            </div>
          </td>
        </tr>
      `;
    })
    .join("");
}

async function initHomebrewPage() {
  const bundlesBody = document.querySelector("[data-homebrew='bundles']");
  const groupsBody = document.querySelector("[data-homebrew='groups']");
  const notesNode = document.querySelector("[data-homebrew='notes']");

  if (!bundlesBody || !groupsBody || !notesNode) {
    return;
  }

  const response = await fetch("assets/install-groups.json");
  if (!response.ok) {
    throw new Error("Unable to load Homebrew data.");
  }

  const data = await response.json();
  const groups = data.groups || [];
  const bundles = data.bundles || [];
  const groupsById = Object.fromEntries(groups.map((group) => [group.id, group]));

  const bundleRows = bundles.map((bundle) => {
    const items = collectItems(bundle.include, groupsById);
    return {
      label: bundle.label,
      description: bundle.description,
      includeLabels: bundle.include.map((groupId) => groupsById[groupId].label),
      formulae: items.formulae,
      casks: items.casks
    };
  });

  const groupRows = groups.map((group) => ({
    label: group.label,
    description: group.description,
    packageSummary: `${group.formulae.length} formulae, ${group.casks.length} casks`,
    formulae: group.formulae,
    casks: group.casks
  }));

  const notes = unique(groups.flatMap((group) => group.notes || []));

  bundlesBody.innerHTML = renderRows(bundleRows);
  groupsBody.innerHTML = renderRows(groupRows);
  notesNode.innerHTML = `<ul class="stacked-list">${notes.map((note) => `<li>${note}</li>`).join("")}</ul>`;

  document.querySelectorAll("[data-copy-value]").forEach((button) => {
    button.addEventListener("click", async () => {
      const value = decodeURIComponent(button.dataset.copyValue || "");
      await navigator.clipboard.writeText(value);
      const original = button.textContent;
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = original;
      }, 1200);
    });
  });
}

initHomebrewPage().catch((error) => {
  console.error(error);
});
