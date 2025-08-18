# scripts/server: Server (VM) provisioning scripts

Last updated: 2025-08-18 16:42

Purpose
- This folder contains shell scripts meant to be run inside an Ubuntu Server machine (typically a VM) to install Docker and provision common developer/DevOps services.
- These scripts are designed to be copied to the VM at: $HOME/Projects/tools and executed from there.

What’s here
- setup-docker.sh: Installs Docker Engine, CLI, Buildx, Compose; adds your user to the docker group.
- setup-server.sh: Orchestrator that (re)creates the full stack of services in a clean way. Run it as non-root: ./setup-server.sh <domain>.
- setup-*-server.sh: Individual service installers (nginx, prometheus, grafana, postgresql, redis, nexus, gitea, jenkins, rancher, ollama, faster-whisper, dns, etc.).
- backup/: Utilities to back up and restore Docker volumes (see backup/README.md).

CI/CD focus
- Core CI/CD components: Jenkins (CI), Gitea (Git hosting/SCM), Nexus (artifact registry).
- Typical flow: Developer pushes to Gitea → webhook triggers a Jenkins pipeline → artifacts published to Nexus → deployments served via Docker/Nginx.
- To provision only CI/CD parts, run the individual scripts: setup-gitea-server.sh, setup-jenkins-server.sh, setup-nexus-server.sh (plus setup-nginx-server.sh if you want a reverse proxy).

How to use (summary)
1) Copy all files in this directory to the VM at $HOME/Projects/tools (see scripts/README.md for scp/rsync examples).
2) On the VM, make the scripts executable: chmod +x $HOME/Projects/tools/*.sh
3) Install Docker (run as root): sudo $HOME/Projects/tools/setup-docker.sh
4) Provision services (run as your normal user, not root):
   - cd $HOME/Projects/tools
   - ./setup-server.sh <domain>

Notes
- These scripts expect helper functions at $HOME/Projects/tools/functions.sh (copy scripts/functions.sh from the repo to that location on the VM).
- This folder was previously named scripts/virtual-machine; it has been renamed to scripts/server to better reflect the purpose.
