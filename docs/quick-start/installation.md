# Installation

WCCKIT targets Ubuntu 24.04 hosts for the current Docker-based workflow. The installer builds the Docker images used by the viewer and collector roles.

## Clone the Repository

Use the same repository on the laptop and compute node:

```bash
git clone https://github.com/razman786/wcckit.git
cd wcckit
```

## Laptop or Desktop: Viewer Role

The viewer role needs Docker and the compose stack. It does not need privileged BPF or hardware-counter access.

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only
```

This prepares the machine to run Grafana, InfluxDB, and Pyroscope.

## Compute Node: Collector Role

The collector role builds the images used for BPF, perf, Intel PCM, AMD uProf, and the WCCKIT wrappers.

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only
```

The collector container is privileged when it runs because BPF, perf, PCM, and uProf need host visibility. Building the image is not itself a profiling run.

## AMD uProf Package

Default collector builds do not require AMD uProf. To include AMD uProf, download the `.deb` package from the AMD uProf page, accept AMD's browser EULA, and place it in the repository root before building:

```text
wcckit/amduprof_5.3-518_amd64.deb
```

The installer auto-detects a local `amduprof_*.deb`. You can also pass a path explicitly:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh \
  --collector-only \
  --amd-uprof-deb ./amduprof_5.3-518_amd64.deb
```

AMD e-smi is downloaded into normal collector images by default from AMD's public `.deb` URL. Use `--no-amd-esmi` for offline or CI-style builds.

## Docker Group Access

If Docker was just installed and your current shell cannot access it:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

Then rerun the installer without host package installation:

```bash
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --viewer-only --no-apt
dockerfiles/bin/install-wcckit-profiler-ubuntu2404.sh --collector-only --no-apt
```

## Package Conflicts

If apt reports a `containerd.io` conflict, the host likely has mixed Docker package sources. Keep one Docker package family. If Docker already works, rerun WCCKIT with `--no-apt` rather than forcing a second Docker installation.
