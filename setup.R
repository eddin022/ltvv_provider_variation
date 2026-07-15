packages <- c(
  "tidyverse", "lubridate", "collapse", "data.table", "pscl",
  "arrow", "jsonlite", "duckdb"
)

install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE))
    install.packages(pkg, dependencies = TRUE)
}

invisible(sapply(packages, install_if_missing))
message("All dependencies installed.")
