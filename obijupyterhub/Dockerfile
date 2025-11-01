# ---------- Stage 1 : builder pour csvlens ----------
FROM jupyter/base-notebook:latest AS rust-builder

USER root

# Installer seulement les dépendances pour compiler csvlens
RUN apt-get update && apt-get install -y \
    curl build-essential zlib1g-dev unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Installer Rust et compiler csvlens
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
RUN . $HOME/.cargo/env && cargo install csvlens

# Install obitools4
RUN TEMP=. curl -L https://raw.githubusercontent.com/metabarcoding/obitools4/master/install_obitools.sh \
    | bash -s -- --install-dir $HOME/obitools-build \
    && cp $HOME/obitools-build/bin/* /usr/local/bin
RUN ls -l /usr/local/bin


# ---------- Stage 2 : image finale ----------
FROM jupyter/base-notebook:latest

USER root

# Installer seulement les dépendances d'exécution (sans build-essential)
RUN apt-get update && apt-get install -y \
    r-base \
    libcurl4-openssl-dev libssl-dev libxml2-dev \
    curl \
    texlive-xetex texlive-fonts-recommended texlive-plain-generic \
    ruby ruby-dev \
    vim nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Installer R et packages
RUN R -e "install.packages(c('IRkernel','tidyverse','vegan','ade4','BiocManager','remotes'), repos='http://cran.rstudio.com/')" && \
    R -e "BiocManager::install('biomformat')" && \
    R -e "remotes::install_github('metabaRfactory/metabaR')" && \
    R -e "IRkernel::installspec(user = FALSE)" && \
    rm -rf /tmp/Rtmp*

# Installer les autres outils
RUN pip install --no-cache-dir bash_kernel csvkit && \
    python -m bash_kernel.install --sys-prefix

RUN gem install youplot

# Set permissions for Jupyter user
RUN mkdir -p /home/${NB_USER}/.local/share/jupyter && \
    chown -R ${NB_UID}:${NB_GID} /home/${NB_USER} 

COPY start-notebook.sh /usr/local/bin/start-notebook.sh
RUN chmod +x /usr/local/bin/start-notebook.sh

# Copier uniquement le binaire csvlens du builder
COPY --from=rust-builder /home/jovyan/.cargo/bin/csvlens /usr/local/bin/
COPY --from=rust-builder /usr/local/bin/* /usr/local/bin/

# Switch back to Jupyter user
USER ${NB_UID}:${NB_GID}
WORKDIR /home/${NB_USER}/work

ENV PATH="/home/${NB_USER}/work/course/bin:${PATH}"
ENV R_LIBS_USER="/home/${NB_USER}/work/R_packages"
ENV R_LIBS_SITE="/home/${NB_USER}/work/course/R_packages:/usr/local/lib/R/site-library:/usr/lib/R/site-library"
