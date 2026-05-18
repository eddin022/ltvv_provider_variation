library(arrow)
library(dplyr)
library(lubridate)
library(jsonlite)

source("Z:/DataStageData/Eddington/R Library/functions/laps2_date_251118.R")

append_status <- function(script_name, step, extra = list()) {
  entry <- c(
    list(
      script = script_name,
      step = step,
      time = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ),
    extra
  )
  line <- toJSON(entry, auto_unbox = TRUE)
  write(line, file = "status.jsonl", append = TRUE)
}

script_name <- "laps2_wrangler"
append_status(script_name, "start")

# Read config.json and strip BOM if present
txt <- readLines("config.json", encoding = "UTF-8")
txt[1] <- sub("^\ufeff", "", txt[1])
cfg <- fromJSON(paste(txt, collapse = "\n"))

clif_path <- cfg$paths$clif
append_status(script_name, "loaded_config", list(clif_path = clif_path))

# %%
data_hospitalizations <- read_parquet("laps2_hospitalizations.parquet")
append_status(script_name, "loaded_hospitalizations", list(n = nrow(data_hospitalizations)))

# %%
clif_adt <- read_parquet(file.path(clif_path, "clif_adt.parquet"))
clif_labs <- read_parquet(file.path(clif_path, "clif_labs.parquet"))
clif_hospitalization <- read_parquet(file.path(clif_path, "clif_hospitalization.parquet"))
clif_patient <- read_parquet(file.path(clif_path, "clif_patient.parquet"))
clif_vitals <- read_parquet(file.path(clif_path, "clif_vitals.parquet"))
clif_gcs <- read_parquet(file.path(clif_path, "clif_gcs.parquet"))
append_status(script_name, "loaded_clif_tables")

# %%
head(data_hospitalizations, 5)

# %%
length(data_hospitalizations$hospitalizations_joined_id)

# %%
laps2 <- laps2_date(data = data_hospitalizations)
append_status(script_name, "computed_laps2")

# %%
write_parquet(laps2, "laps2_data.parquet")
append_status(script_name, "wrote_output", list(path = "laps2_data.parquet"))

laps2
