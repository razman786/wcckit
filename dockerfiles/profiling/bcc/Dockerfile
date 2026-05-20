# syntax=docker/dockerfile:1
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
# BCC/eBPF profiling image for WCCKIT.
#
# Runtime note: BCC traces the host kernel. Running this image normally requires
# elevated permissions and host mounts such as /sys/kernel/debug, /lib/modules,
# and /usr/src. See README.md for example run commands and risks.
ARG BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04
FROM ${BASE_IMAGE}

ARG BCC_REPO=https://github.com/iovisor/bcc.git
ARG BCC_REF=v0.36.1
ARG FLAMEGRAPH_REPO=https://github.com/brendangregg/FlameGraph.git

LABEL org.opencontainers.image.title="wcckit-bcc-profiler" \
      org.opencontainers.image.description="Package-based BCC/eBPF profiling image for WCCKIT disk and pipeline characterisation" \
      org.opencontainers.image.source="https://github.com/iovisor/bcc"

ENV BCC_SRC=/src/bcc \
    FLAMEGRAPH_SRC=/src/FlameGraph \
    PATH=/usr/sbin:/usr/share/bcc/tools:/usr/share/bpfcc-tools:${PATH} \
    PYTHONPATH=/usr/lib/python3/dist-packages:/usr/local/lib/python3/dist-packages:${PYTHONPATH:-}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        arping \
        bpfcc-tools \
        ethtool \
        iputils-ping \
        libbpf-dev \
        libbpfcc \
        libbpfcc-dev \
        net-tools \
        python3-bpfcc \
        python3-netaddr \
        python3-pyroute2 \
        trace-cmd \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${BCC_REF}" "${BCC_REPO}" "${BCC_SRC}" \
    && git clone --depth 1 "${FLAMEGRAPH_REPO}" "${FLAMEGRAPH_SRC}" \
    && rm -rf "${BCC_SRC}/.git" "${FLAMEGRAPH_SRC}/.git"

COPY dockerfiles/profiling/bcc/tools-summary.txt /opt/wcckit/bcc-tools-summary.txt
COPY dockerfiles/profiling/bcc/bin/wcckit_profile_cpu.sh /usr/local/bin/wcckit_profile_cpu.sh

RUN chmod 0755 /usr/local/bin/wcckit_profile_cpu.sh

WORKDIR /work

CMD ["/bin/bash"]
