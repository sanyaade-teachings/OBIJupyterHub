FROM jupyter/base-notebook:latest

USER root

# Installation de R et des dépendances système
RUN apt-get update && apt-get install -y \
    r-base \
    r-base-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Installation du kernel R pour Jupyter (en tant que root)
RUN R -e "install.packages('IRkernel', repos='http://cran.rstudio.com/')" && \
    R -e "IRkernel::installspec(user = FALSE)"

# Installation de quelques packages R utiles pour les TP
RUN R -e "install.packages(c('tidyverse','vegan','ade4'), repos='http://cran.rstudio.com/')"

# Installation du kernel bash (en tant que root aussi)
RUN pip install bash_kernel && \
    python -m bash_kernel.install --sys-prefix

# Créer les répertoires nécessaires avec les bonnes permissions
RUN mkdir -p /home/${NB_USER}/.local/share/jupyter && \
    chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}

USER ${NB_UID}

WORKDIR /home/${NB_USER}