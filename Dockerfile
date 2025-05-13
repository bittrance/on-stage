FROM alpine:3.20

RUN apk --no-cache add bash git wget && \
    wget -q https://github.com/cli/cli/releases/download/v2.72.0/gh_2.72.0_linux_amd64.tar.gz && \
    tar xf gh_2.72.0_linux_amd64.tar.gz && \
    mv */bin/gh /usr/local/bin/gh && \
    rm -r gh_*

COPY entrypoint.sh /entrypoint.sh
RUN git config --global --add safe.directory /workspace
WORKDIR /workspace

ENTRYPOINT ["bash", "-c", "/entrypoint.sh"]
