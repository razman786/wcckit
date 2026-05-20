# WCCKIT Profiling Docker Images

Copyright (c) 2026, Dr Rahim Lakhoo.  
SPDX-License-Identifier: GPL-3.0-or-later

These Dockerfiles provide a reproducible Linux profiling environment for
WCCKIT-style workload characterisation. The immediate target is radio-astronomy
and astrophysics processing pipelines where we need to understand CPU, scheduler,
I/O, filesystem, and kernel behaviour while a pipeline is running.

Most users should start with the installer script, then profile a process ID
(PID). The manual Docker build commands are kept later for advanced users.

## Quick Start On Ubuntu 24.04

From a fresh clone of WCCKIT on the machine where the pipeline will run:

```bash
git clone https://github.com/razman786/wcckit.git
cd wcckit
```

Install host dependencies and build the profiler images:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh
```

The installer:

- checks that the host is Ubuntu 24.04;
- installs host packages needed to build and run Docker images;
- checks Docker daemon access;
- builds the Ubuntu 24.04.4-target base image;
- builds the WCCKIT BCC/eBPF profiler image.

If Docker was just installed and your user cannot access it yet, run:

```bash
sudo usermod -aG docker "$USER"
```

Then log out and back in, or run:

```bash
newgrp docker
```

Then rerun:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --no-apt
```

## Profile A Pipeline PID

Find the host process ID of the pipeline step to profile. Examples:

```bash
pgrep -af python
pgrep -af wsclean
pgrep -af DP3
pgrep -af casa
pgrep -af singularity
```

Suppose the target PID is `1234`. Create an output directory:

```bash
mkdir -p profile-output
```

Generate a CPU flame graph:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh \
    --pid 1234 \
    --duration 15 \
    --frequency 99 \
    --output /out/perf.svg
```

The SVG will appear on the host at:

```text
./profile-output/perf.svg
```

Open that file in a browser.

## Examples

Profile a Python-based calibration or reduction task for 30 seconds:

```bash
PID=$(pgrep -n -f python)
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh --pid "$PID" --duration 30 --output /out/python-cpu.svg
```

Profile a `wsclean` process:

```bash
PID=$(pgrep -n -f wsclean)
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh --pid "$PID" --duration 20 --frequency 99 --output /out/wsclean-cpu.svg
```

Start an interactive profiler shell and inspect available tools:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output
cat /opt/wcckit/bcc-tools-summary.txt
```

Run an I/O latency tool directly:

```bash
dockerfiles/bin/run-wcckit-profiler.sh -- biolatency-bpfcc
```

Run a scheduler latency tool directly:

```bash
dockerfiles/bin/run-wcckit-profiler.sh -- runqlat-bpfcc
```

## What The Wrapper Does

The host launcher is:

```bash
dockerfiles/bin/run-wcckit-profiler.sh
```

It starts the profiler container with the host kernel mounts needed for BCC/eBPF
profiling and mounts your chosen output directory as `/out`.

Use a specific host output directory:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output
```

Use a different profiler image tag:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --image wcckit/bcc-profiler:24.04
```

Or with an environment variable:

```bash
WCCKIT_PROFILER_IMAGE=wcckit/bcc-profiler:24.04 dockerfiles/bin/run-wcckit-profiler.sh
```

## What The CPU Flamegraph Wrapper Does

Inside the container, this command:

```bash
wcckit_profile_cpu.sh --pid 1234 --duration 15 --frequency 99 --output /out/perf.svg
```

wraps:

```bash
/src/bcc/tools/profile.py -dF 99 -f 15 -p "$PID" \
  | /src/FlameGraph/flamegraph.pl > /out/perf.svg
```

Because `/out` is a bind mount, the SVG is written back to the host.

## Useful BCC Commands

Ubuntu's packaged BCC tools use the `-bpfcc` suffix. Examples:

```bash
biolatency-bpfcc
biosnoop-bpfcc
opensnoop-bpfcc
runqlat-bpfcc
profile-bpfcc
execsnoop-bpfcc
```

A short tool guide is available inside the container:

```bash
cat /opt/wcckit/bcc-tools-summary.txt
```

## Runtime Notes And Privileges

BCC/eBPF tools profile the host kernel. A container does not have its own kernel,
so the profiler container needs host PID visibility and kernel tracing mounts.
The wrapper uses:

```bash
docker run -it --rm \
  --privileged \
  --pid=host \
  --net=host \
  -v "$PWD":/out \
  -v /etc/localtime:/etc/localtime:ro \
  -v /sys/kernel/debug:/sys/kernel/debug:rw \
  -v /sys/kernel/tracing:/sys/kernel/tracing:rw \
  -v /sys/fs/bpf:/sys/fs/bpf:rw \
  -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  -v /lib/modules:/lib/modules:ro \
  -v /usr/src:/usr/src:ro \
  wcckit/bcc-profiler:24.04
```

`--privileged` is broad, but it is the practical baseline for BCC in a container.
Use this on trusted profiling machines. For production systems, replace it with a
narrower capability/security profile only after validating the specific BCC tools
you need.

Do not bake `linux-headers-$(uname -r)` into this image at build time. During a
Docker build, `uname -r` reports the host kernel, which may not correspond to an
Ubuntu package available inside the image. Mount the host's `/lib/modules` and
`/usr/src` at runtime so BCC sees the headers for the kernel it is tracing.

## Stop The Container

Inside the container:

```bash
exit
```

or press `Ctrl+D`. If a profiling tool is running, stop it first with `Ctrl+C`.

From another terminal:

```bash
docker ps
docker stop <container_id_or_name>
```

Because the wrapper uses `--rm`, the container is removed automatically after it
stops. The Docker image remains installed.

## Advanced Manual Build

The installer script is preferred for Ubuntu 24.04 users. Advanced users can
build the images manually.

Build the Ubuntu 24.04.4-target base image:

```bash
docker build \
  -t wcckit/ubuntu-profiling-base:24.04 \
  -f dockerfiles/base/ubuntu-24.04.4/Dockerfile \
  .
```

Build the BCC/eBPF profiling image:

```bash
docker build \
  -t wcckit/bcc-profiler:24.04 \
  -f dockerfiles/profiling/bcc/Dockerfile \
  --build-arg BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04 \
  .
```

The base Dockerfile uses `FROM ubuntu:24.04` because Docker's official Ubuntu
images are tagged by LTS series rather than every point release. After
`apt-get update`, the userspace package set identifies as Ubuntu 24.04.4 LTS.

The BCC image installs Ubuntu 24.04's packaged BCC stack:

```text
bpfcc-tools
python3-bpfcc
libbpfcc
libbpfcc-dev
```

It also includes reference/source trees for:

```text
/src/bcc
/src/FlameGraph
```

Override the BCC source checkout when you need a different reference revision:

```bash
docker build \
  -t wcckit/bcc-profiler:bcc-master \
  -f dockerfiles/profiling/bcc/Dockerfile \
  --build-arg BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04 \
  --build-arg BCC_REF=master \
  .
```

## Why Split The Images?

The base image provides common Linux build and profiling prerequisites. Derived
images can add BCC, bpftrace, perf-only tooling, fio-specific tooling, or
radio-astronomy pipeline-specific profilers without duplicating the base system.

This matches the WCCKIT direction: standardised, reproducible, verifiable
workload characterisation with enough provenance to compare measurements across
systems and tool selections.
