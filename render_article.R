source("R/setup.R")
check_required_packages()
check_latex_environment()
targets::tar_source("R")

article_pdf <- render_article_pdf("article/manuscript.qmd")
message("Article rendered to: ", article_pdf)
