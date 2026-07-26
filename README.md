# Weverse stock checker

Checks a Weverse product page every 10 minutes with GitHub Actions. When the
detected state changes from **unavailable** to **available**, it opens a GitHub
Issue and commits the new state to `data/stock-status.json`. GitHub can then
email you its normal notification—no SMTP account or secrets are needed.

## What is included

- `scripts/check_stock.R` fetches the page, detects purchase/sold-out controls,
  and reports a stock transition to the workflow.
- `.github/workflows/check-stock.yml` runs it on a 10-minute GitHub Actions
  schedule, opens an Issue for a restock, and records state changes.

## GitHub setup after pushing

1. Push this project to GitHub and open the repository's **Settings** page.
2. Go to **Settings > Actions > General > Workflow permissions**. Select
   **Read and write permissions**, then save. This allows the workflow to
   commit the small stock-state file. If your default branch is protected, also
   allow GitHub Actions to push to it or use an unprotected branch for this
   checker.
3. Go to **Settings > Secrets and variables > Actions > Variables** and add:

   | Variable | Value |
   | --- | --- |
   | `PRODUCT_URL` | `https://shop.weverse.io/en/shop/USD/artists/2/sales/63225` |

4. On the repository home page, select **Watch > All Activity**. In your GitHub
   notification settings, make sure email notifications are enabled. A detected
   restock opens an Issue, which GitHub notifies you about by email.
5. Open the repository's **Actions** tab, select **Check Weverse stock**, and
   choose **Run workflow**. The log will say whether the page was classified as
   available, unavailable, or unknown. A GitHub Issue is opened only on a
   transition to available.

## Notes

- GitHub schedules are best-effort. The cron expression requests every 10
  minutes, but GitHub can queue a scheduled run later during high load.
- The checker deliberately does not alert when it cannot confidently interpret
  the page. Review the workflow log in that case; Weverse can change its page
  structure or block automated requests.
- This uses GitHub's built-in `GITHUB_TOKEN`; there are no email, API, or other
  personal secrets to configure.
- The script treats visible `Purchase`, `Buy now`, or `Add to cart` controls as
  available and sold-out controls as unavailable. Availability may still depend
  on a selected variant, login, or delivery address.
