# DWCC: Node.js e Angular CLI. Sen SSH: VS Code ábrese en Debian por WSL e o seu
# terminal entra neste contedor con docker exec (docker/angular/DWCC-Angular.code-workspace).
FROM node:26-bookworm
ENV NG_CLI_ANALYTICS=false
RUN npm install --global @angular/cli@22 && npm cache clean --force
RUN install -d -o node -g node /home/node/proxectos
WORKDIR /home/node/proxectos
USER node
CMD ["sleep", "infinity"]
