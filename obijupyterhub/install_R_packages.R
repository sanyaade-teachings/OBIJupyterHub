#!/usr/bin/env Rscript

# Installer pak (lui-même en binaire si possible)
install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))
pak::pkg_install("cli")

# Détection automatique du système et installation de tous les paquets en binaire
pak::pkg_install(c(
  "IRkernel",
  "tidyverse",
  "vegan",
  "ade4",
  "BiocManager",
  "remotes",
  "igraph",
  "Rdpack"
))

# ------------------------------------------------------------
# Paquets Bioconductor (toujours via BiocManager)
# ------------------------------------------------------------
pak::pkg_install("bioc::biomformat")

# ------------------------------------------------------------
# Paquets depuis GitHub / dépôts git
# ------------------------------------------------------------
pak::pkg_install("metabaRfactory/metabaR")
pak::pkg_install("git::https://forge.metabarcoding.org/obitools/ROBIUtils.git")
pak::pkg_install("git::https://forge.metabarcoding.org/obitools/ROBITaxonomy.git")
pak::pkg_install("git::https://forge.metabarcoding.org/obitools/ROBITools.git")
pak::pkg_install("git::https://forge.metabarcoding.org/MetabarcodingSchool/biodiversity-metrics.git")

# ------------------------------------------------------------
# Installation du noyau Jupyter pour IRkernel
# ------------------------------------------------------------
# Si on est root -> installation système, sinon -> user
if (Sys.info()["user"] == "root") {
  IRkernel::installspec(user = FALSE)
} else {
  IRkernel::installspec(user = TRUE)
}

cat("\n✅ Tous les paquets R ont été installés avec succès.\n")
