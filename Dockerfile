FROM jupyter/base-notebook:latest

USER root

# Install R and system dependencies
RUN apt-get update && apt-get install -y \
    r-base \
    r-base-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    git \
    build-essential \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install R kernel for Jupyter (as root)
RUN R -e "install.packages('IRkernel', repos='http://cran.rstudio.com/')" && \
    R -e "IRkernel::installspec(user = FALSE)"

# Install some useful R packages for labs
RUN R -e "install.packages(c('tidyverse', 'vegan', 'ade4'), repos='http://cran.rstudio.com/')"

# Install bash kernel (as root also)
RUN pip install bash_kernel && \
    python -m bash_kernel.install --sys-prefix

# Install obitools4 (written in Go)
RUN curl -L https://raw.githubusercontent.com/metabarcoding/obitools4/master/install_obitools.sh | bash

# Install csvkit
RUN pip install csvkit

# Install csvlens
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y \
    && . $HOME/.cargo/env \
    && cargo install csvlens \
    && mv $HOME/.cargo/bin/csvlens /usr/local/bin/ \
    && rm -rf $HOME/.cargo $HOME/.rustup

# Create necessary directories with proper permissions
RUN mkdir -p /home/${NB_USER}/.local/share/jupyter && \
    chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}

USER ${NB_UID}

WORKDIR /home/${NB_USER}
