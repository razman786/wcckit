# syntax=docker/dockerfile:1
# Copyright (c) 2026, Raz.
# SPDX-License-Identifier: GPL-2.0-only
# Combined WCCKIT pipeline profiler image: BCC/eBPF + Intel PCM + app tracing.
ARG BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04
FROM ${BASE_IMAGE}

ARG BCC_REPO=https://github.com/iovisor/bcc.git
ARG BCC_REF=v0.36.1
ARG FLAMEGRAPH_REPO=https://github.com/brendangregg/FlameGraph.git

LABEL org.opencontainers.image.title="wcckit-pipeline-profiler" \
      org.opencontainers.image.description="Combined BCC/eBPF, Intel PCM, and application runtime profiling image for WCCKIT" \
      org.opencontainers.image.source="https://github.com/razman786/wcckit"

ENV BCC_SRC=/src/bcc \
    FLAMEGRAPH_SRC=/src/FlameGraph \
    PATH=/usr/local/bin:/usr/sbin:/usr/share/bcc/tools:/usr/share/bpfcc-tools:${PATH} \
    PYTHONPATH=/usr/lib/python3/dist-packages:/usr/local/lib/python3/dist-packages:${PYTHONPATH:-}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bpfcc-tools \
        curl \
        jq \
        libbpf-dev \
        libbpfcc \
        libbpfcc-dev \
        pcm \
        python-is-python3 \
        python3-bpfcc \
    && rm -rf /var/lib/apt/lists/*

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
    && command -v pcm \
    && command -v pcm-sensor-server \
    && command -v pythonflow.sh \
    && command -v pythoncalls.sh \
    && command -v pythonstat.sh

WORKDIR /work

CMD ["/bin/bash"]
