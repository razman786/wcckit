# syntax=docker/dockerfile:1
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
# Combined WCCKIT pipeline profiler image: BCC/eBPF + Intel PCM + AMD uProf + app tracing.
#
# AMD uProf is EULA-governed AMD software. WCCKIT does not commit or
# redistribute the AMD .deb. Operational WCCKIT pipeline images use
# INCLUDE_AMD_UPROF=1 for mixed Intel/AMD fleets. Initiating an AMD-enabled
# Docker build is treated as the build operator's instruction to install AMD
# uProf under AMD's EULA. The .deb payload is extracted directly so package
# post-install scripts do not try to configure host kernel drivers during image
# build. CI explicitly overrides this with INCLUDE_AMD_UPROF=0.
ARG BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04
FROM ${BASE_IMAGE}

ARG BCC_REPO=https://github.com/iovisor/bcc.git
ARG BCC_REF=v0.36.1
ARG FLAMEGRAPH_REPO=https://github.com/brendangregg/FlameGraph.git
ARG INCLUDE_AMD_UPROF=1
ARG AMD_UPROF_DEB=dockerfiles/profiling/pipeline/no-amduprof.deb
ARG AMD_UPROF_URL=
ARG AMD_UPROF_MD5=32ab052e45b8c5ffebc8bda901baef02
ARG AMD_UPROF_INSTALL_DIR=/opt/AMDuProf

LABEL org.opencontainers.image.title="wcckit-pipeline-profiler" \
      org.opencontainers.image.description="Combined BCC/eBPF, Intel PCM, AMD uProf, and application runtime profiling image for WCCKIT" \
      org.opencontainers.image.source="https://github.com/razman786/wcckit"

ENV BCC_SRC=/src/bcc \
    FLAMEGRAPH_SRC=/src/FlameGraph \
    PATH=/usr/local/bin:/usr/sbin:/usr/share/bcc/tools:/usr/share/bpfcc-tools:${PATH} \
    PYTHONPATH=/usr/lib/python3/dist-packages:/usr/local/lib/python3/dist-packages:${PYTHONPATH:-}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bpfcc-tools \
        ca-certificates \
        curl \
        jq \
        libbpf-dev \
        libbpfcc \
        libbpfcc-dev \
        pcm \
        python-is-python3 \
        python3-bpfcc \
    && rm -rf /var/lib/apt/lists/*

ADD ${AMD_UPROF_DEB} /tmp/amduprof-local.deb

RUN set -eux; \
    if [ "${INCLUDE_AMD_UPROF}" = "1" ]; then \
        if ! grep -q "WCCKIT placeholder" /tmp/amduprof-local.deb; then \
            cp /tmp/amduprof-local.deb /tmp/amduprof.deb; \
        elif [ -n "${AMD_UPROF_URL}" ]; then \
            printf '%s\n' "Downloading AMD uProf during Docker build. By initiating this AMD-enabled build, the build operator accepts AMD's EULA."; \
            curl --http1.1 --retry 3 --retry-delay 5 --retry-connrefused -fL "${AMD_UPROF_URL}" -o /tmp/amduprof.deb; \
        else \
            printf '%s\n' "INCLUDE_AMD_UPROF=1 requires AMD_UPROF_DEB or AMD_UPROF_URL." >&2; \
            printf '%s\n' "Provide AMD uProf from https://www.amd.com/en/developer/uprof.html or use WCCKIT's default AMD_UPROF_URL." >&2; \
            exit 1; \
        fi; \
        if [ -n "${AMD_UPROF_MD5}" ]; then \
            printf '%s  %s\n' "${AMD_UPROF_MD5}" /tmp/amduprof.deb | md5sum -c -; \
        fi; \
        dpkg-deb -x /tmp/amduprof.deb /; \
        amd_uprof_pcm="$(find /opt /usr -type f -name AMDuProfPcm -perm /111 2>/dev/null | head -n 1)"; \
        test -n "${amd_uprof_pcm}"; \
        mkdir -p "${AMD_UPROF_INSTALL_DIR}"; \
        ln -sf "${amd_uprof_pcm}" /usr/local/bin/AMDuProfPcm; \
        command -v AMDuProfPcm; \
    fi; \
    rm -f /tmp/amduprof.deb /tmp/amduprof-local.deb; \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${BCC_REF}" "${BCC_REPO}" "${BCC_SRC}" \
    && git clone --depth 1 "${FLAMEGRAPH_REPO}" "${FLAMEGRAPH_SRC}" \
    && rm -rf "${BCC_SRC}/.git" "${FLAMEGRAPH_SRC}/.git" \
    && for tool in pythonflow.sh pythoncalls.sh pythonstat.sh javaflow.sh javacalls.sh javastat.sh \
        perlflow.sh perlcalls.sh perlstat.sh phpflow.sh phpcalls.sh phpstat.sh \
        rubyflow.sh rubycalls.sh rubystat.sh tclflow.sh tclcalls.sh tclstat.sh; do \
            if [ -x "${BCC_SRC}/tools/${tool}" ]; then \
                ln -sf "${BCC_SRC}/tools/${tool}" "/usr/local/bin/${tool}"; \
            fi; \
        done \
    && ln -sfn "${BCC_SRC}/tools/lib" /usr/local/bin/lib

COPY dockerfiles/profiling/bcc/bin/wcckit_profile_cpu.sh /usr/local/bin/wcckit_profile_cpu.sh
COPY dockerfiles/profiling/pipeline/bin/ /usr/local/bin/

RUN chmod 0755 /usr/local/bin/wcckit_profile_cpu.sh \
    /usr/local/bin/wcckit_profile_pipeline.sh \
    /usr/local/bin/wcckit_jsonl_to_influx.py \
    /usr/local/bin/wcckit_parse_app_tools.py \
    /usr/local/bin/wcckit_parse_bpf_io.py \
    /usr/local/bin/wcckit_parse_amd_uprof_pcm.py \
    && command -v pcm \
    && command -v pcm-sensor-server \
    && command -v pythonflow.sh \
    && command -v pythoncalls.sh \
    && command -v pythonstat.sh

WORKDIR /work

CMD ["/bin/bash"]
