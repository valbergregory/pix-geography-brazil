message(
  "Confirmed national execution: this job may require several hours and substantial memory."
)
Sys.setenv(PIX_CONFIRM_NATIONAL = "yes")
source("run_national.R")
