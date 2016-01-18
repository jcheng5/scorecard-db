library(methods)
library(dplyr)
library(RSQLite)

parseDefns <- function() {
  dd <- yaml::yaml.load_file("CollegeScorecard_Raw_Data/data_dictionary.yaml")$dictionary
  dd <- bind_cols(data.frame(id = names(dd), stringsAsFactors = FALSE), bind_rows(dd))
  dd
}

colLookup <- function() {
  dd <- parseDefns()
  ids <- dd$id
  cols <- ifelse(!is.na(dd$source), as.list(dd$source), strsplit(dd$calculate, " or "))
  lookup <- new.env(parent = emptyenv())
  mapply(function(id, cols) {
    for (col in cols)
      lookup[[col]] <- dd[dd$id == id,]
  }, ids, cols)
  
  lookup$YEAR <- data.frame(
    id = "year",
    source = "YEAR",
    type = "integer",
    description = "Year of observation",
    label = NA_character_,
    calculate = NA_character_,
    stringsAsFactors = FALSE
  )
  
  lookup
}

loadMerged <- function(n_max = -1, progress = interactive()) {
  cl <- colLookup()
  
  header <- readr::read_csv("output/merged.csv", col_types = paste(rep("c", 1730), collapse = ""), n_max = 0)
  coltypes <- vapply(names(header), function(colname) {
    record <- cl[[colname]]
    if (is.null(record)) {
      "_"
    } else if (colname %in% c("ZIP", "OPEID")) {
      # ZIP is erroneously encoded as integer; zip+4 fails to parse
      "c"
    } else if (colname %in% c("STABBR", "AccredAgency", "INSTURL", "NPCURL")) {
      # Missing types
      "c"
    } else {
      switch(record$type,
        autocomplete = "c",
        float = "n",
        #integer = "i",
        integer = "n", # Lots of columns have floats in supposedly int fields
        {
          str(record)
          stop("Unexpected record type ", record$type)
        }
      )
    }
  }, character(1))
  
  merged <- readr::read_csv("output/merged.csv",
    col_types = paste(coltypes, collapse = ""),
    n_max = n_max,
    progress = progress
  )
  merged
}

normalized <- function(n_max = -1, progress = interactive()) {
  dd <- parseDefns()
  merged <- loadMerged(n_max = n_max, progress = progress)
  
  # Gather data for each variable in the data definition
  colnames <- c("year", dd$id)
  datacolnames <- ifelse(!is.na(dd$source), as.list(dd$source), strsplit(dd$calculate, " or "))
  data <- lapply(datacolnames, function(datacol) {
    if (length(datacol) == 1) {
      merged[[datacol]]
    } else if (length(datacol) == 2) {
      a <- merged[[datacol[[1]]]]
      b <- merged[[datacol[[2]]]]
      a | b
    } else {
      stop("unexpected arity of calculated field ", datacol)
    }
  })
  data <- c(list(merged$YEAR), data)
  names(data) <- colnames
  as.data.frame(data, stringsAsFactors = FALSE)
}

latestSchoolNames <- function(normalized_data) {
  normalized_data %>%
    arrange(desc(year)) %>%
    group_by(id) %>%
    summarise(school.name = head(school.name, 1)) %>%
    as.data.frame()
}

writeToSQLite <- function(n_max = -1, progress = interactive()) {
  ndata <- normalized(n_max = n_max, progress = progress)
  conn <- dbConnect(SQLite(), dbname = "output/CollegeScorecard.sqlite")
  on.exit(dbDisconnect(conn))
  
  dbWriteTable(conn, "data", ndata)
  dbGetQuery(conn, 'CREATE INDEX idx_data_id ON data (id);')
  dbGetQuery(conn, 'CREATE INDEX idx_data_school_name ON data ("school.name");')
  
  dbWriteTable(conn, "schoolnames", latestSchoolNames(ndata))
  dbGetQuery(conn, 'CREATE INDEX idx_schoolnames_id ON schoolnames (id);')
  dbGetQuery(conn, 'CREATE INDEX idx_schoolnames_school_name ON schoolnames ("school.name");')
  
  invisible()
}

if (!interactive()) {
  writeToSQLite(progress = TRUE)
}