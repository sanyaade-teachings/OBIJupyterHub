#!/usr/bin/env Rscript
# Script to dynamically detect and install R dependencies from Quarto files.
# Scans library()/require() calls and remotes::install_git/github() calls.

args <- commandArgs(trailingOnly = TRUE)
quarto_dir <- if (length(args) > 0) args[1] else "."

target_lib <- "/usr/local/lib/R/site-library"

cat("Scanning Quarto files in:", quarto_dir, "\n")
cat("Target library:", target_lib, "\n")

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

# Extract package names from library()/require() calls
extract_cran_packages <- function(files) {
  pattern <- "(?:library|require)\\s*\\(\\s*['\"]?([A-Za-z0-9._]+)['\"]?"
  pkgs <- character(0)
  for (f in files) {
    lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
    m <- regmatches(lines, gregexpr(pattern, lines, perl = TRUE))
    hits <- unlist(m)
    if (length(hits) > 0) {
      extracted <- sub(
        "(?:library|require)\\s*\\(\\s*['\"]?([A-Za-z0-9._]+)['\"]?.*",
        "\\1", hits, perl = TRUE
      )
      pkgs <- c(pkgs, extracted)
    }
  }
  unique(pkgs)
}

# Extract git/github URLs from remotes::install_git/github() calls
extract_git_packages <- function(files) {
  # Matches remotes::install_git('url') or remotes::install_github('user/repo')
  pattern <- "remotes::install_(git|github)\\s*\\(\\s*['\"]([^'\"]+)['\"]"
  result <- list()
  for (f in files) {
    lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
    text <- paste(lines, collapse = "\n")
    m <- gregexpr(pattern, text, perl = TRUE)
    hits <- regmatches(text, m)[[1]]
    for (hit in hits) {
      type <- sub("remotes::install_(git|github).*", "\\1", hit, perl = TRUE)
      url  <- sub("remotes::install_(?:git|github)\\s*\\(\\s*['\"]([^'\"]+)['\"].*",
                  "\\1", hit, perl = TRUE)
      result[[length(result) + 1]] <- list(type = type, url = url)
    }
  }
  result
}

cran_deps <- extract_cran_packages(qmd_files)
git_deps  <- extract_git_packages(qmd_files)

# Quarto's implicit runtime dependencies — must be in target_lib (the persistent
# volume), not just somewhere in libPaths, because Quarto spawns its own R session.
quarto_required <- c("rmarkdown", "knitr")
if (length(git_deps) > 0) quarto_required <- c(quarto_required, "remotes")

cat("\nDetected CRAN packages:\n")
cat(paste(" -", unique(c(quarto_required, cran_deps)), collapse = "\n"), "\n")

if (length(git_deps) > 0) {
  cat("\nDetected git/github packages:\n")
  for (d in git_deps) cat(" -", d$type, ":", d$url, "\n")
}
cat("\n")

# --- Install CRAN packages ---

base_pkgs <- rownames(installed.packages(priority = "base"))

# quarto_required: check only in target_lib so they are guaranteed to be there
installed_in_target <- rownames(installed.packages(lib.loc = target_lib))
quarto_missing <- setdiff(quarto_required, c(base_pkgs, installed_in_target))

# other deps: check anywhere in libPaths (they just need to be loadable)
cran_deps  <- setdiff(cran_deps, c(base_pkgs, quarto_required))
installed  <- rownames(installed.packages())
to_install <- unique(c(quarto_missing, setdiff(cran_deps, installed)))

if (length(to_install) == 0) {
  cat("All CRAN packages already installed.\n")
} else {
  cat("Installing CRAN packages:", paste(to_install, collapse = ", "), "\n\n")
  failed <- character(0)
  for (pkg in to_install) {
    result <- tryCatch({
      withCallingHandlers(
        install.packages(pkg, lib = target_lib, repos = "https://cloud.r-project.org/",
                         dependencies = TRUE, quiet = FALSE),
        warning = function(w) {
          if (grepl("not available", conditionMessage(w))) invokeRestart("muffleWarning")
        }
      )
      if (!requireNamespace(pkg, quietly = TRUE)) "unavailable" else "ok"
    }, error = function(e) "error")

    if (result %in% c("unavailable", "error")) {
      cat("  [SKIP]", pkg, "- not available on CRAN\n")
      failed <- c(failed, pkg)
    } else {
      cat("  [OK]", pkg, "\n")
    }
  }
  if (length(failed) > 0)
    cat("\nNot installed (not on CRAN):", paste(failed, collapse = ", "), "\n")
}

# --- Install git/github packages ---

if (length(git_deps) > 0) {
  cat("\nInstalling git/github packages...\n")
  for (d in git_deps) {
    tryCatch({
      if (d$type == "git") {
        remotes::install_git(d$url, lib = target_lib, upgrade = "never")
      } else {
        remotes::install_github(d$url, lib = target_lib, upgrade = "never")
      }
      cat("  [OK]", d$url, "\n")
    }, error = function(e) {
      cat("  [FAIL]", d$url, "-", conditionMessage(e), "\n")
    })
  }
}

cat("\nDependency installation complete.\n")
