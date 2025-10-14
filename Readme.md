# Configuration JupyterHub avec OrbStack sur Mac (tout en Docker)

## Prérequis
- OrbStack installé et démarré

## Structure des fichiers

Votre dossier `~/jupyterhub-tp` doit contenir :
```
~/jupyterhub-tp/
├── Dockerfile                  # Image pour les étudiants (déjà créée)
├── Dockerfile.hub              # Image pour JupyterHub (nouvelle)
├── jupyterhub_config.py        # Configuration
└── docker-compose.yml          # Orchestration
```

## Étapes d'installation

### 1. Créer la structure de dossiers

```bash
mkdir -p ~/jupyterhub-tp
cd ~/jupyterhub-tp
```

### 2. Créer tous les fichiers nécessaires

Créez les fichiers suivants avec le contenu des artifacts :
- `Dockerfile` (artifact "Dockerfile pour JupyterHub avec R et Bash")
- `Dockerfile.hub` (artifact "Dockerfile pour le container JupyterHub")
- `jupyterhub_config.py` (artifact "Configuration JupyterHub")
- `docker-compose.yml` (artifact "docker-compose.yml")

### 3. Construire les images Docker

```bash
# Image pour les étudiants
docker build -t jupyterhub-student:latest -f Dockerfile .

# Image pour le hub JupyterHub
docker build -t jupyterhub-hub:latest -f Dockerfile.hub .
```

### 4. Démarrer JupyterHub avec Docker Compose

```bash
docker-compose up -d
```

### 5. Accéder à JupyterHub

Ouvrez votre navigateur et allez à : **http://localhost:8000**

Vous pouvez vous connecter avec n'importe quel nom d'utilisateur.

## Commandes utiles

### Voir les logs de JupyterHub
```bash
docker-compose logs -f jupyterhub
```

### Voir tous les containers (hub + étudiants)
```bash
docker ps
```

### Arrêter JupyterHub
```bash
docker-compose down
```

### Redémarrer JupyterHub (après modification du config)
```bash
docker-compose restart jupyterhub
```

### Reconstruire après modification du Dockerfile
```bash
# Pour l'image étudiants
docker build -t jupyterhub-student:latest -f Dockerfile .
docker-compose restart jupyterhub

# Pour l'image hub
docker-compose up -d --build
```

### Voir les logs d'un étudiant spécifique
```bash
docker logs jupyter-nom_utilisateur
```

### Nettoyer après le TP
```bash
# Arrêter et supprimer tous les containers
docker-compose down

# Supprimer les containers étudiants
docker ps -a | grep jupyter- | awk '{print $1}' | xargs docker rm -f

# Supprimer les volumes (ATTENTION : supprime les données étudiants)
docker volume ls | grep jupyterhub-user | awk '{print $2}' | xargs docker volume rm

# Tout nettoyer (containers + volumes + réseau)
docker-compose down -v
docker ps -a | grep jupyter- | awk '{print $1}' | xargs docker rm -f
docker volume prune -f
```

## Gestion des données partagées

### Structure des dossiers pour chaque étudiant

Chaque étudiant verra ces dossiers dans son JupyterLab :
- **`work/`** : Son espace personnel (persistant, privé)
- **`shared/`** : Espace partagé entre tous les étudiants (lecture/écriture)
- **`course/`** : Fichiers du cours (lecture seule, vous déposez les fichiers)

### Déposer des fichiers pour le cours

Pour mettre des fichiers dans le dossier `course/` (accessible en lecture seule) :

```bash
# Créer un dossier temporaire
mkdir -p ~/jupyterhub-tp/course-files

# Copier vos fichiers dedans
cp mes_notebooks.ipynb ~/jupyterhub-tp/course-files/
cp mes_donnees.csv ~/jupyterhub-tp/course-files/

# Copier dans le volume Docker
docker run --rm \
  -v jupyterhub-course:/target \
  -v ~/jupyterhub-tp/course-files:/source \
  alpine sh -c "cp -r /source/* /target/"
```

