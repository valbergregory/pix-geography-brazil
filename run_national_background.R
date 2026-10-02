# A execução nacional só começa com o piloto aprovado (C1-C4 = PASS em
# check_pilot.R; ver docs/PILOT_APPROVAL_CRITERIA.md).
source("R/pilot_approval.R")
approval_path <- file.path("output", "pilot_approval.csv")
if (!file.exists(approval_path)) {
  stop(
    "Pilot approval not found. Run source('check_pilot.R') after run_pilot.R.",
    call. = FALSE
  )
}
approval <- summarise_pilot_approval(readr::read_csv(
  approval_path,
  col_types = readr::cols(.default = readr::col_character()),
  show_col_types = FALSE
))
if (!all(approval$status == "PASS")) {
  print(approval)
  stop(
    "The pilot did not pass C1-C4. Read output/pilot_approval.md before the national run.",
    call. = FALSE
  )
}

message(
  "Confirmed national execution: this job may require several hours and substantial memory."
)
Sys.setenv(PIX_CONFIRM_NATIONAL = "yes")
source("run_national.R")
