#!/usr/bin/env Rscript

# Checks one Weverse product page and exposes an availability transition to
# GitHub Actions. The workflow then creates a GitHub Issue as the alert.

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

set_action_output <- function(name, value) {
  output_file <- Sys.getenv("GITHUB_OUTPUT")
  if (nzchar(output_file)) cat(name, "=", value, "\n", sep = "", file = output_file, append = TRUE)
}

previous <- read_state(state_path)
checked_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
result <- tryCatch(check_product(product_url), error = function(e) {
  list(state = "unknown", evidence = conditionMessage(e))
})

message("Checked: ", product_url)
message("Result: ", result$state, " (", result$evidence, ")")

if (identical(result$state, "unknown")) {
  set_action_output("available_transition", "false")
  message("Stock state was not changed because the page could not be classified.")
  quit(status = 0)
}

changed <- !identical(result$state, previous$state)
available_transition <- identical(result$state, "available") && changed
set_action_output("available_transition", tolower(as.character(available_transition)))

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
  message("Stock state is unchanged; no alert is needed.")
}
