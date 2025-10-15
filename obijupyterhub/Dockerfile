# ---------- Stage 1 : builder ----------
FROM jupyter/base-notebook:latest AS builder

USER root

# Install system dependencies for R, build tools and Go/Rust
RUN apt-get update && apt-get install -y \
    r-base r-base-dev \
    libcurl4-openssl-dev libssl-dev libxml2-dev \
    build-essential git curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install R kernel + useful packages
RUN R -e "install.packages('IRkernel', repos='http://cran.rstudio.com/')" && \
    R -e "IRkernel::installspec(user = FALSE)" && \
    R -e "install.packages(c('tidyverse','vegan','ade4'), repos='http://cran.rstudio.com/')"

# Install bash kernel
RUN pip install bash_kernel && python -m bash_kernel.install --sys-prefix

# Install obitools4
RUN curl -L https://raw.githubusercontent.com/metabarcoding/obitools4/master/install_obitools.sh | bash

# Install csvkit
RUN pip install csvkit

# Install csvlens via Rust
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y && \
    . $HOME/.cargo/env && \
    cargo install csvlens

RUN apt-get update && apt-get install -y ruby ruby-dev build-essential \
    && gem install youplot

# Copy csvlens to /usr/local/bin for final use
RUN cp $HOME/.cargo/bin/csvlens /usr/local/bin/

# Set permissions for Jupyter user
RUN mkdir -p /home/${NB_USER}/.local/share/jupyter && \
    chown -R ${NB_UID}:${NB_GID} /home/${NB_USER} 

COPY start-notebook.sh /usr/local/bin/start-notebook.sh
RUN chmod +x /usr/local/bin/start-notebook.sh

# Switch back to Jupyter user
USER ${NB_UID}:${NB_GID}
WORKDIR /home/${NB_USER}/work

# Environment variables
ENV PATH="/home/${NB_USER}/work/course/bin:${PATH}"
ENV R_LIBS_USER="/home/${NB_USER}/work/R_packages"
ENV R_LIBS_SITE="/home/${NB_USER}/work/course/R_packages:/usr/local/lib/R/site-library:/usr/lib/R/site-library"

