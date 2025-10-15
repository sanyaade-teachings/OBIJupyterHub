# JupyterHub Configuration with OrbStack on Mac (all in Docker)

## Prerequisites
- OrbStack installed and running

## File Structure

Your `~/jupyterhub-tp` directory should contain:
```
~/jupyterhub-tp/
├── Dockerfile                  # Image for students (already created)
├── Dockerfile.hub              # Image for JupyterHub (new)
├── jupyterhub_config.py        # Configuration
├── docker-compose.yml          # Orchestration
└── start-jupyterhub.sh         # Startup script
```

## Installation Steps

### 1. Create Directory Structure

```bash
mkdir -p ~/jupyterhub-tp
cd ~/jupyterhub-tp
```

### 2. Create All Necessary Files

Create the following files with the content from artifacts:
- `Dockerfile` (artifact "Dockerfile for JupyterHub with R and Bash")
- `Dockerfile.hub` (artifact "Dockerfile for JupyterHub container")
- `jupyterhub_config.py` (artifact "JupyterHub Configuration")
- `docker-compose.yml` (artifact "docker-compose.yml")
- `start-jupyterhub.sh` (artifact "start-jupyterhub.sh")

### 3. Make Startup Script Executable

```bash
chmod +x start-jupyterhub.sh
```

### 4. Start JupyterHub

```bash
./start-jupyterhub.sh
```

### 5. Access JupyterHub

Open your browser and go to: **http://localhost:8888**

You can log in with any username and password: `metabar2025`

## Useful Commands

### View JupyterHub logs
```bash
docker-compose logs -f jupyterhub
```

### View all containers (hub + students)
```bash
docker ps
```

### Stop JupyterHub
```bash
docker-compose down
```

### Restart JupyterHub (after config modification)
```bash
docker-compose restart jupyterhub
```

### Rebuild after Dockerfile modification
```bash
# For student image
docker build -t jupyterhub-student:latest -f Dockerfile .
docker-compose restart jupyterhub

# For hub image
docker-compose up -d --build
```

### View logs for a specific student
```bash
docker logs jupyter-username
```

### Clean up after lab
```bash
# Stop and remove all containers
docker-compose down

# Remove student containers
docker ps -a | grep jupyter- | awk '{print $1}' | xargs docker rm -f

# Remove volumes (WARNING: deletes student data)
docker volume ls | grep jupyterhub-user | awk '{print $2}' | xargs docker volume rm

# Clean everything (containers + volumes + network)
docker-compose down -v
docker ps -a | grep jupyter- | awk '{print $1}' | xargs docker rm -f
docker volume prune -f
```

## Managing Shared Data

### Directory Structure for Each Student

Each student will see this directory structure in their JupyterLab (everything under `work/` is persistent):
```
work/                              # Personal workspace root (persistent)
├── [student files]               # Their own files and notebooks
├── R_packages/                   # Personal R packages (writable by student)
├── shared/                       # Shared workspace (read/write, shared with all)
└── course/                       # Course files (read-only, managed by admin)
    ├── R_packages/               # Shared R packages (read-only, installed by prof)
    ├── bin/                      # Shared executables (in PATH)
    └── [course materials]        # Your course files
```

**R Package Priority:**
1. R checks `work/R_packages/` first (personal, writable)
2. Then `work/course/R_packages/` (shared, read-only, installed by prof)
3. Then system libraries

**Important:** Everything is under `work/`, so all student files are automatically saved in their persistent volume.

### User Accounts

**Admin Account:**
- Username: `admin`
- Password: `admin2025` (change in docker-compose.yml: `JUPYTERHUB_ADMIN_PASSWORD`)
- Can write to `course/` directory

**Student Accounts:**
- Username: any name
- Password: `metabar2025` (change in docker-compose.yml: `JUPYTERHUB_PASSWORD`)
- Read-only access to `course/` directory

### Installing R Packages (Admin Only)

**From your Mac (recommended):**

```bash
chmod +x install-r-packages-admin.sh

# Install packages
./install-r-packages-admin.sh reshape2 plotly knitr
```

This script:
- Installs packages in the `course/R_packages/` directory
- All students can use them (read-only)
- No need to rebuild the image

**From admin notebook:**

Login as `admin` and create an R notebook:

```r
# Install packages in course/R_packages (admin only, available to all students)
course_lib <- "/home/jovyan/work/course/R_packages"
dir.create(course_lib, recursive = TRUE, showWarnings = FALSE)

install.packages(c('reshape2', 'plotly', 'knitr'), 
                 lib = course_lib,
                 repos = 'http://cran.rstudio.com/')
```

