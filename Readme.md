# OBIJupyterHub - the DNA Metabarcoding Learning Server

## Intended use

This project packages the MetabarcodingSchool training lab into one reproducible bundle. You get Python, R, and Bash kernels, a Quarto-built course website, and preconfigured admin/student accounts, so onboarding a class is a single command instead of a day of setup. Everything runs locally on a single machine, student work persists between sessions, and `./start-jupyterhub.sh` takes care of building images, rendering the site, preparing volumes, and bringing JupyterHub up at `http://localhost:8888`. Defaults (accounts, passwords, volumes) live in the repo so instructors can tweak them quickly.

## Prerequisites (with quick checks)

You only need **Docker and Docker Compose** on the machine that will host the lab. All other tools (Quarto, Hugo, Python, R) are provided via a builder Docker image and do not need to be installed on your system.

- macOS: install [OrbStack](https://orbstack.dev/) (recommended) or Docker Desktop; both ship Docker Engine and Compose.
- Linux: install Docker Engine and the Compose plugin from your distribution (e.g., `sudo apt install docker.io docker-compose-plugin`) or from Docker’s official packages.
- Windows: install Docker Desktop with the WSL2 backend enabled.

Verify from a terminal:

```bash
docker --version
docker compose version    # or: docker-compose --version
```

## How the startup script works

`./start-jupyterhub.sh` is the single entry point. It builds the Docker images, renders the course website, prepares the volume folders, and starts the stack. Internally it:

- creates the `jupyterhub_volumes/` tree (caddy, course, shared, users, web...)
- builds the `obijupyterhub-builder` image (contains Quarto, Hugo, R, Python) if not already present
- builds `jupyterhub-student` and `jupyterhub-hub` images
- detects R package dependencies from Quarto files using the `{attachment}` package and installs them automatically
- renders the Quarto site from `web_src/`, generates PDF galleries and `pages.json`, and copies everything into `jupyterhub_volumes/web/`
- runs `docker-compose up -d --remove-orphans`

### Builder image

The builder image (`obijupyterhub-builder`) contains all the tools needed to prepare the course materials:

- **Quarto** for rendering the course website
- **Hugo** for building the obidoc documentation
- **R** with the `{attachment}` package for automatic dependency detection
- **Python 3** for utility scripts

This means you don't need to install any of these tools on your host system. The script automatically builds this image on first run and reuses it for subsequent builds. Use `--force-rebuild` to rebuild the builder image if needed.

### R package caching for builds

R packages required by your Quarto documents are automatically detected and installed during the build process. These packages are cached in `jupyterhub_volumes/builder/R_packages/` so they persist across builds. This means:

- **First build**: All R packages used in your `.qmd` files are detected and installed (may take some time)
- **Subsequent builds**: Only missing packages are installed, making builds much faster
- **Adding new packages**: Simply use `library(newpackage)` in your Quarto files; the build process will detect and install it automatically

To clear the R package cache and force a fresh installation, delete the `jupyterhub_volumes/builder/R_packages/` directory.

You can tailor what it does with a few flags:

- `--no-build` (or `--offline`): skip Docker image builds and reuse existing images (useful when offline).
- `--force-rebuild`: rebuild images without cache.
- `--stop-server`: stop the stack and remove student containers, then exit.
- `--update-lectures`: rebuild the course website only (no Docker stop/start).
- `--build-obidoc`: force rebuilding the obidoc documentation (auto-built if empty; skipped in offline mode).

## Installation and first run

1) Clone the project:

```bash
git clone https://forge.metabarcoding.org/MetabarcodingSchool/OBIJupyterHub.git
cd OBIJupyterHub
```

2) (Optional) glance at the structure you’ll populate:

```         
OBIJupyterHub
├── start-jupyterhub.sh                  - single entry point (build + render + start)
├── obijupyterhub                        - Docker images and stack definitions
│   ├── docker-compose.yml
│   ├── install_R_packages.R             - An R script used to install all need R packages
│   ├── Dockerfile                       - Image used by the students
│   ├── Dockerfile.hub                   - Image for the jupyter hub
│   ├── Dockerfile.builder               - Image for the builder
│   └── jupyterhub_config.py
├── jupyterhub_volumes                   - data persisted on the host
│   ├── builder                          - R packages cache for building lectures
│   ├── course                           - read-only for students (notebooks, data, bin, R packages)
│   ├── shared                           - shared read/write space for everyone
│   ├── users                            - per-user persistent data
│   └── web                              - rendered course website
└── web_src                              - Quarto sources for the course website
```

Note: The `tools/` directory contains utility scripts including `install_quarto_deps.R` for automatic R dependency detection.

3) Prepare course materials (optional before first run):
- Put notebooks, datasets, scripts, binaries, or PDFs for students under `jupyterhub_volumes/course/`. They will appear read-only at `/home/jovyan/work/course/`.
- For collaborative work, drop files in `jupyterhub_volumes/shared/` (read/write for all at `/home/jovyan/work/shared/`).
- Edit or add Quarto sources in `web_src/` to update the course website; the script will render them.

4) Start everything (build + render + launch):

```bash
./start-jupyterhub.sh
```

5) Access JupyterHub in a browser at `http://localhost:8888`.

6) Stop the stack when you’re done (run from `obijupyterhub/`):

```bash
docker-compose down
```

### Operating the stack (one command, a few options)

