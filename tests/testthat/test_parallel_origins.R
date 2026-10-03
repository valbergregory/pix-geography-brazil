test_that("resolve_origin_workers validates and caps the number of workers", {
  expect_equal(resolve_origin_workers(NULL, 29L), 1L)
  expect_equal(resolve_origin_workers(4L, 29L), 4L)
  expect_equal(resolve_origin_workers(8L, 3L), 3L)
  expect_equal(resolve_origin_workers(4L, 0L), 1L)
  expect_gte(resolve_origin_workers("auto", 29L), 1L)
  expect_error(resolve_origin_workers(0L, 29L), "positive integer")
  expect_error(resolve_origin_workers("many", 29L), "positive integer")
})

test_that("parallel origin tasks return the same results, in order, as sequential ones", {
  task <- function(index, data) {
    data.frame(index = index, value = data$base * index, pid = Sys.getpid())
  }
  data <- list(base = 10)
  sequential <- run_origin_tasks(1:5, task, workers = 1L, worker_data = data)
  parallel_run <- run_origin_tasks(1:5, task, workers = 2L, worker_data = data)
  strip <- function(x) lapply(x, function(d) d[c("index", "value")])
  expect_equal(strip(parallel_run), strip(sequential))
  expect_true(all(vapply(parallel_run, `[[`, numeric(1), "pid") != Sys.getpid()))
  expect_equal(run_origin_tasks(integer(), task, workers = 2L), list())
})