Note: Admin account has write access to the course directory.

**Students can also install their own packages:**

Students can install packages in their personal `work/R_packages/`:

```r
# Install in personal library (each student has their own)
install.packages(c('mypackage'))  # Will install in work/R_packages/
```

### Using R Packages (Students)

Students simply load packages normally:
```r
library(reshape2)  # R checks: 1) work/R_packages/ 2) work/course/R_packages/ 3) system
library(plotly)
```

R automatically searches in this order:
1. Personal packages: `/home/jovyan/work/R_packages/` (R_LIBS_USER)
2. Prof packages: `/home/jovyan/work/course/R_packages/` (R_LIBS_SITE)
3. System packages

### List Available Packages

```r
# List all available packages (personal + course + system)
installed.packages()[,"Package"]

# Check personal packages
list.files("/home/jovyan/work/R_packages")

# Check course packages (installed by prof)
list.files("/home/jovyan/work/course/R_packages")
```

### Deposit Files for Course

To put files in the `course/` directory (accessible read-only):

```bash
# Create a temporary directory
mkdir -p ~/jupyterhub-tp/course-files

# Copy your files into it
cp my_notebooks.ipynb ~/jupyterhub-tp/course-files/
cp my_data.csv ~/jupyterhub-tp/course-files/

# Copy into Docker volume
docker run --rm \
  -v jupyterhub-course:/target \
  -v ~/jupyterhub-tp/course-files:/source \
  alpine sh -c "cp -r /source/* /target/"
```

### Access Shared Files Between Students

Students can collaborate via the `shared/` directory:

```python
# In a notebook, to read a shared file
import pandas as pd
df = pd.read_csv('/home/jovyan/work/shared/group_data.csv')

# To write a shared file
df.to_csv('/home/jovyan/work/shared/alice_results.csv')
```

### Retrieve Student Work

```bash
# List user volumes
docker volume ls | grep jupyterhub-user

# Copy files from a specific student
docker run --rm \
  -v jupyterhub-user-alice:/source \
  -v ~/submissions:/target \
  alpine sh -c "cp -r /source/* /target/alice/"

# Copy all shared work
docker run --rm \
  -v jupyterhub-shared:/source \
  -v ~/submissions/shared:/target \
  alpine sh -c "cp -r /source/* /target/"
```

## User Management

### Option 1: Predefined User List
In `jupyterhub_config.py`, uncomment and modify:
```python
c.Authenticator.allowed_users = {'student1', 'student2', 'student3'}
```

### Option 2: Allow Everyone (for testing)
By default, the configuration allows any user:
```python
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
```dockerfile
RUN R -e "install.packages(c('your_package'), repos='http://cran.rstudio.com/')"
```

Then rebuild:
```bash
docker build -t jupyterhub-student:latest -f Dockerfile .
docker-compose restart jupyterhub
```

### Add Python Packages
Add to the `Dockerfile` (before `USER ${NB_UID}`):
```dockerfile
RUN pip install numpy pandas matplotlib seaborn
```

### Distribute Files to Students
Create a `files_lab/` directory and add to the `Dockerfile`:
```dockerfile
COPY files_lab/ /home/${NB_USER}/lab/
RUN chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}/lab
```

### Change Port (if 8000 is occupied)
Modify in `docker-compose.yml`:
```yaml
ports:
  - "8001:8000"  # Accessible on localhost:8001
```

## Advantages of This Approach

✅ **Everything in Docker**: No need to install Python/JupyterHub on your Mac  
✅ **Portable**: Easy to deploy on another Mac or server  
✅ **Isolated**: No pollution of your system environment  
✅ **Easy to Clean**: A simple `docker-compose down` is enough  
✅ **Reproducible**: Students will have exactly the same environment

## Troubleshooting

**Error "Cannot connect to Docker daemon"**:
- Check that OrbStack is running
- Verify the socket exists: `ls -la /var/run/docker.sock`

**Student containers don't start**:
- Check logs: `docker-compose logs jupyterhub`
- Verify student image exists: `docker images | grep jupyterhub-student`

**Port 8000 already in use**:
- Change port in `docker-compose.yml`

**After config modification, changes are not applied**:
```bash
docker-compose restart jupyterhub
```

**I want to start from scratch**:
```bash
docker-compose down -v
docker rmi jupyterhub-hub jupyterhub-student
# Then rebuild everything
./start-jupyterhub.sh
```
