# OBIJupyterHub - the DNA Metabarcoding Learning Server

## Intended use

This project packages the MetabarcodingSchool training lab into one reproducible bundle. You get Python, R, and Bash kernels, a Quarto-built course website, and preconfigured admin/student accounts, so onboarding a class is a single command instead of a day of setup. Everything runs locally on a single machine, student work persists between sessions, and `./start-jupyterhub.sh` takes care of pulling images, rendering the site, preparing volumes, and bringing JupyterHub up at `http://localhost:8888`.

## Prerequisites (with quick checks)

You only need **Docker and Docker Compose** on the machine that will host the lab. All other tools (Quarto, Hugo, Python, R) are provided via a builder Docker image and do not need to be installed on your system.

- macOS: install [OrbStack](https://orbstack.dev/) (recommended) or Docker Desktop; both ship Docker Engine and Compose.
- Linux: install Docker Engine and the Compose plugin (`sudo apt install docker.io docker-compose-plugin`) or from Docker's official packages.
- Windows: install Docker Desktop with the WSL2 backend enabled.

Verify from a terminal:

```bash
docker --version
docker compose version    # or: docker-compose --version
```

## Three operating modes

`./start-jupyterhub.sh` has three modes that control how Docker images are obtained:

| Mode | Flag | Description |
|------|------|-------------|
| **Pull** (default) | *(none)* | Pull pre-built images from the registry and start |
| **Local build** | `--local-build` | Build images locally on your machine and start (no push) |
| **Publish** | `--publish` | Build multi-arch images (amd64 + arm64), push to registry, then start |

### Pull mode — default, fastest

```bash
./start-jupyterhub.sh
```

Downloads the three pre-built images from `registry.metabarcoding.org/metabarschool/`:
- `obijupyterhub-builder:latest`
- `obijupyterhub-hub:latest`
- `obijupyterhub-student:latest`

This is what instructors should use in class. No compilation, no wait.

### Local build mode — for development

```bash
./start-jupyterhub.sh --local-build
```

Builds all three images locally using the Dockerfiles in `obijupyterhub/`. Rebuilt images stay on your machine and are not pushed to the registry. Additional flags apply only in this mode:

| Flag | Effect |
|------|--------|
| `--no-build` / `--offline` | Skip all image operations, use whatever is already local |
| `--force-rebuild` | Rebuild all images without Docker cache |
| `--rebuild-builder` | Force rebuild the builder image only |
| `--rebuild-student` | Force rebuild the student image only |
| `--rebuild-hub` | Force rebuild the JupyterHub image only |

`--rebuild-*` and `--force-rebuild` imply `--local-build` automatically.

### Publish mode — for maintainers

```bash
./start-jupyterhub.sh --publish
```

Builds all three images for both `linux/amd64` and `linux/arm64` using `docker buildx`, then pushes them to the registry tagged with both `:latest` and the version from `version.txt`. Requires write access to the registry and `docker buildx` with a `docker-container` driver.

**Before publishing a new version**, bump `version.txt` at the project root:

```
0.2.0
```

## Actions (all modes)

These flags work alongside any mode:

| Flag | Effect |
|------|--------|
| `--stop-server` | Stop the stack and remove student containers, then exit |
| `--update-lectures` | Rebuild the course website only (no Docker stop/start) |
| `--update-obidoc` | Rebuild the obidoc documentation only (no Docker stop/start) |
| `--build-obidoc` | Force rebuild of obidoc documentation on next full start |

## Installation and first run

1. Clone the project:

```bash
git clone https://forge.metabarcoding.org/MetabarcodingSchool/OBIJupyterHub.git
cd OBIJupyterHub
```

2. Repository structure:

```
OBIJupyterHub/
├── start-jupyterhub.sh              single entry point
├── version.txt                      current image version number
├── obijupyterhub/
│   ├── docker-compose.yml
│   ├── Dockerfile                   student image
│   ├── Dockerfile.hub               JupyterHub image
│   ├── Dockerfile.builder           builder image (Quarto, Hugo, R, Python)
│   └── jupyterhub_config.py
├── jupyterhub_volumes/              data persisted on the host
│   ├── builder/R_packages/          R package cache for building lectures
│   ├── course/                      read-only for students (notebooks, data, bin)
│   ├── shared/                      shared read/write space for everyone
│   ├── users/                       per-user persistent data
│   └── web/                         rendered course website
├── tools/
│   ├── install_quarto_deps.R        automatic R dependency detection and install
│   └── install_packages.sh          install shared R packages into course/
└── web_src/                         Quarto sources for the course website
```

3. (Optional) place course materials in `jupyterhub_volumes/course/` before first run.

4. Start everything:

```bash
./start-jupyterhub.sh            # pulls images from registry (recommended)
# or
./start-jupyterhub.sh --local-build   # builds locally
```

5. Access JupyterHub at `http://localhost:8888`.

6. Stop when done:

```bash
./start-jupyterhub.sh --stop-server
# or from obijupyterhub/
docker-compose down
```

## How the builder image works

The `obijupyterhub-builder` image contains Quarto, Hugo, R, and Python — you do not need any of these on your host. The script runs this image as a temporary container to:

- detect R package dependencies from your `.qmd` files (scans `library()`, `require()`, and `remotes::install_git/github()` calls using base R — no external package required)
- install missing R packages into `jupyterhub_volumes/builder/R_packages/` (cached between runs)
- render the Quarto website from `web_src/`
- generate PDF galleries and `pages.json`
- (optionally) build the obidoc documentation with Hugo

### R package caching

Packages are cached in `jupyterhub_volumes/builder/R_packages/`:

- **First build**: all packages used in your `.qmd` files are detected and installed (may take a while).
- **Subsequent builds**: only new packages are installed, making builds much faster.
- **Non-CRAN packages**: packages installed via `remotes::install_git()` or `remotes::install_github()` in your `.qmd` files are detected and pre-installed automatically before rendering.
- **Clear the cache**: delete `jupyterhub_volumes/builder/R_packages/` to force a full reinstall.

## OBITools documentation (obidoc)

The OBITools4 documentation is built from the [`obitools4-doc`](https://github.com/metabarcoding/obitools4-doc) repository using Hugo and served as a static site at `http://localhost:8888/obidoc/`.

### How it works

The builder container clones the repository (with all submodules), runs `hugo build`, and writes the generated HTML into `jupyterhub_volumes/web/obidoc/`. Caddy then serves these files directly — no special routing is needed.

### First installation

The documentation is built automatically on the first full start if `jupyterhub_volumes/web/obidoc/` is empty:

```bash
./start-jupyterhub.sh
```

To force a build even if the directory is already populated, use `--build-obidoc` during a full start:

```bash
./start-jupyterhub.sh --build-obidoc
```

### Updating the documentation

To rebuild the documentation without stopping the running stack:

```bash
./start-jupyterhub.sh --update-obidoc
```

This pulls the latest version of the builder image (or uses the local one with `--local-build`), reclones the `obitools4-doc` repository, rebuilds the site, and replaces the contents of `jupyterhub_volumes/web/obidoc/`. The JupyterHub stack keeps running throughout.

### Removing the documentation

To remove the built documentation (e.g. to free disk space or force a clean rebuild):

```bash
rm -rf jupyterhub_volumes/web/obidoc/*
```

The next `./start-jupyterhub.sh` will rebuild it automatically.

## Managing course and student data

Each student lands in `/home/jovyan/work/` with three areas:

```
work/
├── [student files]         personal workspace (persistent)
├── R_packages/             personal R packages (writable by student)
├── shared/                 shared space (read/write, all students)
└── course/                 course files (read-only)
    ├── R_packages/         shared R packages installed by the instructor
    ├── bin/                shared executables (added to PATH)
    └── [course materials]
```

On the host, place course files in `jupyterhub_volumes/course/`, collaborative files in `jupyterhub_volumes/shared/`, and collect student work from `jupyterhub_volumes/users/`.

### Installing shared R packages (instructor)

```bash
tools/install_packages.sh reshape2 plotly knitr
```

### Installing personal R packages (students)

```r
install.packages('mypackage')   # installs into work/R_packages/
```

### Loading packages (students)

```r
library(reshape2)   # searches: work/R_packages/ → work/course/R_packages/ → system
```

## User accounts

Defaults are set in `obijupyterhub/docker-compose.yml`:

| Account | Username | Password |
|---------|----------|----------|
| Admin | `admin` | `admin2025` |
| Students | any | `metabar2025` |

Change `JUPYTERHUB_ADMIN_PASSWORD` and `JUPYTERHUB_PASSWORD` in the compose file, then rerun `./start-jupyterhub.sh`.

To restrict access to a predefined list, edit `jupyterhub_config.py`:

```python
c.Authenticator.allowed_users = {'student1', 'student2', 'student3'}
```

## Customising the images

All image customisations require a rebuild. Use `--local-build` (or the targeted `--rebuild-*` flag) to apply changes locally, or `--publish` to push them to the registry.

### Add R packages baked into the student image

Edit `obijupyterhub/Dockerfile` (before `USER ${NB_UID}`):

```dockerfile
RUN R -e "install.packages(c('your_package'), repos='http://cran.rstudio.com/')"
```

Then rebuild:

```bash
./start-jupyterhub.sh --rebuild-student
```

### Add Python packages

Edit `obijupyterhub/Dockerfile` (before `USER ${NB_UID}`):

```dockerfile
RUN pip install numpy pandas matplotlib seaborn
```

Then rebuild:

```bash
./start-jupyterhub.sh --rebuild-student
```

### Change the listening port

In `obijupyterhub/docker-compose.yml`:

```yaml
ports:
  - "8001:80"   # accessible at http://localhost:8001
```

## Troubleshooting

**Docker daemon unavailable**: make sure OrbStack / Docker Desktop / the daemon is running.

**Student containers do not start**: run `docker-compose logs jupyterhub` from `obijupyterhub/` and confirm the student image is present:

```bash
docker images | grep obijupyterhub-student
```

**Port conflict**: change the published port in `docker-compose.yml`.

**Registry pull fails**: check your network, or fall back to a local build:

```bash
./start-jupyterhub.sh --local-build
```

**Start from scratch**:

```bash
./start-jupyterhub.sh --stop-server

cd obijupyterhub
docker-compose down -v
docker rmi jupyterhub-hub jupyterhub-student obijupyterhub-builder 2>/dev/null || true
docker rmi registry.metabarcoding.org/metabarschool/obijupyterhub-hub:latest \
           registry.metabarcoding.org/metabarschool/obijupyterhub-student:latest \
           registry.metabarcoding.org/metabarschool/obijupyterhub-builder:latest 2>/dev/null || true
cd ..

rm -rf jupyterhub_volumes/builder/R_packages   # clear R package cache

./start-jupyterhub.sh   # pull fresh images and start
```
