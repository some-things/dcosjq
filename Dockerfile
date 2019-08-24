FROM ubuntu:latest
LABEL maintainer="dustinmnemes@gmail.com"

RUN \
  apt update -y && \
  apt install -y \
    bc \
    bsdmainutils \
    curl \
    jq

ADD https://raw.githubusercontent.com/some-things/dcosjq/master/dcosjq.sh /usr/local/bin/dcosjq
ADD https://raw.githubusercontent.com/some-things/dcosjq/master/cluster-setup.sh /usr/local/bin/cluster-setup

RUN chmod +x /usr/local/bin/dcosjq /usr/local/bin/cluster-setup

CMD ["/bin/bash"]
