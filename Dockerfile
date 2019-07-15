FROM ubuntu:latest
LABEL maintainer="dustinmnemes@gmail.com"

RUN \
  apt update -y && \
  apt install -y \
    bc \
    bsdmainutils \
    curl \
    jq

ADD dcosjq.sh /usr/local/bin/dcosjq
ADD cluster-setup.sh /usr/local/bin/cluster-setup

CMD ["/bin/bash"]
