const RESOURCE = (window.GetParentResourceName && GetParentResourceName()) || "midnight_firearms";

const app = document.getElementById("app");
const rowsEl = document.getElementById("rows");
const searchEl = document.getElementById("search");
const countPill = document.getElementById("countPill");
const brandTitle = document.getElementById("brandTitle");

const btnClose = document.getElementById("btnClose");
const btnRefresh = document.getElementById("btnRefresh");

let players = [];

function postNui(name, data = {}) {
  return fetch(`https://${RESOURCE}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(data),
  }).then(r => r.json());
}

function badgeFor(p) {
  if (p.allowed) return `<span class="badge good">ALLOWED</span>`;
  return `<span class="badge bad">LOCKED</span>`;
}

function modeText(p) {
  if (!p.mode) return `<span class="small">UNKNOWN</span>`;
  return `<span class="small">${p.mode}</span>`;
}

function overrideText(p) {
  if (p.overrideAllow) return `<span class="badge good">ALLOW</span>`;
  if (p.overrideDeny) return `<span class="badge bad">DENY</span>`;
  return `<span class="badge warn">NONE</span>`;
}

function escapeHtml(str) {
  return String(str ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function render() {
  const q = (searchEl.value || "").toLowerCase().trim();
  const filtered = players.filter(p => {
    const name = (p.name || "").toLowerCase();
    const did = (p.discordId || "").toLowerCase();
    return !q || name.includes(q) || did.includes(q) || String(p.id).includes(q);
  });

  countPill.textContent = `${filtered.length} player${filtered.length === 1 ? "" : "s"}`;

  rowsEl.innerHTML = filtered.map(p => {
    return `
      <tr>
        <td>${escapeHtml(p.id)}</td>
        <td>${escapeHtml(p.name)}</td>
        <td>
          <div>${escapeHtml(p.discordId || "No Discord")}</div>
        </td>
        <td>${badgeFor(p)}</td>
        <td>${modeText(p)}</td>
        <td>${overrideText(p)}</td>
        <td>
          <div class="rowActions">
            <button class="actionBtn allow" data-action="allow" data-discord="${escapeHtml(p.discordId || "")}">Allow</button>
            <button class="actionBtn deny" data-action="deny" data-discord="${escapeHtml(p.discordId || "")}">Deny</button>
            <button class="actionBtn clear" data-action="clear" data-discord="${escapeHtml(p.discordId || "")}">Clear</button>
            <button class="actionBtn" data-action="refreshRole" data-id="${escapeHtml(p.id)}">Refresh Role</button>
          </div>
        </td>
      </tr>
    `;
  }).join("");
}

async function refreshPlayers() {
  const res = await postNui("fetchPlayers");
  if (!res || !res.ok) {
    console.log("fetchPlayers failed", res);
    return;
  }
  players = res.players || [];
  render();
}

rowsEl.addEventListener("click", async (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;

  const action = btn.dataset.action;
  if (action === "refreshRole") {
    const id = Number(btn.dataset.id);
    const res = await postNui("refreshRole", { id });
    if (res && res.ok) await refreshPlayers();
    return;
  }

  const discordId = btn.dataset.discord;
  if (!discordId) return;

  const res = await postNui("applyOverride", { action, discordId });
  if (res && res.ok) await refreshPlayers();
});

btnClose.addEventListener("click", () => postNui("close"));
btnRefresh.addEventListener("click", refreshPlayers);
searchEl.addEventListener("input", render);

window.addEventListener("message", (event) => {
  const msg = event.data;
  if (!msg || msg.type !== "setVisible") return;

  if (msg.brand) brandTitle.textContent = msg.brand;

  if (msg.visible) {
    app.classList.remove("hidden");
    refreshPlayers();
  } else {
    app.classList.add("hidden");
  }
});

// Escape key to close
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") postNui("close");
});