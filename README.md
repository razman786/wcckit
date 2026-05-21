# WCCKIT

[![CI](https://github.com/razman786/wcckit/actions/workflows/ci.yml/badge.svg)](https://github.com/razman786/wcckit/actions/workflows/ci.yml)

Copyright (c) 2026, Raz.
Licensed under the GNU General Public License v2.0. See [`LICENSE`](LICENSE).

WCCKIT is the Workload Characterisation and Capacity Kit: a practical toolkit for
profiling and characterising radio-astronomy and astrophysics processing
workloads on Linux systems.

It follows the direction of the Workload Characterisation Framework from the
SKA Telescope Local Monitoring and Control Design: reproducible measurement, provenance capture, operating-system profiling, runtime resource utilisation, bottleneck location, and comparison across software and hardware versions.

![WCCKIT profiling architecture](docs/images/wcckit-profiler-overview.svg)

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

Install host dependencies and build the profiler images. For normal WCCKIT
pipeline servers, the installer builds the pipeline image with AMD uProf included
so the same image works across mixed Intel and AMD CPU fleets. First download
`amduprof_5.3-518_amd64.deb` from AMD in a browser, accepting AMD's EULA, and
place it in the repository root:

```text
wcckit/amduprof_5.3-518_amd64.deb
```

Then build:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh
```

By instructing WCCKIT/Codex to initiate this AMD-enabled Docker build, the user
is instructing the build to install AMD uProf under AMD's EULA. WCCKIT extracts
the `.deb` payload into the image rather than running AMD's package post-install
script, because Docker builds cannot safely configure host kernel drivers,
headers, debugfs, or tracefs. WCCKIT does not commit or redistribute AMD's `.deb`
package in git; local AMD uProf packages are ignored. For CI-only or deliberately
Intel-only development builds, pass `--no-amd-uprof`.

The installer checks that the host is Ubuntu 24.04, installs the host packages
needed for Docker builds, checks Docker access, and builds:

- `wcckit/ubuntu-profiling-base:24.04`
- `wcckit/bcc-profiler:24.04`
- `wcckit/pipeline-profiler:24.04`

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
pgrep -af DDFacet
pgrep -af wsclean
pgrep -af DP3
pgrep -af casa
pgrep -af singularity
pgrep -af '<My Pipeline>'
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

![Simplified flame graph readout](docs/images/wcckit-flamegraph-readout.svg)

For disk fio runs under `opti_disk/`, use `--target-dir` when the mounted test
filesystem cannot be inferred unambiguously from the selected NVMe device.

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

## 📊 Pipeline Profiling With BCC + Hardware Counters + InfluxDB/Grafana

The first combined pipeline-profiler round uses one privileged collector image
and one separate viewer/backend stack:

```text
wcckit/pipeline-profiler:24.04     BCC/eBPF + Intel PCM + AMD uProf + app/runtime tools
InfluxDB + Grafana Docker Compose   unprivileged local analysis UI
```

InfluxDB is the first backend because radio-astronomy pipeline telemetry can be
dense, irregular, and phase-specific. Grafana reads from InfluxDB, while WCCKIT
still writes raw artifacts to disk so a run can be inspected, reprocessed, and
compared later. Grafana is a view, not the source of truth.

The collector aligns three layers of behaviour:

```text
PCM                 hardware/socket/core/memory/PCIe telemetry
BCC/eBPF            kernel, I/O, scheduler, syscall, and flamegraph telemetry
ucalls/ustat/uflow  application/runtime alignment for languages such as Python
```

Start the local InfluxDB + Grafana stack:

```bash
dockerfiles/bin/run-wcckit-viewer.sh
```

Development defaults are printed by the wrapper:

```text
Grafana:  http://localhost:3000  admin / wcckit
InfluxDB: http://localhost:8086
Org:      wcckit
Bucket:   wcckit
Token:    wcckit-dev-token
```

![Intel PCM to Grafana flow](docs/images/wcckit-pcm-grafana-flow.svg)

Find the target pipeline PID and run the combined collector. This example uses
DDFacet as a Python radio-astronomy pipeline target:

```bash
PID=$(pgrep -n -f DDFacet)

dockerfiles/bin/run-wcckit-pipeline-profiler.sh \
  --pid "$PID" \
  --duration 120 \
  --pipeline DDFacet \
  --language python \
  --run-id ddfacet-test-001 \
  --out runs/ddfacet-test-001 \
  --influx-url http://127.0.0.1:8086 \
  --influx-org wcckit \
  --influx-bucket wcckit \
  --influx-token wcckit-dev-token
```

Open Grafana at:

```text
http://localhost:3000
```

The viewer provisions three dashboards:

```text
WCCKIT Pipeline Overview
Intel® Performance Counter Monitor (Intel® PCM) Dashboard
AMD uProf / AMDuProfPcm Dashboard
```

The `WCCKIT Pipeline Overview` dashboard is the run/artifact view: run markers,
collector status, bounded BPF summaries, application summaries, hardware-counter
sample counts, and WCCKIT-owned line protocol. The first BPF I/O panel is fed
from `biolatency-bpfcc -j` summary samples because this produces bounded,
low-cardinality block-I/O telemetry that is suitable for InfluxDB. Raw per-I/O
event streams, for example from `biosnoop`, should stay as JSONL artifacts or be
exported only as bounded summaries. The overview hardware-counter panel counts
Intel PCM scrape samples when PCM is available and AMD uProf PCM samples on AMD
hosts. The application-runtime panel uses language runtime summaries when BCC can
attach to the target runtime; when Python USDT probes are unavailable, WCCKIT
also records a bounded per-PID syscall summary so the panel still shows useful
runtime activity and marks the language-level probes unavailable. The Intel PCM
and AMD uProf dashboards are the hardware-counter detail views.

The Intel PCM dashboard follows Intel's `scripts/grafana` architecture: a
`pcm-sensor-server` runs on the profiled host and the unprivileged viewer stack
scrapes it with Telegraf into InfluxDB. The combined collector starts
`pcm-sensor-server` while `--pcm` is enabled, so on an Intel PCM-supported host
the dashboard begins filling during the profiling window. By default the viewer
looks for PCM at:

```text
http://host.docker.internal:9738/persecond/
```

For a remote Intel host, start the viewer with an explicit PCM sensor URL:

```bash
WCCKIT_PCM_SENSOR_URL=http://target-host:9738/persecond/ \
  dockerfiles/bin/run-wcckit-viewer.sh
```

If no `pcm-sensor-server` is running yet, the Telegraf bridge stays up and logs
connection errors until a PCM sensor endpoint appears. On AMD or unsupported
Intel systems, `pcm-sensor-server` will not produce PCM metrics; WCCKIT still
records collector status so Grafana can show that the PCM collector was attempted
and failed rather than silently displaying an empty PCM view.

### Hardware Counters: Intel PCM And AMD uProf

Use `--hardware-counters auto` for the default backend selection. WCCKIT chooses
Intel PCM on `GenuineIntel` CPUs and AMD uProf / `AMDuProfPcm` on
`AuthenticAMD` CPUs. You can force a backend when needed:

```bash
--hardware-counters intel-pcm
--hardware-counters amd-uprof
--hardware-counters none
```

Intel PCM is the Intel CPU backend. AMD uProf / `AMDuProfPcm` is the first AMD
CPU-equivalent backend in WCCKIT. Omnitrace and Omniperf are useful future
integrations, especially for wrapped application tracing and ROCm/GPU profiling,
but they are not the first CPU equivalent to Intel PCM.

For operational WCCKIT pipeline servers, build the pipeline profiler image with
`INCLUDE_AMD_UPROF=1` so the same image can run on mixed Intel and AMD CPU
fleets. This is the default installer and Dockerfile behaviour. AMD's download
endpoint requires browser EULA acceptance before the `.deb` is served, so the
normal path is to download `amduprof_5.3-518_amd64.deb`, place it in the repo
root, and let the installer pass it into the Docker build. By initiating the
AMD-enabled build, the user/build operator is instructing WCCKIT to install AMD
uProf under AMD's EULA. WCCKIT extracts the `.deb` payload directly rather than
running AMD's post-install driver setup during image build. WCCKIT does not
commit or redistribute AMD's `.deb` package in this repository. CI is the
explicit exception and uses `INCLUDE_AMD_UPROF=0`. If an image was deliberately
built without AMD uProf,
`--hardware-counters amd-uprof` records an unavailable collector status rather
than failing the full profiling run.

Build with a local AMD uProf `.deb`:

```bash
mkdir -p third_party
# Download amduprof_5.3-518_amd64.deb from:
# https://www.amd.com/en/developer/uprof.html
# Building with this package means you accept AMD's EULA.
cp ~/Downloads/amduprof_5.3-518_amd64.deb third_party/

docker build \
  -t wcckit/pipeline-profiler:24.04 \
  -f dockerfiles/profiling/pipeline/Dockerfile \
  --build-arg BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04 \
  --build-arg INCLUDE_AMD_UPROF=1 \
  --build-arg AMD_UPROF_DEB=third_party/amduprof_5.3-518_amd64.deb \
  --build-arg AMD_UPROF_MD5=32ab052e45b8c5ffebc8bda901baef02 \
  .
```

Run an AMD uProf hardware-counter collection with:

```bash
PID=$(pgrep -n -f DDFacet)

dockerfiles/bin/run-wcckit-pipeline-profiler.sh \
  --pid "$PID" \
  --duration 120 \
  --pipeline DDFacet \
  --language python \
  --hardware-counters amd-uprof \
  --run-id ddfacet-amd-001 \
  --out runs/ddfacet-amd-001 \
  --influx-url http://127.0.0.1:8086 \
  --influx-org wcckit \
  --influx-bucket wcckit \
  --influx-token wcckit-dev-token
```

Hardware counters are generally system, core, or socket-level observations and
may not be strictly per-PID. BCC and perf remain better for PID attribution. The
AMD backend runs the PID-targeted IPC collector by default. System-level memory
and power sidecar collectors are available with `--amd-uprof-memory` and
`--amd-uprof-power`; their raw CSV and JSONL artifacts remain under
`runs/<run_id>/events/` as `amd-uprof-memory.*` and `amd-uprof-power.*`.

Memory and power support are platform dependent. On some AMD CPUs,
`AMDuProfPcm -m memory` may report the memory metric as unsupported. Power
collection may require host support such as the AMD HSMP driver; when unavailable
WCCKIT records collector status and keeps the raw AMD uProf warning in the run
logs instead of pretending the metric exists. These sidecar collectors are opt-in
because concurrent PMU collection can interfere with PID-targeted IPC samples.

The host artifacts remain under the run directory:

```text
runs/ddfacet-test-001/
  manifest.json
  events/
  metrics/influx.lp
  flamegraphs/
  logs/
```

The collector is privileged and observes the host kernel. Use it only on systems
where this is acceptable. PCM counters are hardware/system-level and are not
strictly per-PID; BCC and perf provide stronger PID attribution. `uflow` can
produce dense method-flow traces, so raw flow capture is opt-in via
`--app-flow-raw`. By default WCCKIT exports bounded summaries to InfluxDB and
keeps raw/reproducible records on disk.

Reference visuals and background:

- Intel PCM command-line and Grafana screenshots: <https://github.com/intel/pcm>
- Intel PCM Grafana stack notes: <https://github.com/intel/pcm/tree/master/scripts/grafana>
- AMD uProf downloads: <https://www.amd.com/en/developer/uprof.html>
- AMD Lab Notes profilers: <https://github.com/amd/amd-lab-notes/tree/release/profilers>
- AMD uProf documentation: <https://docs.amd.com/r/en-US/57368-uProf-user-guide/uProf-User-Guide>
- Brendan Gregg's CPU flame graph examples: <https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html>

The images embedded in this README are WCCKIT-owned schematic diagrams, not
copies of the upstream screenshots.

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

docker build \
  -t wcckit/pipeline-profiler:24.04 \
  -f dockerfiles/profiling/pipeline/Dockerfile \
  --build-arg BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04 \
  --build-arg INCLUDE_AMD_UPROF=1 \
  --build-arg AMD_UPROF_DEB=amduprof_5.3-518_amd64.deb \
  --build-arg AMD_UPROF_MD5=32ab052e45b8c5ffebc8bda901baef02 \
  .
```

For CI-only or deliberately Intel-only builds, override the pipeline image with
`--build-arg INCLUDE_AMD_UPROF=0`.

The base Dockerfile uses `FROM ubuntu:24.04` because Docker's official Ubuntu
images are tagged by LTS series rather than each point release. After
`apt-get update`, the userspace package set identifies as the current Ubuntu
24.04 LTS point release.

The BCC image installs Ubuntu 24.04's packaged BCC stack. The pipeline image
extends that direction with Intel PCM, AMD uProf for mixed CPU fleets, and
Python application-alignment wrappers:

```text
bpfcc-tools
python3-bpfcc
libbpfcc
libbpfcc-dev
pcm
AMDuProfPcm from AMD uProf .deb
python-is-python3
pythonflow.sh / pythoncalls.sh / pythonstat.sh
```

It also includes reference/source trees for:

```text
/src/bcc
/src/FlameGraph
```

The default BCC source checkout is pinned by `BCC_REF` in the Dockerfile rather
than following `master`, so CI and user builds are reproducible. Override the BCC
source checkout when you need a different reference revision:

```bash
docker build \
  -t wcckit/bcc-profiler:bcc-v0.35.0 \
  -f dockerfiles/profiling/bcc/Dockerfile \
  --build-arg BASE_IMAGE=wcckit/ubuntu-profiling-base:24.04 \
  --build-arg BCC_REF=v0.35.0 \
  .
```

## 🧭 Why Split The Images?

The base image holds common Linux build and profiling prerequisites, including
Ubuntu 24.04 `perf`, `cpupower`, `bpftool`, `turbostat`, and related linux-tools.
Derived images can add BCC, bpftrace, perf-only workflows, fio-specific tooling,
or radio-astronomy pipeline-specific profilers without duplicating the base
system.

That matches the WCCKIT direction: standardised, reproducible, verifiable
workload characterisation with enough provenance to compare measurements across
systems and tool selections.