- Start or rebuild: `./start-jupyterhub.sh` (rebuilds images, regenerates the website, starts the stack).
- Start without rebuilding images (offline): `./start-jupyterhub.sh --no-build`
- Force rebuild without cache: `./start-jupyterhub.sh --force-rebuild`
- Stop only: `./start-jupyterhub.sh --stop-server`
- Rebuild website only (no Docker stop/start): `./start-jupyterhub.sh --update-lectures`
- Rebuild obidoc docs: `./start-jupyterhub.sh --build-obidoc` (also builds automatically if `jupyterhub_volumes/web/obidoc` is empty; skipped in offline mode)
- Access at `http://localhost:8888` (students: any username / password `metabar2025`; admin: `admin` / `admin2025`).
- Check logs from `obijupyterhub/` with `docker-compose logs -f jupyterhub`.
- Stop with `docker-compose down` (from `obijupyterhub/`). Rerun `./start-jupyterhub.sh` to start again or after config changes.

## Managing shared data

Each student lands in `/home/jovyan/work/` with three key areas: their own files, a shared space, and a read-only course space. Everything under `work/` is persisted on the host in `jupyterhub_volumes`.

```         
work/                             # Personal workspace root (persistent)
├── [student files]               # Their own files and notebooks
├── R_packages/                   # Personal R packages (writable by student)
├── shared/                       # Shared workspace (read/write, shared with all)
└── course/                       # Course files (read-only, managed by admin)
    ├── R_packages/               # Shared R packages (read-only, installed by prof)
    ├── bin/                      # Shared executables (in PATH)
    └── [course materials]        # Your course files
```

R looks for packages in this order: personal `work/R_packages/`, then shared `work/course/R_packages/`, then system libraries. Because everything lives under `work/`, student files survive restarts.

### User Accounts

Defaults are defined in `obijupyterhub/docker-compose.yml`: admin (`admin` / `admin2025`) with write access to `course/`, and students (any username, password `metabar2025`) with read-only access to `course/`. Adjust `JUPYTERHUB_ADMIN_PASSWORD` and `JUPYTERHUB_PASSWORD` there, then rerun `./start-jupyterhub.sh`.

### Installing R Packages (Admin Only)

From the host, install shared R packages into `course/R_packages/`:

``` bash
# Install packages
tools/install_packages.sh reshape2 plotly knitr
```

Students can install their own packages into their personal `work/R_packages/`:

```r
# Install in personal library (each student has their own)
install.packages('mypackage')  # Will install in work/R_packages/
```

### Using R Packages (Students)

Students simply load packages normally:

``` r
library(reshape2)  # R checks: 1) work/R_packages/ 2) work/course/R_packages/ 3) system
library(plotly)
```

R automatically searches in this order: 

1. Personal packages: `/home/jovyan/work/R_packages/` (R_LIBS_USER) 
1. Prof packages: `/home/jovyan/work/course/R_packages/` (R_LIBS_SITE) 
1. System packages

### List Available Packages

``` r
# List all available packages (personal + course + system)
installed.packages()[,"Package"]

# Check personal packages
list.files("/home/jovyan/work/R_packages")

# Check course packages (installed by prof)
list.files("/home/jovyan/work/course/R_packages")
```

### Deposit or retrieve course and student files

On the host, place course files in `jupyterhub_volumes/course/` (they appear read-only to students), shared files in `jupyterhub_volumes/shared/`, and collect student work from `jupyterhub_volumes/users/`.

## User Management

### Option 1: Predefined User List

In `jupyterhub_config.py`, uncomment and modify:

``` python
c.Authenticator.allowed_users = {'student1', 'student2', 'student3'}
```

### Option 2: Allow Everyone (for testing)

By default, the configuration allows any user:

``` python
c.Authenticator.allow_all = True
```

⚠️ **Warning**: DummyAuthenticator is ONLY for local testing!

## Kernel Verification

Once logged in, create a new notebook and verify you have access to: 

- **Python 3** (default kernel) 
- **R** (R kernel) 
- **Bash** (bash kernel)

## Customization for Your Labs

### Add Additional R Packages

Modify the `Dockerfile` (before `USER ${NB_UID}`):

``` dockerfile
RUN R -e "install.packages(c('your_package'), repos='http://cran.rstudio.com/')"
```

Then rerun `./start-jupyterhub.sh` to rebuild and restart.

### Add Python Packages

Add to the `Dockerfile` (before `USER ${NB_UID}`):

``` dockerfile
RUN pip install numpy pandas matplotlib seaborn
```

Then rerun `./start-jupyterhub.sh` to rebuild and restart.

### Change Port (if 8000 is occupied)

Modify in `docker-compose.yml`:

``` yaml
ports:
  - "8001:8000"  # Accessible on localhost:8001
```

## Advantages of This Approach

✅ **Everything in Docker**: No need to install Python/JupyterHub on your computer\
✅ **Portable**: Easy to deploy on another server\
✅ **Isolated**: No pollution of your system environment\
✅ **Easy to Clean**: A simple `docker-compose down` is enough\
✅ **Reproducible**: Students will have exactly the same environment

## Troubleshooting

- Docker daemon unavailable: make sure OrbStack/Docker Desktop/daemon is running; verify `/var/run/docker.sock` exists.
- Student containers do not start: check `docker-compose logs jupyterhub` and confirm the images exist with `docker images | grep jupyterhub-student`.
- Port conflict: change the published port in `docker-compose.yml`.


**I want to start from scratch**:

``` bash
pushd obijupyterhub
docker-compose down -v
docker rmi jupyterhub-hub jupyterhub-student obijupyterhub-builder
popd

# Optionally clear the R package cache
rm -rf jupyterhub_volumes/builder/R_packages

# Then rebuild everything
./start-jupyterhub.sh
```