### Accéder aux fichiers partagés entre étudiants

Les étudiants peuvent collaborer via le dossier `shared/` :

```python
# Dans un notebook, pour lire un fichier partagé
import pandas as pd
df = pd.read_csv('/home/jovyan/shared/donnees_groupe.csv')

# Pour écrire un fichier partagé
df.to_csv('/home/jovyan/shared/resultats_alice.csv')
```

### Récupérer les travaux des étudiants

```bash
# Lister les volumes utilisateurs
docker volume ls | grep jupyterhub-user

# Copier les fichiers d'un étudiant spécifique
docker run --rm \
  -v jupyterhub-user-alice:/source \
  -v ~/rendus:/target \
  alpine sh -c "cp -r /source/* /target/alice/"

# Copier tous les travaux partagés
docker run --rm \
  -v jupyterhub-shared:/source \
  -v ~/rendus/shared:/target \
  alpine sh -c "cp -r /source/* /target/"
```

## Gestion des utilisateurs

### Option 1 : Liste d'utilisateurs prédéfinis
Dans `jupyterhub_config.py`, décommentez et modifiez :
```python
c.Authenticator.allowed_users = {'etudiant1', 'etudiant2', 'etudiant3'}
```

### Option 2 : Autoriser tout le monde (pour tests)
Par défaut, la configuration autorise n'importe quel utilisateur :
```python
c.Authenticator.allow_all = True
```

⚠️ **Attention** : DummyAuthenticator est UNIQUEMENT pour les tests locaux !

## Vérification des kernels

Une fois connecté, créez un nouveau notebook et vérifiez que vous avez accès à :
- **Python 3** (kernel par défaut)
- **R** (kernel R)
- **Bash** (kernel bash)

## Personnalisation pour vos TP

### Ajouter des packages R supplémentaires
Modifiez le `Dockerfile` (avant `USER ${NB_UID}`) :
```dockerfile
RUN R -e "install.packages(c('votre_package'), repos='http://cran.rstudio.com/')"
```

Puis reconstruisez :
```bash
docker build -t jupyterhub-student:latest -f Dockerfile .
docker-compose restart jupyterhub
```

### Ajouter des packages Python
Ajoutez dans le `Dockerfile` (avant `USER ${NB_UID}`) :
```dockerfile
RUN pip install numpy pandas matplotlib seaborn
```

### Distribuer des fichiers aux étudiants
Créez un dossier `files_tp/` et ajoutez dans le `Dockerfile` :
```dockerfile
COPY files_tp/ /home/${NB_USER}/tp/
RUN chown -R ${NB_UID}:${NB_GID} /home/${NB_USER}/tp
```

### Changer le port (si 8000 est occupé)
Modifiez dans `docker-compose.yml` :
```yaml
ports:
  - "8001:8000"  # Accessible sur localhost:8001
```

## Avantages de cette approche

✅ **Tout en Docker** : Plus besoin d'installer Python/JupyterHub sur votre Mac  
✅ **Portable** : Facile à déployer sur un autre Mac ou serveur  
✅ **Isolé** : Pas de pollution de votre environnement système  
✅ **Facile à nettoyer** : Un simple `docker-compose down` suffit  
✅ **Reproductible** : Les étudiants auront exactement le même environnement

## Dépannage

**Erreur "Cannot connect to Docker daemon"** :
- Vérifiez qu'OrbStack est démarré
- Vérifiez que le socket existe : `ls -la /var/run/docker.sock`

**Les containers étudiants ne démarrent pas** :
- Vérifiez les logs : `docker-compose logs jupyterhub`
- Vérifiez que l'image étudiants existe : `docker images | grep jupyterhub-student`

**Port 8000 déjà utilisé** :
- Changez le port dans `docker-compose.yml`

**Après modification du config, les changements ne sont pas pris en compte** :
```bash
docker-compose restart jupyterhub
```

**Je veux repartir de zéro** :
```bash
docker-compose down -v
docker rmi jupyterhub-hub jupyterhub-student
# Puis reconstruire tout
```