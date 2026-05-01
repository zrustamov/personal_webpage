// @ts-check
import { test, expect } from "@playwright/test";

test("contact page exposes email link", async ({ page }) => {
  await page.goto("/pages/contact.html");
  const mailto = page.locator('a[href^="mailto:"]').first();
  await expect(mailto).toBeVisible();
  const href = await mailto.getAttribute("href");
  expect(href).toMatch(/^mailto:.+@.+/);
});

test("cv page lists positions", async ({ page }) => {
  await page.goto("/pages/cv.html");
  await expect(page.locator("main")).toContainText(/MegaSec|ADA/i);
});

test("no broken assets on homepage", async ({ page, baseURL }) => {
  const failed = [];
  page.on("response", (response) => {
    if (response.status() >= 400 && baseURL && response.url().startsWith(baseURL)) {
      failed.push(`${response.status()} ${response.url()}`);
    }
  });
  await page.goto("/index.html", { waitUntil: "networkidle" });
  expect(failed, failed.join("\n")).toEqual([]);
});
