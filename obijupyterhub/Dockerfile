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
RUN apt-get update && apt-get install -y --no-install-recommends \
    # R et dépendances de base
    r-base \
    r-base-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libicu-dev \
    zlib1g-dev \
    # Polices et rendu graphique (indispensable pour ggplot2, ragg, etc.)
    libharfbuzz-dev \
    libfribidi-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    pandoc \
    # Outils de compilation et gestion de versions
    libgit2-dev \
    cmake \
    # Utilitaires systèmes déjà présents dans votre Dockerfile
    curl \
    wget \
    git \
    vim \
    nano \
    less \
    gdebi-core \
    ripgrep \
    # Pour générer des PDF/rapports depuis R Markdown / Jupyter
    texlive-xetex \
    texlive-luatex \
    texlive-fonts-recommended \
    texlive-fonts-extra \
    texlive-latex-extra \
    texlive-plain-generic \
    lmodern \
    fonts-lmodern \
    librsvg2-bin \
    cm-super \
    # Ruby (si vous en avez besoin pour autre chose)
    ruby \
    ruby-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Installer R et packages
COPY install_R_packages.R /tmp/install_R_packages.R
RUN Rscript /tmp/install_R_packages.R --no-save --no-restore && \
    rm -rf /tmp/Rtmp* /tmp/install_R_packages.R

# Installer les autres outils
RUN pip install --no-cache-dir bash_kernel csvkit && \
    python -m bash_kernel.install --sys-prefix

RUN gem install youplot

# Installation de Quarto (multi-arch)
RUN ARCH=$(dpkg --print-architecture) && \
    QUARTO_VERSION="1.8.27" && \
    wget https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${ARCH}.deb && \
    gdebi --non-interactive quarto-${QUARTO_VERSION}-linux-${ARCH}.deb && \
    rm quarto-${QUARTO_VERSION}-linux-${ARCH}.deb

# Set permissions for Jupyter user
RUN mkdir -p /home/${NB_USER}/.local/share/jupyter && \
    chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}



# Copier uniquement le binaire csvlens du builder
COPY --from=rust-builder /home/jovyan/.cargo/bin/csvlens /usr/local/bin/
COPY --from=rust-builder /usr/local/bin/* /usr/local/bin/

COPY start-notebook.sh /usr/local/bin/start-notebook.sh
RUN chmod +x /usr/local/bin/start-notebook.sh

# Switch back to Jupyter user
USER ${NB_UID}:${NB_GID}
WORKDIR /home/${NB_USER}/work

ENV PATH="/home/${NB_USER}/work/course/bin:${PATH}"
ENV R_LIBS_USER="/home/${NB_USER}/work/R_packages"
ENV R_LIBS_SITE="/home/${NB_USER}/work/course/R_packages:/usr/local/lib/R/site-library:/usr/lib/R/site-library"
