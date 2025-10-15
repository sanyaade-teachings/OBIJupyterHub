import os
import logging
from pathlib import Path


# Base configuration coucou
c.JupyterHub.spawner_class = 'dockerspawner.DockerSpawner'

# Enable debug logs
c.JupyterHub.log_level = 'DEBUG'
c.Spawner.debug = True

VOLUMES_BASE_PATH = '/volumes'

# Docker image to use for student containers
c.DockerSpawner.image = 'jupyterhub-student:latest'

# Docker network (create with: docker network create jupyterhub-network)
c.DockerSpawner.network_name = 'jupyterhub-network'

# Connection to OrbStack Docker socket from the hub container
c.DockerSpawner.client_kwargs = {'base_url': 'unix:///var/run/docker.sock'}

# IMPORTANT: Internal URL for communication between containers
# The hub container communicates with user containers via Docker network
c.JupyterHub.hub_ip = '0.0.0.0'
c.JupyterHub.hub_connect_ip = 'jupyterhub'

c.DockerSpawner.environment = {
    # R package library in read-only course directory under work/
    'R_LIBS_USER': '/home/jovyan/work/R_packages',
    'R_LIBS_SITE': '/home/jovyan/work/course/R_packages:/usr/local/lib/R/site-library:/usr/lib/R/site-library'
}
# Network configuration for student containers
c.DockerSpawner.use_internal_ip = True
c.DockerSpawner.network_name = 'jupyterhub-network'
c.DockerSpawner.extra_host_config = {'network_mode': 'jupyterhub-network'}

# Remove containers after disconnection (optional, set to False to keep containers)
c.DockerSpawner.remove = True

# Container naming
c.DockerSpawner.name_template = "jupyter-{username}"

# Volume mounting to persist student data
# Set root to work/ - everything is persistent
notebook_dir = '/home/jovyan/work'
c.DockerSpawner.notebook_dir = notebook_dir

# Personal volume for each student + shared volumes under work/
# Pre-spawn hook to create user directory
async def create_user_dir(spawner):
    """Create user directory if it doesn't exist"""
    user_dir = os.path.join(VOLUMES_BASE_PATH, spawner.user.name)
    spawner.log.info(f"Ensured user directory exists: {user_dir}")
    Path(user_dir).mkdir(parents=True, exist_ok=True)
    os.chmod(user_dir, 0o755)

c.Spawner.pre_spawn_hook = create_user_dir

c.DockerSpawner.volumes = {
    # Personal volume (persistent) - root directory
    'obijupyterhub_shared-{username}' : '/home/jovyan/work',
    # Shared volume between all students - under work/
    'obijupyterhub_shared': '/home/jovyan/work/shared',
    # Shared read-only volume for course files - under work/
    'obijupyterhub_course': {
        'bind': '/home/jovyan/work/course',
        'mode': 'ro'  # read-only
    }
}

c.DockerSpawner.volume_driver = 'local'
c.DockerSpawner.volume_driver_opts = {
    'type': 'none',
    'device': '/volumes',
    'o': 'bind'
}
# Memory and CPU configuration (adjust according to your needs)
c.DockerSpawner.mem_limit = '2G'
c.DockerSpawner.cpu_limit = 1.0

# User configuration - Simple password authentication for lab
from jupyterhub.auth import DummyAuthenticator

class SimplePasswordAuthenticator(DummyAuthenticator):
    """Simple authenticator with a shared password for everyone"""
    
    def check_allowed(self, username, authentication=None):
        """Check if user is allowed"""
        if authentication is None:
            return False
        
        provided_password = authentication.get('password', '')
        
        # Admin user with special password
        if username == 'admin':
            admin_password = os.environ.get('JUPYTERHUB_ADMIN_PASSWORD', 'admin2025')
            return provided_password == admin_password
        
        # Regular students with shared password
        student_password = os.environ.get('JUPYTERHUB_PASSWORD', 'metabar2025')
        return provided_password == student_password

c.JupyterHub.authenticator_class = SimplePasswordAuthenticator

# To create a list of allowed users, uncomment and modify:
# c.Authenticator.allowed_users = {'student1', 'student2', 'student3'}

# Or allow any user with the correct password:
c.Authenticator.allow_all = True

# Admin configuration
c.Authenticator.admin_users = {'admin'}

# Listening port
c.JupyterHub.bind_url = 'http://0.0.0.0:8000/jupyter/'

# Timeout
c.Spawner.start_timeout = 300
c.Spawner.http_timeout = 120

# Post-start hook to create R_packages directory after volumes are mounted
c.DockerSpawner.cmd = ['start-notebook.sh']
