// @ts-check
import { test, expect } from "@playwright/test";

test.describe("homepage @smoke", () => {
  test("loads with hero content", async ({ page }) => {
    const response = await page.goto("/index.html");
    expect(response?.status()).toBeLessThan(400);
    await expect(page).toHaveTitle(/Zaid Rustamov/i);
    await expect(page.getByRole("heading", { level: 1 })).toContainText("Zaid Rustamov");
  });

  test("primary nav links resolve", async ({ page }) => {
    await page.goto("/index.html");
    const links = ["CV", "Projects", "Publications", "Talks", "Teaching", "Consulting", "Contact"];
    for (const label of links) {
      const link = page.getByRole("navigation", { name: "Primary" }).getByRole("link", { name: label });
      await expect(link).toBeVisible();
      const href = await link.getAttribute("href");
      expect(href).toBeTruthy();
    }
  });

  test("language toggle reaches az variant", async ({ page }) => {
    await page.goto("/index.html");
    await page.getByRole("link", { name: "AZ" }).click();
    await expect(page).toHaveURL(/index-az\.html$/);
  });
});

test.describe("key pages @smoke", () => {
  for (const path of [
    "/pages/cv.html",
    "/pages/projects.html",
    "/pages/publications.html",
    "/pages/contact.html",
  ]) {
    test(`renders ${path}`, async ({ page }) => {
      const response = await page.goto(path);
      expect(response?.status()).toBeLessThan(400);
      await expect(page.locator("main")).toBeVisible();
    });
  }
});
