const fileFromPath = (value) => {
  const clean = (value || "").split("?")[0].split("#")[0];
  const part = clean.split("/").pop();
  return part || "index.html";
};

const currentFile = fileFromPath(window.location.pathname);

for (const link of document.querySelectorAll(".primary-nav a")) {
  if (link.classList.contains("lang-toggle")) continue;
  const href = link.getAttribute("href");
  if (!href || href.startsWith("#")) continue;
  if (fileFromPath(href) === currentFile) link.classList.add("active");
}

for (const img of document.querySelectorAll("img[data-fallback]")) {
  img.addEventListener(
    "error",
    () => {
      const fallback = img.getAttribute("data-fallback");
      if (fallback && img.src !== fallback) img.src = fallback;
    },
    { once: true },
  );
}

const filterRoot = document.querySelector("[data-filter-group]");
if (filterRoot) {
  const buttons = filterRoot.querySelectorAll("[data-filter]");
  const items = document.querySelectorAll("[data-tags]");
  buttons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const tag = btn.getAttribute("data-filter");
      buttons.forEach((b) => b.classList.toggle("active", b === btn));
      items.forEach((item) => {
        const tags = (item.getAttribute("data-tags") || "").split(/\s+/);
        item.style.display = tag === "all" || tags.includes(tag) ? "" : "none";
      });
    });
  });
}
