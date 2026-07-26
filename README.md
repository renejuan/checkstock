# Weverse stock checker

Checks a Weverse product page every 10 minutes with GitHub Actions. When the
detected state changes from **unavailable** to **available**, it sends one email
and commits the new state to `data/stock-status.json`. It will not send repeat
emails while the item remains available. Once it is unavailable again, a later
restock can trigger a new alert.

## What is included

- `scripts/check_stock.R` fetches the page, detects purchase/sold-out controls,
  and sends SMTP email using R.
- `.github/workflows/check-stock.yml` runs it on a 10-minute GitHub Actions
  schedule and records state changes.

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

4. In **Settings > Secrets and variables > Actions > Secrets**, add the six
   secrets below. Do not put any of these values in the repository.

   | Secret | Example / purpose |
   | --- | --- |
   | `SMTP_HOST` | `smtp.gmail.com` |
   | `SMTP_PORT` | `465` for Gmail SSL |
   | `SMTP_USERNAME` | Your sending email address |
   | `SMTP_PASSWORD` | Your SMTP password (for Gmail, an app password) |
   | `EMAIL_FROM` | Your sending email address |
   | `EMAIL_TO` | The address that should receive the alert |

5. For Gmail, enable two-step verification on the sending Google account, then
   create a Google **App Password** and use that 16-character value as
   `SMTP_PASSWORD`. Do not use your normal Google password.
6. Open the repository's **Actions** tab, select **Check Weverse stock**, and
   choose **Run workflow**. Check **Send a test email** and run it to verify
   your email settings without changing stock state. Then run it normally; its
   log will say whether the page was classified as available, unavailable, or
   unknown. A real alert is sent only on a transition to available.

## Notes

- GitHub schedules are best-effort. The cron expression requests every 10
  minutes, but GitHub can queue a scheduled run later during high load.
- The checker deliberately does not alert when it cannot confidently interpret
  the page. Review the workflow log in that case; Weverse can change its page
  structure or block automated requests.
- The script treats visible `Purchase`, `Buy now`, or `Add to cart` controls as
  available and sold-out controls as unavailable. Availability may still depend
  on a selected variant, login, or delivery address.
