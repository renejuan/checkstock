#!/usr/bin/env Rscript

# Checks one Weverse product page and emails only when its stock state changes
# from unavailable to available. The state file is committed by GitHub Actions.

default_url <- "https://shop.weverse.io/en/shop/USD/artists/2/sales/63225"
product_url <- Sys.getenv("PRODUCT_URL", unset = default_url)
if (!nzchar(product_url)) product_url <- default_url

state_path <- file.path("data", "stock-status.json")
dir.create(dirname(state_path), recursive = TRUE, showWarnings = FALSE)

read_state <- function(path) {
  if (!file.exists(path)) return(list(state = "unavailable"))
  tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) {
    stop("Cannot read ", path, ": ", conditionMessage(e))
  })
}

normalise <- function(x) {
  x <- enc2utf8(x)
  trimws(gsub("\\s+", " ", x))
}

check_product <- function(url) {
  response <- httr2::request(url) |>
    httr2::req_user_agent("Mozilla/5.0 (compatible; personal-stock-checker/1.0)") |>
    httr2::req_timeout(30) |>
    httr2::req_follow_location() |>
    httr2::req_perform()

  if (httr2::resp_status(response) != 200) {
    stop("Weverse returned HTTP ", httr2::resp_status(response))
  }

  page <- httr2::resp_body_html(response)
  controls <- rvest::html_elements(page, "button, [role='button']")
  control_text <- toupper(normalise(rvest::html_text2(controls)))
  control_text <- control_text[nzchar(control_text)]

  buy_pattern <- "ADD TO CART|PURCHASE|BUY NOW"
  sold_pattern <- "SOLD OUT|OUT OF STOCK|NOT AVAILABLE|COMING SOON"
  buy_controls <- control_text[grepl(buy_pattern, control_text, perl = TRUE)]
  sold_controls <- control_text[grepl(sold_pattern, control_text, perl = TRUE)]

  # Buttons are preferred over page text: product descriptions can legitimately
  # contain phrases such as "sold out" even when the current item is purchasable.
  if (length(buy_controls) > 0) {
    return(list(state = "available", evidence = paste(buy_controls, collapse = " | ")))
  }
  if (length(sold_controls) > 0) {
    return(list(state = "unavailable", evidence = paste(sold_controls, collapse = " | ")))
  }

  body_text <- toupper(normalise(rvest::html_text2(page)))
  if (grepl(sold_pattern, body_text, perl = TRUE)) {
    return(list(state = "unavailable", evidence = "unavailable wording in page text"))
  }
  list(state = "unknown", evidence = "No purchase or stock-status control was found")
}

required_env <- function(name) {
  value <- Sys.getenv(name)
  if (!nzchar(value)) stop("Missing required environment variable: ", name)
  value
}

send_notice <- function(url, evidence,
                        subject = "Weverse stock alert: item may be available",
                        heading = "Weverse item appears to be in stock") {
  smtp_port <- suppressWarnings(as.integer(required_env("SMTP_PORT")))
  if (is.na(smtp_port)) stop("SMTP_PORT must be a number")

  email <- blastula::compose_email(
    body = blastula::md(paste0(
      "# ", heading, "\\n\\n",
      "[Open the product page](", url, ")\\n\\n",
      "Detection evidence: `", evidence, "`"
    ))
  )
  blastula::smtp_send(
    email = email,
    from = required_env("EMAIL_FROM"),
    to = required_env("EMAIL_TO"),
    subject = subject,
    credentials = blastula::creds(
      username = required_env("SMTP_USERNAME"),
      password = required_env("SMTP_PASSWORD")
    ),
    host = required_env("SMTP_HOST"),
    port = smtp_port,
    use_ssl = identical(smtp_port, 465)
  )
}

if (identical(tolower(Sys.getenv("SEND_TEST_EMAIL")), "true")) {
  send_notice(
    product_url,
    "This is a configuration test; no stock state was changed.",
    subject = "Weverse stock checker: test email",
    heading = "Weverse stock checker test"
  )
  message("Test email sent. Stock was not checked or saved.")
  quit(status = 0)
}

previous <- read_state(state_path)
checked_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
result <- tryCatch(check_product(product_url), error = function(e) {
  list(state = "unknown", evidence = conditionMessage(e))
})

message("Checked: ", product_url)
message("Result: ", result$state, " (", result$evidence, ")")

if (identical(result$state, "unknown")) {
  message("Stock state was not changed because the page could not be classified.")
  quit(status = 0)
}

changed <- !identical(result$state, previous$state)
if (identical(result$state, "available") && changed) {
  send_notice(product_url, result$evidence)
  message("Availability email sent.")
}

if (changed) {
  next_state <- list(
    state = result$state,
    last_changed_at = checked_at,
    last_evidence = result$evidence,
    product_url = product_url
  )
  jsonlite::write_json(next_state, state_path, auto_unbox = TRUE, pretty = TRUE)
  message("Stock state changed and was saved.")
} else {
  message("Stock state is unchanged; no email sent.")
}
