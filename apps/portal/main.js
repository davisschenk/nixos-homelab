const grid = document.querySelector("#app-grid");
const count = document.querySelector("#app-count");
const search = document.querySelector("#search");
const empty = document.querySelector("#empty-state");

const icon = document.createElement("span");
icon.className = "app-icon";
icon.setAttribute("aria-hidden", "true");
icon.innerHTML = "<span></span><span></span><span></span><span></span>";

function card(app) {
  const link = document.createElement("a");
  link.className = "app-card";
  link.href = app.href;

  const top = document.createElement("div");
  top.className = "card-top";
  top.append(icon.cloneNode(true));
  const category = document.createElement("span");
  category.className = "category";
  category.textContent = app.category;
  top.append(category);

  const body = document.createElement("div");
  body.className = "card-body";
  const eyebrow = document.createElement("p");
  eyebrow.className = "card-eyebrow";
  eyebrow.textContent = app.eyebrow;
  const title = document.createElement("h3");
  title.textContent = app.name;
  const description = document.createElement("p");
  description.className = "card-description";
  description.textContent = app.description;
  body.append(eyebrow, title, description);

  const bottom = document.createElement("div");
  bottom.className = "card-bottom";
  bottom.innerHTML =
    '<span>Open app</span><span class="card-arrow" aria-hidden="true">↗</span>';
  link.append(top, body, bottom);
  return link;
}

function render(apps, query = "") {
  const needle = query.trim().toLowerCase();
  const visible = apps.filter((app) =>
    [app.name, app.category, app.description, app.eyebrow].some((value) =>
      value.toLowerCase().includes(needle),
    ),
  );
  grid.replaceChildren(...visible.map(card));
  empty.hidden = visible.length !== 0;
}

try {
  const response = await fetch("/apps.json");
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const apps = await response.json();
  if (!Array.isArray(apps)) throw new Error("Invalid app library");
  count.textContent = String(apps.length).padStart(2, "0");
  render(apps);
  search.addEventListener("input", () => render(apps, search.value));
  document.addEventListener("keydown", (event) => {
    if (event.key === "/" && document.activeElement !== search) {
      event.preventDefault();
      search.focus();
    }
  });
} catch {
  empty.hidden = false;
  empty.textContent = "The app library could not load. Refresh to try again.";
}
