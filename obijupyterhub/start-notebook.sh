#!/bin/bash
set -e

# Function to create directory
create_r_packages_dir() {
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ -d "/home/jovyan/work" ]; then
            mkdir -p /home/jovyan/work/R_packages
            echo "R_packages directory created successfully"
            return 0
        fi
        echo "Waiting for work directory to be mounted (attempt $attempt/$max_attempts)..."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo "Warning: Could not verify work directory mount"
    return 1
}

# Create R_packages directory
create_r_packages_dir

# Start the single-user server
exec jupyterhub-singleuser "$@"
