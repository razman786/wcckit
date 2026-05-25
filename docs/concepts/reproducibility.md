# Reproducibility

WCCKIT is designed around repeatable characterisation rather than one-off benchmarking.

A useful run should answer:

- Which pipeline was profiled?
- Which PID and command window were observed?
- Which collector options were enabled?
- Which CPU vendor and hardware counter backend were selected?
- Which tools were available or unavailable?
- Which raw files support the dashboard view?
- Did any collector fail, timeout, or report no data?

## Compare Runs Carefully

Hardware counter availability, CPU frequency behaviour, kernel version, container privileges, BPF support, and pipeline input size all affect results. WCCKIT records these where practical, but interpretation still requires care.

## Avoid Unsupported Claims

Do not claim a setting improves performance unless it has been measured on a representative workload. WCCKIT helps collect the evidence; it does not make performance claims by itself.
