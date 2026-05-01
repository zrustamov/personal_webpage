# Personal Webpage — CI/CD Pipeline

> A production-grade CI/CD pipeline for a static personal website, deployed to **Azure Static Web Apps** via **GitHub Actions** with infrastructure defined as code in **Bicep**.

The site itself is intentionally simple — plain HTML/CSS/JS. The interesting part of this repo is the pipeline around it: branching strategy, automated quality gates, environment promotion, infrastructure as code, manual approval gates, and post-deploy verification.

---

## Table of contents

- [Architecture](#architecture)
- [Branching & promotion model](#branching--promotion-model)
- [Pipeline stages](#pipeline-stages)
- [Repository layout](#repository-layout)
- [Local development](#local-development)
- [One-time setup](#one-time-setup)
- [Pipeline reference](#pipeline-reference)
- [Design decisions](#design-decisions)

---

## Architecture

```mermaid
flowchart TB
    Dev[Developer] -->|push feature branch| GH[GitHub]
    GH -->|PR to develop| CI[CI Workflow]
    CI -->|lint + security + a11y + lighthouse| Quality{Quality gates}
    Quality -->|pass| Preview[PR Preview Env<br/>Azure SWA]
    Quality -->|fail| Block[Block merge]
    Preview --> Review[Code review]
    Review -->|merge| Develop[develop branch]
    Develop --> CDStaging[CD-Staging Workflow]
    CDStaging --> Bicep1[Bicep deploy<br/>staging RG]
    Bicep1 --> StagingSWA[Staging SWA + App Insights]
    StagingSWA --> E2E[Playwright E2E<br/>vs staging URL]
    E2E -->|pass| ReleasePR[Release PR<br/>develop → main]
    ReleasePR --> Approval[Manual approval gate<br/>GitHub Environment]
    Approval --> CDProd[CD-Production Workflow]
    CDProd --> Bicep2[Bicep deploy<br/>production RG]
    Bicep2 --> ProdSWA[Production SWA + App Insights]
    ProdSWA --> Smoke[Smoke tests]
    Smoke --> Health[App Insights health check<br/>5xx error rate < 5%]
    Health -->|pass| Tag[Git release tag]
    Health -->|fail| Rollback[Manual rollback]
```

Two long-lived branches (`develop`, `main`) map 1:1 to two Azure environments. A separate Azure resource group, Static Web App, Log Analytics workspace, and Application Insights instance are provisioned per environment.

---

## Branching & promotion model

| Branch | Environment | Trigger | URL |
|---|---|---|---|
| `feature/*` | Per-PR preview | Open PR to `develop` | `…-{prNumber}.{region}.azurestaticapps.net` |
| `develop` | Staging | Push / merge to `develop` | `swa-zrweb-staging.…azurestaticapps.net` |
| `main` | Production | Merge release PR + manual approval | `swa-zrweb-production.…azurestaticapps.net` |

Branch protection on `develop` and `main`:
- All status checks (lint, security, a11y, lighthouse) must pass
- At least one approving review
- No direct pushes — PR-only
- `main` requires passing E2E run from `develop` (enforced via merge queue / required check)

---

## Pipeline stages

### Continuous Integration ([ci.yml](.github/workflows/ci.yml))

Runs on every PR and push to `develop` / `main`. Five parallel jobs:

| Job | Tool | Purpose |
|---|---|---|
| `lint` | htmlhint, stylelint, eslint | Static analysis of HTML, CSS, JS |
| `security` | gitleaks, npm audit, Trivy | Secret detection, dependency CVEs, filesystem scan; SARIF uploaded to GitHub Security tab |
| `accessibility` | Pa11y CI (WCAG2AA) | A11y compliance on every page |
| `lighthouse` | Lighthouse CI | Perf ≥ 0.85, A11y ≥ 0.9, BP ≥ 0.9, SEO ≥ 0.9 |
| `preview` | Azure SWA | Deploys an isolated preview URL per PR |

### Continuous Delivery — Staging ([cd-staging.yml](.github/workflows/cd-staging.yml))

Runs on push to `develop`. Sequential jobs:

1. **`infrastructure`** — `az bicep build` → `validate` → `what-if` → `deploy` against the staging subscription via OIDC.
2. **`deploy`** — Uploads `src/` to the staging Static Web App.
3. **`e2e`** — Playwright suite (Chromium + Firefox) against the live staging URL.
4. **`report`** — Posts a job summary.

### Continuous Delivery — Production ([cd-production.yml](.github/workflows/cd-production.yml))

Runs on push to `main`. The first job targets a `production-approval` GitHub Environment configured with **Required reviewers** — this is the manual approval gate. Subsequent jobs:

1. **`approval`** — Pause until a reviewer approves.
2. **`infrastructure`** — Bicep validate / what-if / deploy for the production resource group.
3. **`deploy`** — Upload `src/` to production SWA.
4. **`smoke`** — Smoke subset of the Playwright suite (`@smoke` tag).
5. **`health`** — KQL query against Application Insights — fail if 5xx error rate over the last 5 min exceeds 5%.
6. **`tag`** — Tag the release commit with `release-YYYYMMDD-HHMMSS`.

---

## Repository layout

```
personal_webpage/
├── .github/workflows/
│   ├── ci.yml                  # PR + push checks
│   ├── cd-staging.yml          # develop → staging
│   └── cd-production.yml       # main → production (with approval)
├── infrastructure/
│   ├── main.bicep              # subscription-scoped entrypoint
│   ├── modules/
│   │   └── workload.bicep      # SWA + Log Analytics + App Insights
│   └── parameters/
│       ├── staging.bicepparam
│       └── production.bicepparam
├── tests/
│   ├── e2e/                    # Playwright (Chromium + Firefox)
│   │   ├── playwright.config.js
│   │   ├── smoke.spec.js
│   │   └── navigation.spec.js
│   ├── accessibility/
│   │   └── pa11y-ci.json       # WCAG2AA on every page
│   └── lighthouse/
│       └── lighthouserc.json   # Perf / A11y / BP / SEO budgets
├── src/                        # The actual website
│   ├── index.html
│   ├── index-az.html
│   ├── assets/
│   ├── pages/
│   └── staticwebapp.config.json
├── .htmlhintrc
├── .stylelintrc.json
├── eslint.config.js
├── package.json
└── README.md
```

---

## Local development

```bash
# Install all tooling
npm ci

# Serve the site locally on http://localhost:8080
npm run serve

# Run the same checks the CI runs (lint + a11y + lighthouse)
npm run ci

# Individual gates
npm run lint:html
npm run lint:css
npm run lint:js
npm run test:a11y
npm run test:lighthouse
npm run test:e2e
```

---

## One-time setup

### 1. Azure prerequisites

```bash
# Log in with your Azure for Students subscription
az login
az account set --subscription <your-subscription-id>

# Bootstrap each environment by running Bicep manually the first time
# (subsequent updates are driven by the pipeline)
az deployment sub create \
  --location westeurope \
  --template-file infrastructure/main.bicep \
  --parameters infrastructure/parameters/staging.bicepparam

az deployment sub create \
  --location westeurope \
  --template-file infrastructure/main.bicep \
  --parameters infrastructure/parameters/production.bicepparam
```

### 2. Create a federated credential for GitHub Actions (OIDC, no secrets)

```bash
APP_NAME="github-actions-zrweb"
az ad app create --display-name "$APP_NAME"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"

# Grant Contributor over the subscription (or scope it to RGs for least privilege)
SUB_ID=$(az account show --query id -o tsv)
az role assignment create --role Contributor \
  --assignee "$APP_ID" --scope "/subscriptions/$SUB_ID"

# Federated credentials — one per branch that deploys
for BRANCH in develop main; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"github-$BRANCH\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:zrustamov/personal_webpage:ref:refs/heads/$BRANCH\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
done
```

### 3. GitHub repository configuration

**Secrets** (Settings → Secrets and variables → Actions):

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | `$APP_ID` from above |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Your subscription ID |
| `AZURE_STATIC_WEB_APPS_API_TOKEN_STAGING` | Portal → staging SWA → Manage deployment token |
| `AZURE_STATIC_WEB_APPS_API_TOKEN_PRODUCTION` | Portal → production SWA → Manage deployment token |
| `STAGING_BASE_URL` | `https://<staging-swa-default-hostname>` |
| `PRODUCTION_BASE_URL` | `https://<production-swa-default-hostname>` |

**Environments** (Settings → Environments):
- `preview` — no protection
- `staging` — no protection
- `production-approval` — **required reviewers** = you (this is the manual gate)
- `production` — restrict to `main` branch

**Branch protection** (Settings → Branches):
- `develop` — require status checks: `lint`, `security`, `accessibility`, `lighthouse`
- `main` — require status checks + 1 approving review + linear history

---

## Pipeline reference

### Quality budgets enforced

| Check | Threshold | Failure mode |
|---|---|---|
| Lighthouse — Performance | ≥ 0.85 | Warning |
| Lighthouse — Accessibility | ≥ 0.9 | **Block** |
| Lighthouse — Best Practices | ≥ 0.9 | Warning |
| Lighthouse — SEO | ≥ 0.9 | Warning |
| Pa11y — WCAG2AA | 0 violations | **Block** |
| Trivy — CVEs | High / Critical | **Block** |
| npm audit | High / Critical | **Block** |
| Production error rate (App Insights, 5 min post-deploy) | < 5% | **Block & alert** |

### Adding a new page

1. Create the HTML under `src/pages/`.
2. Add the URL to [tests/lighthouse/lighthouserc.json](tests/lighthouse/lighthouserc.json) and [tests/accessibility/pa11y-ci.json](tests/accessibility/pa11y-ci.json) so the page is part of the quality gates.
3. Add a smoke test in [tests/e2e/smoke.spec.js](tests/e2e/smoke.spec.js) if the page is part of the critical user journey.

---

## Design decisions

**Why Azure Static Web Apps over App Service or a VM?**
The site is fully static. SWA gives you global CDN, free SSL, PR preview environments out of the box, and the free tier covers it. App Service would mean paying for a server that does nothing, and a VM would be both more expensive and require OS-level maintenance.

**Why GitHub Actions over Azure DevOps Pipelines?**
The code already lives on GitHub. Keeping CI/CD next to the code reduces context switching and removes the need for a second auth boundary. The Azure SWA action and `azure/login@v2` cover everything the Azure DevOps task ecosystem offers for this scope.

**Why Bicep over Terraform?**
Bicep is Azure-native, has zero state file to manage, and `az deployment what-if` gives a high-fidelity diff before applying. Terraform would be the right call in a multi-cloud setup; here it's just an extra tool to learn.

**Why OIDC instead of a service principal secret?**
Federated credentials mean the pipeline holds **no long-lived Azure secret**. The token is minted at run time, scoped to one workflow run, and verifies against GitHub's OIDC issuer. This is the current Microsoft-recommended pattern.

**Why a separate `production-approval` environment?**
GitHub Environments are the only mechanism that pauses a workflow until a human approves. Splitting the approval gate into its own job (depending on a separate environment) keeps the approval explicit and audit-logged, instead of bundling it with the deploy step.

**Why a 5-minute post-deploy health check?**
Smoke tests confirm that pages load. They don't catch issues that only show up under real traffic (broken third-party CDN reference, regional DNS issue, etc.). The Application Insights query gives traffic-driven evidence the deploy is healthy before the workflow tags the release.

**Why per-environment resource groups?**
Hard isolation. A misconfigured Bicep change can't accidentally rename or delete a production resource because the staging deployment scopes to a different RG. Cost attribution and access control follow the same boundary.
