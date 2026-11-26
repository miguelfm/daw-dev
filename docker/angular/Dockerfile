FROM node:26-bookworm
ENV NG_CLI_ANALYTICS=false
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server && rm -rf /var/lib/apt/lists/* && rm -f /etc/ssh/ssh_host_* && mkdir -p /run/sshd
RUN npm install --global @angular/cli@22 && npm cache clean --force
RUN mkdir -p /home/node/proxectos && chown node:node /home/node/proxectos
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
CMD ["sh", "/usr/local/bin/entrypoint.sh"]
