# syntax=docker/dockerfile:1
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
# WCCKIT profiling base image for the Ubuntu 24.04.4 LTS target.
#
# This image intentionally contains only common Linux build, profiling, and
# inspection dependencies. Tool-specific images, such as BCC/eBPF, should build
# FROM this image so each profiler stack can be selected independently.
# The official Ubuntu Docker image is tagged by LTS series; apt updates
# bring the image to the current 24.04 point-release package set.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC

LABEL org.opencontainers.image.title="wcckit-ubuntu-profiling-base" \
      org.opencontainers.image.description="Ubuntu 24.04 base image for WCCKIT profiling tool images" \
      org.opencontainers.image.version="24.04.4" \
      org.opencontainers.image.source="https://github.com/razman786/wcckit"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=${TZ} \
    WCCKIT_SRC=/src \
    WCCKIT_TOOLS=/opt/wcckit

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        bash \
        binutils \
        bison \
        build-essential \
        ca-certificates \
        clang \
        cmake \
        coreutils \
        curl \
        dwarves \
        elfutils \
        file \
        flex \
        g++ \
        gcc \
        git \
        gnupg \
        iproute2 \
        kmod \
        less \
        libaudit-dev \
        libclang-dev \
        libdw-dev \
        libedit-dev \
        libelf-dev \
        libfl-dev \
        liblzma-dev \
        libzstd-dev \
        linux-tools-common \
        linux-tools-generic \
        llvm \
        llvm-dev \
        lsb-release \
        make \
        man-db \
        ninja-build \
        numactl \
        openssl \
        pkg-config \
        procps \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-venv \
        python3-wheel \
        strace \
        sudo \
        tar \
        tzdata \
        unzip \
        vim-tiny \
        xz-utils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu's /usr/bin/perf and /usr/bin/cpupower wrappers look for tools matching
# the running host kernel. In containers this often mismatches the image package
# set, so expose the packaged Ubuntu 24.04 tools directly on PATH.
RUN set -eux; \
    tools_dir="$(find /usr/lib -maxdepth 1 -type d -name 'linux-tools-*' | sort -V | tail -n 1)"; \
    test -n "${tools_dir}"; \
    for tool in perf cpupower bpftool turbostat x86_energy_perf_policy; do \
        if [ -x "${tools_dir}/${tool}" ]; then \
            ln -sf "${tools_dir}/${tool}" "/usr/local/bin/${tool}"; \
        fi; \
    done; \
    perf --version; \
    cpupower --version

RUN mkdir -p "${WCCKIT_SRC}" "${WCCKIT_TOOLS}"

WORKDIR ${WCCKIT_SRC}

CMD ["/bin/bash"]
