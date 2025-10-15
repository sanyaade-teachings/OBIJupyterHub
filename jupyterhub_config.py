import os

# Base configuration coucou
c.JupyterHub.spawner_class = 'dockerspawner.DockerSpawner'

# Enable debug logs
c.JupyterHub.log_level = 'DEBUG'
c.Spawner.debug = True

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
c.DockerSpawner.volumes = {
    # Personal volume (persistent) - root directory
    'jupyterhub-user-{username}': '/home/jovyan/work',
    # Shared volume between all students - under work/
    'jupyterhub-shared': '/home/jovyan/work/shared',
    # Shared read-only volume for course files - under work/
    'jupyterhub-course': {
        'bind': '/home/jovyan/work/course',
        'mode': 'ro'  # read-only
    }
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
