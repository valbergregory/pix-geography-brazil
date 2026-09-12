# Extracao dos dados municipais do Pix (BCB / Olinda OData) ----------------
#
# Fatos verificados empiricamente contra a API em 2026-08-30:
#
# 1. O recurso e um FunctionImport e exige DataBase na URL. Sem ele, a
#    resposta e 400 "The URI is malformed".
#
# 2. O recurso NAO aceita $skip. Qualquer chamada com $skip, inclusive
#    $skip=0, responde HTTP 500. Era a causa da falha do pipeline.
#
# 3. DataBase nao seleciona um arquivo: funciona como filtro AnoMes >=
#    DataBase. Com DataBase='202011' vem a serie inteira (70 meses).
#
# 4. $top, $orderby, $select, $filter e $count funcionam. $inlinecount nao.
#
# 5. Um unico $top alto devolve a base inteira: 183.822 linhas em 21,6 s
#    para 33 meses. Nao ha necessidade de paginar.
#
# 6. O formato text/csv usa virgula decimal dentro de campos entre aspas
#    ("4379170,2"), o que convida a erro de parsing. Usamos JSON.
#
# Estrategia: uma requisicao unica; se ela falhar, recuo automatico para
# uma requisicao por mes via $filter=AnoMes eq AAAAMM.

pix_start_anomes <- function(config) {
  value <- config$bcb$start_anomes
  if (is.null(value)) {
    value <- "202011"
  }
  as.character(value)
}

pix_page_size <- function(config) {
  value <- config$bcb$page_size
  if (is.null(value)) {
    value <- 1000000L
  }
  as.integer(value)
}

pix_transient_status <- function(response) {
  httr2::resp_status(response) %in% c(408L, 425L, 429L, 500L, 502L, 503L, 504L)
}

pix_request <- function(config, url) {
  request <- httr2::request(url)
  request <- httr2::req_user_agent(request, "pix-geography-research/0.1")
  request <- httr2::req_timeout(
    request,
    as.numeric(config$bcb$timeout_seconds)
  )
  httr2::req_retry(
    request,
    max_tries = as.integer(config$bcb$max_tries),
    is_transient = pix_transient_status,
    backoff = function(attempt) min(60, 2^attempt)
  )
}

# A URL e montada como texto de proposito. httr2::req_url_query() aplica
# curl::curl_escape() aos nomes dos parametros e ao caminho, produzindo
# %40DataBase, %24top e %28DataBase%3D%40DataBase%29, que o Olinda rejeita.

pix_url_full_series <- function(config) {
  sprintf(
    "%s?@DataBase='%s'&$format=json&$top=%d",
    config$bcb$endpoint,
    pix_start_anomes(config),
    pix_page_size(config)
  )
}

pix_url_single_month <- function(config, anomes) {
  sprintf(
    "%s?@DataBase='%s'&$format=json&$top=%d&$filter=AnoMes%%20eq%%20%s",
    config$bcb$endpoint,
    pix_start_anomes(config),
    pix_page_size(config),
    anomes
  )
}

pix_perform <- function(config, url) {
  response <- tryCatch(
    httr2::req_perform(pix_request(config, url)),
    error = function(condition) {
      stop(
        "Falha na API do BCB.",
        "\n  URL:  ", url,
        "\n  Erro: ", conditionMessage(condition),
        call. = FALSE
      )
    }
  )

  values <- httr2::resp_body_json(response, simplifyVector = TRUE)$value

  if (is.null(values) || length(values) == 0L) {
    return(tibble::tibble())
  }
  tibble::as_tibble(values)
}

pix_expected_months <- function(config) {
  start <- pix_start_anomes(config)
  start_date <- as.Date(sprintf(
    "%s-%s-01",
    substr(start, 1L, 4L),
    substr(start, 5L, 6L)
  ))
  end_date <- as.Date(format(Sys.Date(), "%Y-%m-01"))
  format(seq(start_date, end_date, by = "month"), "%Y%m")
}

fetch_pix_by_month <- function(config) {
  months <- pix_expected_months(config)
  blocks <- list()

  for (anomes in months) {
    message("BCB Pix | AnoMes ", anomes)
    block <- pix_perform(config, pix_url_single_month(config, anomes))

    if (nrow(block) == 0L) {
      message("   sem registros (competencia ainda nao publicada)")
      next
    }
    blocks[[anomes]] <- block
  }

  dplyr::bind_rows(blocks)
}

fetch_all_pix <- function(config) {
  message(
    "Baixando a serie do Pix municipal (AnoMes >= ",
    pix_start_anomes(config), ") ..."
  )

  data <- tryCatch(
    pix_perform(config, pix_url_full_series(config)),
    error = function(condition) {
      message("Requisicao unica falhou: ", conditionMessage(condition))
      message("Recuando para o download mes a mes ...")
      NULL
    }
  )

  if (is.null(data) || nrow(data) == 0L) {
    data <- fetch_pix_by_month(config)
  }

  if (nrow(data) == 0L) {
    stop("The BCB endpoint returned no Pix municipality records.", call. = FALSE)
  }

  data <- dplyr::distinct(data)

  message(
    "Linhas: ", nrow(data),
    " | meses: ", length(unique(data$AnoMes)),
    " | de ", min(data$AnoMes, na.rm = TRUE),
    " a ", max(data$AnoMes, na.rm = TRUE),
    " | municipios: ", length(unique(data$Municipio_Ibge))
  )

  data
}

write_json_metadata <- function(metadata, path) {
  jsonlite::write_json(
    metadata,
    path = path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  path
}

extract_pix_snapshot <- function(config) {
  ensure_project_directories(config)
  extraction_time <- Sys.time()
  snapshot_id <- timestamp_id(extraction_time)

  parquet_path <- file.path(
    config$project$raw_dir,
    paste0("pix_municipality_", snapshot_id, ".parquet")
  )
  metadata_path <- file.path(
    config$project$raw_dir,
    paste0("pix_municipality_", snapshot_id, ".json")
  )

  data <- fetch_all_pix(config)

  arrow::write_parquet(data, parquet_path, compression = "zstd")

  metadata <- list(
    source = config$bcb$endpoint,
    extraction_utc = format(extraction_time, tz = "UTC", usetz = TRUE),
    start_anomes = pix_start_anomes(config),
    rows = nrow(data),
    columns = ncol(data),
    minimum_AnoMes = min(data$AnoMes, na.rm = TRUE),
    maximum_AnoMes = max(data$AnoMes, na.rm = TRUE),
    distinct_AnoMes = length(unique(data$AnoMes)),
    distinct_municipalities = length(unique(data$Municipio_Ibge)),
    sha256_not_computed = TRUE
  )
  write_json_metadata(metadata, metadata_path)

  normalizePath(c(parquet_path, metadata_path), winslash = "/", mustWork = TRUE)
}

read_pix_snapshot <- function(snapshot_files) {
  parquet_path <- snapshot_files[grepl("\\.parquet$", snapshot_files)]
  if (length(parquet_path) != 1L) {
    stop("Expected exactly one Parquet snapshot file.", call. = FALSE)
  }
  arrow::read_parquet(parquet_path) |>
    tibble::as_tibble()
}
