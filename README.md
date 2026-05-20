# WCCKIT

[![CI](https://github.com/razman786/wcckit/actions/workflows/ci.yml/badge.svg)](https://github.com/razman786/wcckit/actions/workflows/ci.yml)

Copyright (c) 2026, Dr Rahim Lakhoo.  
Licensed under the GNU General Public License v2.0. See [`LICENSE`](LICENSE).

WCCKIT is the Workload Characterisation and Capacity Kit: a practical toolkit for
profiling and characterising radio-astronomy and astrophysics processing
workloads on Linux systems.

It follows the direction of the Workload Characterisation Framework from the
SKA Telescope Local Monioring and Control Design: reproducible measurement, provenance capture, operating-system profiling, runtime resource utilisation, bottleneck location, and comparison across software and hardware versions.

## 🔭 What This Repository Contains

- `opti_disk/`: disk and CPU tuning helpers for radio-astronomy style processing
  pipelines. This is a focused subset of WCCKIT for investigating disk speed,
  efficiency, and relevant system settings.
- `dockerfiles/`: reproducible Ubuntu 24.04 profiler images.
- `examples/profiling/`: small validation workloads for checking that profiling
  works before pointing WCCKIT at a real pipeline.

Some scripts can touch low-level system state. Use dry-run modes first, check the
planned target device carefully, and do not run destructive storage commands
against real hardware unless you have verified the target.

## 🚀 Quick Start: Build The Profiler

From a fresh clone on the machine where the pipeline will run:

```bash
git clone https://github.com/razman786/wcckit.git
cd wcckit
```

Install host dependencies and build the profiler images:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh
```

The installer checks that the host is Ubuntu 24.04, installs the host packages
needed for Docker builds, checks Docker access, and builds:

- `wcckit/ubuntu-profiling-base:24.04`
- `wcckit/bcc-profiler:24.04`

If Docker was just installed and your user cannot access it yet:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

Then rerun the installer without reinstalling packages:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --no-apt
```

## 🔥 Profile A Pipeline PID

Find the host process ID for the pipeline step you want to profile:

```bash
pgrep -af python
pgrep -af wsclean
pgrep -af DP3
pgrep -af casa
pgrep -af singularity
```

Create an output directory and generate a CPU flame graph:

```bash
mkdir -p profile-output

dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh \
    --pid 1234 \
    --duration 15 \
    --frequency 99 \
    --output /out/perf.svg
```

The SVG appears on the host at:

```text
./profile-output/perf.svg
```

Open it in a browser and inspect the widest frames first.

## 🧪 Validate With A Python Hotspot

Before profiling a real pipeline, run the synthetic Python workload. It repeatedly
calls one intentionally expensive function and records the exact source line used
as the hotspot.

```bash
examples/profiling/profile_python_hotspot.sh
```

This writes:

```text
profile-output/python-hotspot.svg
profile-output/python-hotspot.log
```

The log includes the target PID and source-line anchor:

```text
PID=12345
HOTSPOT=/path/to/wcckit/examples/profiling/python_hotspot.py:37
HOTSPOT_FUNCTION=wcckit_intentional_hotspot
```

The SVG subtitle also records the `HOTSPOT=` line. Depending on Python/perf-map
support on the host, the flame graph may show `wcckit_intentional_hotspot`
directly, or it may show native CPython and math frames such as
`_PyEval_EvalFrameDefault`, `math_sin`, and `math_cos`. In both cases, the log
and subtitle identify the source line being exercised.

Manual version:

```bash
python3 -X perf examples/profiling/python_hotspot.py --duration 120
```

Then profile the printed PID from another terminal:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output -- \
  wcckit_profile_cpu.sh \
    --pid <PID> \
    --duration 15 \
    --frequency 99 \
    --output /out/python-hotspot.svg \
    --subtitle "Target hotspot: <HOTSPOT_FROM_LOG>"
```

## 🧰 Useful Examples

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

Start an interactive profiler shell:

```bash
dockerfiles/bin/run-wcckit-profiler.sh --out ./profile-output
cat /opt/wcckit/bcc-tools-summary.txt
```

Run BCC tools directly:

```bash
dockerfiles/bin/run-wcckit-profiler.sh -- biolatency-bpfcc
dockerfiles/bin/run-wcckit-profiler.sh -- runqlat-bpfcc
```

Useful packaged BCC command names include:

```text
biolatency-bpfcc
biosnoop-bpfcc
opensnoop-bpfcc
runqlat-bpfcc
profile-bpfcc
execsnoop-bpfcc
```

## ⚙️ What The Docker Wrapper Does

The host launcher is:

```bash
dockerfiles/bin/run-wcckit-profiler.sh
```

It mounts your chosen output directory as `/out` and starts the BCC profiler
container with host PID visibility and the kernel tracing mounts needed for BCC.
The effective Docker run shape is:

```bash
docker run -it --rm \
  --privileged \
  --pid=host \
  --net=host \
  -v "$PWD":/out \
  -v /etc/localtime:/etc/localtime:ro \
  -v /tmp:/tmp:ro \
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
narrower capability/security profile only after validating the exact BCC tools
you need.

For Python targets started with `python3 -X perf`, host `/tmp` is mounted
read-only so BCC can read Python perf map files such as `/tmp/perf-<PID>.map`
when the interpreter creates them.

Do not bake `linux-headers-$(uname -r)` into the image at build time. During a
Docker build, `uname -r` reports the host kernel, which may not correspond to an
Ubuntu package available inside the image. Mount `/lib/modules` and `/usr/src` at
runtime so BCC sees the headers for the kernel it is tracing.

## 🛑 Stop The Container

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

The wrapper uses `--rm`, so the stopped container is removed automatically. The
Docker image remains installed.

## 🏗️ Advanced Manual Build

The installer script is preferred for Ubuntu 24.04 users. Advanced users can
build manually.

```bash
docker build \
  -t wcckit/ubuntu-profiling-base:24.04 \
  -f dockerfiles/base/ubuntu-24.04.4/Dockerfile \
  .

docker build \
  -t wcckit/bcc-profiler:24.04 \
  -f dockerfiles/profiling/bcc/Dockerfile \
  --build-arg BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04 \
  .
```

The base Dockerfile uses `FROM ubuntu:24.04` because Docker's official Ubuntu
images are tagged by LTS series rather than each point release. After
`apt-get update`, the userspace package set identifies as the current Ubuntu
24.04 LTS point release.

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

## 🧭 Why Split The Images?

The base image holds common Linux build and profiling prerequisites. Derived
images can add BCC, bpftrace, perf-only tooling, fio-specific tooling, or
radio-astronomy pipeline-specific profilers without duplicating the base system.

That matches the WCCKIT direction: standardised, reproducible, verifiable
workload characterisation with enough provenance to compare measurements across
systems and tool selections.
