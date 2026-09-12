# diagnose_bcb2.R ----------------------------------------------------------
# Segundo diagnostico: descobrir POR QUE o Olinda responde 500.
#
# Tres hipoteses a separar:
#   (a) o servico Olinda / Pix esta fora do ar;
#   (b) o nome do recurso "TransacoesPixPorMunicipio" esta errado;
#   (c) o parametro DataBase tem outro formato.
#
# Rode no Console do RStudio, na raiz do projeto. Nao altera nada.

# --------------------------------------------------------------------------
# Auxiliar: executa e devolve status + corpo da resposta (mesmo em erro)
# --------------------------------------------------------------------------

sondar <- function(url, segundos = 60, mostrar_corpo = TRUE, limite = 1200) {
  req <- httr2::request(url)
  req <- httr2::req_user_agent(req, "pix-geography-research/0.1")
  req <- httr2::req_timeout(req, segundos)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)

  if (inherits(resp, "error")) {
    cat("  status: FALHA DE CONEXAO\n")
    cat("  erro  : ", conditionMessage(resp), "\n", sep = "")
    return(invisible(NULL))
  }

  status <- httr2::resp_status(resp)
  cat("  status: ", status, "\n", sep = "")
  cat("  tipo  : ", httr2::resp_content_type(resp), "\n", sep = "")

  if (mostrar_corpo) {
    corpo <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
    corpo <- substr(corpo, 1, limite)
    cat("  corpo : ", gsub("[\r\n]+", " ", corpo), "\n", sep = "")
  }
  invisible(resp)
}

barra <- function(titulo) {
  cat("\n", strrep("-", 74), "\n", titulo, "\n", strrep("-", 74), "\n", sep = "")
}

servico <- "https://olinda.bcb.gov.br/olinda/servico/Pix_DadosAbertos/versao/v1/odata"

# --------------------------------------------------------------------------
# 1. O corpo do erro 500 (o Olinda costuma explicar a causa aqui)
# --------------------------------------------------------------------------

barra("1. Corpo da resposta 500 na chamada atual")

sondar(sprintf(
  "%s/TransacoesPixPorMunicipio(DataBase=@DataBase)?@DataBase='20232'&$top=5&$format=json",
  servico
), limite = 2000)

# --------------------------------------------------------------------------
# 2. Raiz do servico: lista os recursos realmente existentes
# --------------------------------------------------------------------------

barra("2. Raiz do servico Pix_DadosAbertos (sem nome de recurso)")

resp_raiz <- sondar(paste0(servico, "/"), limite = 3000)

if (!is.null(resp_raiz) && httr2::resp_status(resp_raiz) == 200) {
  cat("\n  >>> RECURSOS DISPONIVEIS:\n")
  corpo <- tryCatch(
    httr2::resp_body_json(resp_raiz, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (!is.null(corpo$value)) print(corpo$value)
}

# --------------------------------------------------------------------------
# 3. Metadados: esquema completo, com nomes e parametros exatos
# --------------------------------------------------------------------------

barra("3. $metadata do servico")

resp_meta <- sondar(paste0(servico, "/$metadata"), mostrar_corpo = FALSE)

if (!is.null(resp_meta) && httr2::resp_status(resp_meta) == 200) {
  texto <- httr2::resp_body_string(resp_meta)
  nomes <- regmatches(texto, gregexpr('Name="[^"]+"', texto))[[1]]
  nomes <- unique(gsub('Name="|"', "", nomes))
  cat("\n  >>> NOMES ENCONTRADOS NO ESQUEMA (primeiros 80):\n")
  print(utils::head(nomes, 80))
}

# --------------------------------------------------------------------------
# 4. Controle: outro servico Olinda, para saber se o problema e geral
# --------------------------------------------------------------------------

barra("4. Controle - servico PTAX (deve responder 200 se o Olinda estiver no ar)")

sondar(
  paste0(
    "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/",
    "Moedas?$top=3&$format=json"
  ),
  limite = 600
)

# --------------------------------------------------------------------------
# 5. Variacoes do formato de DataBase
# --------------------------------------------------------------------------

barra("5. Variacoes do parametro DataBase")

variacoes <- c("20232", "202312", "2023", "202306")

for (v in variacoes) {
  cat("\n  DataBase = ", v, "\n", sep = "")
  sondar(
    sprintf(
      "%s/TransacoesPixPorMunicipio(DataBase=@DataBase)?@DataBase='%s'&$top=1&$format=json",
      servico, v
    ),
    mostrar_corpo = FALSE
  )
  Sys.sleep(0.5)
}

# --------------------------------------------------------------------------
# 6. Sem parametro nenhum
# --------------------------------------------------------------------------

barra("6. Recurso sem parametro")

sondar(
  sprintf("%s/TransacoesPixPorMunicipio?$top=1&$format=json", servico),
  limite = 800
)

cat("\n", strrep("=", 74), "\n", sep = "")
cat("FIM. Copie TODA a saida acima.\n")
