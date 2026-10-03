test_that("input validation rejects bad codes, duplicates and negatives", {
  ok <- tibble::tibble(municipality_code = c(1100015, 1100023), branches = c(1, 0))
  expect_silent(validate_a2_input(ok, "banking"))
  expect_error(validate_a2_input(ok[, "municipality_code"], "banking"), "missing columns")
  bad <- ok; bad$municipality_code[2] <- 11
  expect_error(validate_a2_input(bad, "banking"), "7-digit")
  dup <- ok; dup$municipality_code[2] <- dup$municipality_code[1]
  expect_error(validate_a2_input(dup, "banking"), "duplicated")
  neg <- ok; neg$branches[1] <- -1
  expect_error(validate_a2_input(neg, "banking"), "negative")
})

test_that("stable MT codes are merged, excluded dropped, NA never becomes zero", {
  pop <- tibble::tibble(
    municipality_code = c(5101837L, 5106240L, 5107925L, 2401305L, 1100015L),
    population_total = c(10, 20, 30, 99, NA), population_adult = c(8, 16, 24, 90, NA)
  )
  out <- aggregate_to_stable(pop, test_rules(), c("population_total", "population_adult"))
  expect_equal(nrow(out), 2L)
  expect_equal(out$population_adult[out$stable_municipality_id == "MT_STABLE"], 48)
  expect_true(is.na(out$population_adult[out$stable_municipality_id == "1100015"]))
  expect_false("2401305" %in% out$stable_municipality_id)
})

test_that("adoption keeps NA denominators and audit flags ratios above one", {
  panel <- tibble::tibble(
    stable_municipality_id = rep(c("A", "B", "C"), each = 2),
    month = rep(as.Date(c("2021-01-01", "2021-02-01")), 3),
    QT_PES_PagadorPF = c(5, 6, 30, 12, 4, 4)
  )
  pop <- tibble::tibble(
    municipality_code = c(1100015L, 1100023L), population_total = c(20, 20), population_adult = c(10, 10)
  )
  panel$stable_municipality_id <- rep(c("1100015", "1100023", "9999999"), each = 2)
  adoption <- build_adoption_outcome(panel, pop, test_rules(), test_a2_config())
  expect_true(all(is.na(adoption$adoption_rate[adoption$stable_municipality_id == "9999999"])))
  expect_equal(adoption$adoption_rate[1], 0.5)
  audit <- audit_adoption(adoption, test_a2_config())
  expect_equal(audit$summary$n_missing_denominator, 2L)
  expect_equal(audit$summary$n_ratio_above_threshold, 2L)
  expect_equal(audit$summary$max_ratio, 3)
  expect_equal(nrow(audit$by_month), 2L)
})

test_that("scarcity classes and feasibility check work", {
  set.seed(1)
  n <- 40
  exposure <- tibble::tibble(
    stable_municipality_id = as.character(seq_len(n)),
    population_adult = 1000,
    branches_per_10k_adults = rep(c(0, 1, 2, 3), each = n / 4),
    broadband_per_100_households = rep(c(5, 10, 20, 40), times = n / 4)
  )
  cls <- classify_banking_scarcity(exposure$branches_per_10k_adults)
  expect_equal(as.character(cls[1]), "none")
  expect_equal(as.character(cls[n]), "high")
  res <- check_scarcity_connectivity(exposure, test_a2_config())
  expect_equal(nrow(res$cells), 6L)
  expect_true(res$summary$viable)
  expect_equal(sum(res$cells$municipalities), n)
  # perfectly collinear scarcity/connectivity leaves empty cells -> not viable
  collinear <- exposure
  collinear$broadband_per_100_households <- collinear$branches_per_10k_adults * 10
  expect_false(check_scarcity_connectivity(collinear, test_a2_config())$summary$viable)
})

test_that("connectivity with tied quantiles errors instead of silently collapsing", {
  expect_error(classify_connectivity(rep(1, 10), 3L), "not unique")
})
