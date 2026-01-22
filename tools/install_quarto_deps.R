#!/usr/bin/env Rscript
# Script to dynamically detect and install R dependencies from Quarto files
# Uses the {attachment} package to scan .qmd files for library()/require() calls

args <- commandArgs(trailingOnly = TRUE)
quarto_dir <- if (length(args) > 0) args[1] else "."

# Target library for installing packages (the mounted volume)
target_lib <- "/usr/local/lib/R/site-library"

cat("Scanning Quarto files in:", quarto_dir, "\n")
cat("Target library:", target_lib, "\n")

# Find all .qmd files
qmd_files <- list.files(
  path = quarto_dir,
  pattern = "\\.qmd$",
  recursive = TRUE,
  full.names = TRUE
)

if (length(qmd_files) == 0) {
  cat("No .qmd files found.\n")
  quit(status = 0)
}

cat("Found", length(qmd_files), "Quarto files\n")

# Extract dependencies using attachment
deps <- attachment::att_from_rmds(qmd_files, inline = TRUE)

if (length(deps) == 0) {
  cat("No R package dependencies detected.\n")
  quit(status = 0)
}

cat("\nDetected R packages:\n")
cat(paste(" -", deps, collapse = "\n"), "\n\n")

# Filter out base R packages that are always available
base_pkgs <- rownames(installed.packages(priority = "base"))
deps <- setdiff(deps, base_pkgs)

# Check which packages are not installed
installed <- rownames(installed.packages())
to_install <- setdiff(deps, installed)

if (length(to_install) == 0) {
  cat("All required packages are already installed.\n")
} else {
  cat("Installing missing packages:", paste(to_install, collapse = ", "), "\n\n")
  install.packages(
    to_install,
    lib = target_lib,
    repos = "https://cloud.r-project.org/",
    dependencies = TRUE
  )
  cat("\nPackage installation complete.\n")
}
