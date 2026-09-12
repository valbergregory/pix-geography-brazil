# diagnose_bcb3.R ----------------------------------------------------------
# Terceiro diagnostico: definir a estrategia de download.
#
# O que ja sabemos:
#   - o servico esta no ar e o recurso TransacoesPixPorMunicipio existe;
#   - ele e um FunctionImport, e DataBase e obrigatorio na URL;
#   - sem $skip a chamada retorna 200; a chamada do projeto (com $skip) deu 500;
#   - as linhas vem FORA DE ORDEM e misturando varios AnoMes.
#
# Falta decidir: como paginar, se DataBase filtra alguma coisa, e qual o
# volume total.
#
# Rode no Console. Nao altera nada. Pode levar alguns minutos na secao 5.

servico <- paste0(
  "https://olinda.bcb.gov.br/olinda/servico/",
  "Pix_DadosAbertos/versao/v1/odata"
)

montar <- function(query, database = "202312", formato = "json") {
  sprintf(
    "%s/TransacoesPixPorMunicipio(DataBase=@DataBase)?@DataBase='%s'&$format=%s&%s",
    servico, database, formato, query
  )
}

sondar <- function(rotulo, url, segundos = 300) {
  t0 <- Sys.time()
  req <- httr2::request(url)
  req <- httr2::req_user_agent(req, "pix-geography-research/0.1")
  req <- httr2::req_timeout(req, segundos)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  dt <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

  if (inherits(resp, "error")) {
    cat(sprintf("  %-44s FALHA (%ss)\n", rotulo, dt))
    cat("      ", conditionMessage(resp), "\n")
    return(invisible(NULL))
  }

  st <- httr2::resp_status(resp)
  n <- NA_integer_
  if (st == 200 && grepl("json", httr2::resp_content_type(resp), fixed = TRUE)) {
    v <- tryCatch(
      httr2::resp_body_json(resp, simplifyVector = TRUE)$value,
      error = function(e) NULL
    )
    n <- if (is.null(v)) 0L else NROW(v)
  }
  cat(sprintf("  %-44s %s   linhas=%-7s (%ss)\n", rotulo, st, n, dt))
  invisible(resp)
}

barra <- function(t) {
  cat("\n", strrep("-", 74), "\n", t, "\n", strrep("-", 74), "\n", sep = "")
}

# --------------------------------------------------------------------------
barra("1. O $skip e mesmo o culpado?")
# --------------------------------------------------------------------------

sondar("sem $skip",            montar("$top=5"))
sondar("com $skip=0",          montar("$top=5&$skip=0"))
sondar("com $skip=10",         montar("$top=5&$skip=10"))

# --------------------------------------------------------------------------
barra("2. Quais opcoes OData o recurso aceita?")
# --------------------------------------------------------------------------

sondar("$orderby=AnoMes",      montar("$top=5&$orderby=AnoMes"))
sondar("$select",              montar("$top=5&$select=AnoMes,Municipio_Ibge"))
sondar("$filter AnoMes",       montar("$top=5&$filter=AnoMes%20eq%20202401"))
sondar("$filter Estado_Ibge",  montar("$top=5&$filter=Estado_Ibge%20eq%2027"))
sondar("$count=true",          montar("$top=5&$count=true"))
sondar("$inlinecount",         montar("$top=5&$inlinecount=allpages"))

# --------------------------------------------------------------------------
barra("3. DataBase filtra alguma coisa?")
# --------------------------------------------------------------------------

comparar_database <- function(db) {
  resp <- sondar(paste0("DataBase=", db, " (top 3000)"),
                 montar("$top=3000", database = db))
  if (is.null(resp) || httr2::resp_status(resp) != 200) return(invisible(NULL))
  v <- httr2::resp_body_json(resp, simplifyVector = TRUE)$value
  if (is.null(v) || NROW(v) == 0) return(invisible(NULL))
  cat("      AnoMes: de ", min(v$AnoMes), " a ", max(v$AnoMes),
      " | distintos: ", length(unique(v$AnoMes)), "\n", sep = "")
  invisible(v)
}

comparar_database("202306")
comparar_database("202312")
comparar_database("20232")

# --------------------------------------------------------------------------
barra("4. Formato CSV (muito mais leve que JSON)")
# --------------------------------------------------------------------------

url_csv <- montar("$top=5", formato = "text/csv")
cat("  URL: ", url_csv, "\n", sep = "")
r <- sondar("formato text/csv", url_csv)
if (!is.null(r) && httr2::resp_status(r) == 200) {
  cat("  tipo: ", httr2::resp_content_type(r), "\n", sep = "")
  cat("  amostra:\n")
  cat(substr(httr2::resp_body_string(r), 1, 500), "\n")
}

# --------------------------------------------------------------------------
barra("5. Volume total (pode demorar - seja paciente)")
# --------------------------------------------------------------------------

cat("  Tentando baixar tudo de uma vez com $top alto...\n")

r_total <- sondar("$top=1000000", montar("$top=1000000"), segundos = 900)

if (!is.null(r_total) && httr2::resp_status(r_total) == 200) {
  v <- httr2::resp_body_json(r_total, simplifyVector = TRUE)$value
  if (!is.null(v) && NROW(v) > 0) {
    cat("\n  >>> RESULTADO DO DOWNLOAD COMPLETO\n")
    cat("      linhas          : ", NROW(v), "\n", sep = "")
    cat("      colunas         : ", NCOL(v), "\n", sep = "")
    cat("      AnoMes distintos: ", length(unique(v$AnoMes)), "\n", sep = "")
    cat("      AnoMes minimo   : ", min(v$AnoMes), "\n", sep = "")
    cat("      AnoMes maximo   : ", max(v$AnoMes), "\n", sep = "")
    cat("      municipios      : ", length(unique(v$Municipio_Ibge)), "\n", sep = "")
    cat("      UFs             : ", length(unique(v$Estado_Ibge)), "\n", sep = "")

    faltantes <- setdiff(
      format(seq(
        as.Date(sprintf("%d-%02d-01", min(v$AnoMes) %/% 100, min(v$AnoMes) %% 100)),
        as.Date(sprintf("%d-%02d-01", max(v$AnoMes) %/% 100, max(v$AnoMes) %% 100)),
        by = "month"
      ), "%Y%m"),
      as.character(sort(unique(v$AnoMes)))
    )
    cat("      meses faltantes : ",
        if (length(faltantes) == 0) "nenhum" else paste(faltantes, collapse = ", "),
        "\n", sep = "")

    assign("pix_bruto_teste", v, envir = globalenv())
    cat("\n      O objeto pix_bruto_teste ficou disponivel no ambiente global.\n")
  }
}

cat("\n", strrep("=", 74), "\n", sep = "")
cat("FIM. Copie TODA a saida acima.\n")
