const fileFromPath = (value) => {
  const clean = (value || "").split("?")[0].split("#")[0];
  const part = clean.split("/").pop();
  return part || "index.html";
};

const pathFile = fileFromPath(window.location.pathname);
for (const link of document.querySelectorAll("nav a")) {
  const href = link.getAttribute("href");
  if (!href || href.startsWith("#")) continue;
  const targetFile = fileFromPath(href);
  if (targetFile === pathFile) link.classList.add("active");
}
