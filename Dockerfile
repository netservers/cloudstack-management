FROM ubuntu:trusty
ENV TERM screen
EXPOSE 8080
RUN \
  groupadd -g 200 cloud && \
  useradd -d /var/lib/cloudstack/management -g 200 -u 200 -s /bin/false cloud && \
  apt-get update && \
  apt-get install -y \
    wget \
    nano \
    less \
    dnsutils \
    curl \
    uuid-runtime \
    openssh-client && \
  wget -O - http://cloudstack.apt-get.eu/release.asc | sudo apt-key add - && \
  echo "deb http://cloudstack.apt-get.eu/ubuntu trusty 4.9" >> /etc/apt/sources.list && \
  apt-get update && \
  apt-get install -y cloudstack-management && \
  apt-get clean && \
  mkdir -p /var/lib/cloudstack/management/.ssh && \
  ssh-keygen -f /var/lib/cloudstack/management/.ssh/id_rsa -N '' && \
  chown -R cloud:cloud /var/lib/cloudstack/management

COPY start.sh /start.sh
CMD ["/start.sh"]
