# AURORA — RAN Metrics Collection Framework

AURORA = POSIX shared-memory metrics framework embedded in OpenAirInterface 5G (OAI).
Exposes live RAN state snapshot to external observers through single
`struct aurora_metrics` region in System V shared memory, updated continuously by running gNB process.

---

## Architecture

```
  OAI gNB process                         External consumer
  ─────────────────────────────────       ─────────────────────────
  MAC scheduler      ─┐
  RLC/PDCP layer     ─┤─► aurora_update_*() ─► shmget/shmat
  GTP-U tunneling    ─┘     aurora.c           (struct aurora_metrics)
                              │                       │
                       reset thread              aurora_reader
                    (clears each interval)    (reads & prints)

  Thread metrics subsystem (aurora_thread):
  ─────────────────────────────────────────
  /proc/self/task/  ──► aurora_thread_proc.c   ─┐
  (procfs fallback)     (polling collector)     │
                                                ├─► thread_stats[]
  sched_switch eBPF ──► aurora_thread_ebpf.c   ─┘   in shared memory
  (nanosecond res.)     (BPF map merge agent)
                              │
                    aurora_thread_registry.c  — discover / whitelist / allocate slots
                    aurora_thread_stats.c     — Procedure-1 histogram → statistics
```

### Shared Memory

| Parameter | Value |
|-----------|-------|
| IPC mechanism | System V `shmget` / `shmat` |
| Key | Configured via `shm_key` in `.conf` file (default `0xDEADBEEF`) |
| Size | `sizeof(struct aurora_metrics)` |
| Permissions | `0666` (world-readable) |

### Data Model

- Up to **100 UEs** (`MAX_NO_UEs`) tracked simultaneously
- Up to **36 radio bearers per UE** (`MAX_RBS_PER_UE`): 4 SRBs + 32 DRBs
- Up to **64 named worker threads** (`AURORA_MAX_MONITORED_THREADS`) profiled simultaneously
- All traffic counters **aggregated across all UEs** into single value per traffic flow
- Per-UE MAC/RLC/PDCP/GTP stats stored in per-UE arrays indexed by `rnti % MAX_NO_UEs`
- Metrics **reset every collection interval** (default 100 ms) by background thread
- **Delta vs. cumulative**: traffic-flow, HARQ, CRC, FAPI, histogram metrics = interval-deltas (reset to zero each interval). RLC/PDCP/GTP packet+byte counters also converted to interval-deltas using static previous-value snapshots. RC handover counters reset each interval. TC queue packet counters store per-interval change. Process resource-usage counters (`ru_*`, except `ru_maxrss_kb`) report delta since last interval. Thread runtime histograms+counters also reset each interval; derived statistics recomputed just before reset.

### RAN Node Types

AURORA operates in one of five modes, selected by `ran_type` config parameter:

| Value | Meaning | Traffic metrics collected |
|-------|---------|--------------------------|
| `RAN_GNB` | Monolithic gNB | BH, MH, F1-RLC, RLC-MAC, MAC-RLC, MAC-DL-BO, HARQ, CRC, FAPI |
| `RAN_DU` | CU-DU split — DU side | BH-RX, MH, F1-RLC, RLC-F1, RLC-MAC, MAC-RLC, MAC-DL-BO, HARQ, CRC, FAPI |
| `RAN_CU` | CU (combined CU-CP+CU-UP) | BH, MH |
| `RAN_CU_UP` | CU-UP only | BH, MH |
| `RAN_CU_CP` | CU-CP only (control plane) | none (control plane only) |

---

## Configuration

Add `aurora` block to `.conf` file of each OAI process. Three mandatory fields: `collection_interval_ms`, `shm_key`, `ran_type`. `thread_metrics_*` fields optional — control per-thread runtime distribution subsystem.

### Thread Metrics Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `thread_metrics_enabled` | `"yes"` | Enable (`"yes"`/`"1"`) or disable (`"no"`/`"0"`) per-thread collection |
| `thread_metrics_backend` | `"auto"` | `"auto"` tries eBPF first, falls back to procfs; `"ebpf"` forces eBPF (fails if unavailable); `"procfs"` always uses procfs polling |
| `thread_metrics_whitelist` | (see per-type below) | Comma-separated thread names to monitor. Trailing `*` = prefix wildcard: `Tpool*` matches `Tpool0_-1`, `Tpool1_2`, etc. Max 512 chars. |

---

### RAN_GNB — Monolithic gNB (L1 + MAC + RLC/PDCP + GTP + SDAP)

All layers run in single process. Whitelist covers L1 RT threads, PHY worker pool, MAC stats, PDCP/RLC data threads, GTP-U receive threads, SDAP TUN reader. Add `vnf_p7_thread` / `pnf_p7_thread` only when using split-PHY with nFAPI; add `udp read thread` / `udp write thread` only for eCPRI/Open-Fronthaul radio units.

```
aurora = {
  collection_interval_ms = 100;
  shm_key = "0xDEADBEEF";    # unique key per node
  ran_type = "RAN_GNB";
  thread_metrics_enabled   = "yes";
  thread_metrics_backend   = "auto";
  thread_metrics_whitelist = "L1_rx_thread, L1_tx_thread, L1_stats,
                               ru_thread, fep, feptx,
                               MAC_STATS,
                               pdcp_timer, RLC queue, PDCP data ind,
                               GTPrx_*, gnb_tun_read_thread,
                               Tpool*,
                               vnf_p7_thread, pnf_p7_thread,
                               udp read thread, udp write thread,
                               aurora_reset_thread, aurora_thr_proc, aurora_thr_ebpf";
};
```

| Thread | Category | Notes |
|--------|----------|-------|
| `L1_rx_thread` | PHY | L1 receive loop — highest RT priority |
| `L1_tx_thread` | PHY | L1 transmit loop — highest RT priority |
| `L1_stats` | PHY | L1 per-slot stats collector |
| `ru_thread` | RU | Radio Unit frontend main thread |
| `fep` | RU | Front-End Processing RX |
| `feptx` | RU | Front-End Processing TX |
| `MAC_STATS` | MAC | MAC scheduler stats thread |
| `pdcp_timer` | PDCP | PDCP retransmission timer |
| `RLC queue` | RLC | RLC AM/UM queue processing |
| `PDCP data ind` | PDCP | PDCP data indication dispatcher |
| `GTPrx_*` | GTP-U | Per-tunnel GTP-U receive threads (`GTPrx_0`, `GTPrx_1`, …) |
| `gnb_tun_read_thread` | SDAP | SDAP TUN interface read thread (gNB-side PDU session) |
| `Tpool*` | PHY pool | PHY worker thread-pool (`Tpool0_-1`, `Tpool1_2`, …) |
| `vnf_p7_thread` | nFAPI | NFAPI VNF P7 handler (split-PHY only) |
| `pnf_p7_thread` | nFAPI | NFAPI PNF P7 handler (split-PHY only) |
| `udp read thread` | eCPRI | UDP fronthaul RX (eCPRI/Open-Fronthaul only) |
| `udp write thread` | eCPRI | UDP fronthaul TX (eCPRI/Open-Fronthaul only) |

---

### RAN_DU — Distributed Unit (L1 + MAC + lower RLC/PDCP, no GTP/SDAP)

DU hosts all real-time PHY/MAC layers. GTP-U and SDAP TUN **not** present on DU — run on CU side. nFAPI and eCPRI fronthaul entries included if deployment uses them; harmless when absent (unmatched entries silently skipped).

```
aurora = {
  collection_interval_ms = 100;
  shm_key = "0xDEADBEEF";    # unique key per node, different from CU
  ran_type = "RAN_DU";
  thread_metrics_enabled   = "yes";
  thread_metrics_backend   = "auto";
  thread_metrics_whitelist = "L1_rx_thread, L1_tx_thread, L1_stats,
                               ru_thread, fep, feptx,
                               MAC_STATS,
                               pdcp_timer, RLC queue, PDCP data ind,
                               Tpool*,
                               vnf_p7_thread, pnf_p7_thread,
                               udp read thread, udp write thread,
                               aurora_reset_thread, aurora_thr_proc, aurora_thr_ebpf";
};
```

| Thread | Category | Notes |
|--------|----------|-------|
| `L1_rx_thread` | PHY | L1 receive loop |
| `L1_tx_thread` | PHY | L1 transmit loop |
| `L1_stats` | PHY | L1 statistics |
| `ru_thread` | RU | Radio Unit frontend |
| `fep` | RU | Front-End Processing RX |
| `feptx` | RU | Front-End Processing TX |
| `MAC_STATS` | MAC | MAC scheduler stats |
| `pdcp_timer` | PDCP | PDCP timer (for RLC-AM at DU) |
| `RLC queue` | RLC | RLC queue processing |
| `PDCP data ind` | PDCP | PDCP data indication |
| `Tpool*` | PHY pool | PHY worker thread-pool |
| `vnf_p7_thread` | nFAPI | NFAPI VNF P7 (split-PHY only) |
| `pnf_p7_thread` | nFAPI | NFAPI PNF P7 (split-PHY only) |
| `udp read thread` | eCPRI | UDP fronthaul RX (eCPRI only) |
| `udp write thread` | eCPRI | UDP fronthaul TX (eCPRI only) |

---

### RAN_CU — Combined CU (CU-CP + CU-UP in one process)

CU has no L1, no MAC, no PHY thread pool. Runs PDCP (both SRBs and DRBs), GTP-U tunnels, SDAP TUN interface.

```
aurora = {
  collection_interval_ms = 100;
  shm_key = "0xDEADBEEF";
  ran_type = "RAN_CU";
  thread_metrics_enabled   = "yes";
  thread_metrics_backend   = "auto";
  thread_metrics_whitelist = "pdcp_timer, RLC queue, PDCP data ind,
                               GTPrx_*, gnb_tun_read_thread,
                               aurora_reset_thread, aurora_thr_proc, aurora_thr_ebpf";
};
```

| Thread | Category | Notes |
|--------|----------|-------|
| `pdcp_timer` | PDCP | PDCP retransmission timer |
| `RLC queue` | RLC | RLC AM/UM queue (user-plane DRBs) |
| `PDCP data ind` | PDCP | PDCP data indication dispatcher |
| `GTPrx_*` | GTP-U | Per-tunnel GTP-U receive threads |
| `gnb_tun_read_thread` | SDAP | SDAP TUN interface read thread |

---

### RAN_CU_CP — CU Control Plane only

CU-CP carries only signalling (RRC, F1AP, NGAP, E1AP). Only PDCP traffic on SRBs. No GTP tunnels, no SDAP TUN interface.

```
aurora = {
  collection_interval_ms = 100;
  shm_key = "0xDEADBEEF";
  ran_type = "RAN_CU_CP";
  thread_metrics_enabled   = "yes";
  thread_metrics_backend   = "auto";
  thread_metrics_whitelist = "pdcp_timer, PDCP data ind,
                               aurora_reset_thread, aurora_thr_proc, aurora_thr_ebpf";
};
```

| Thread | Category | Notes |
|--------|----------|-------|
| `pdcp_timer` | PDCP | SRB PDCP retransmission timer |
| `PDCP data ind` | PDCP | SRB PDCP data indication (control-plane only) |

> **Note**: `RLC queue` absent on CU-CP — RLC queue processing belongs to user-plane path on CU-UP.

---

### RAN_CU_UP — CU User Plane only

CU-UP carries only user data (DRBs). Runs PDCP for DRBs, GTP-U tunnels to UPF, SDAP TUN interface. No MAC, no L1, no SRB handling.

```
aurora = {
  collection_interval_ms = 100;
  shm_key = "0xDEADBEEF";
  ran_type = "RAN_CU_UP";
  thread_metrics_enabled   = "yes";
  thread_metrics_backend   = "auto";
  thread_metrics_whitelist = "pdcp_timer, RLC queue, PDCP data ind,
                               GTPrx_*, gnb_tun_read_thread,
                               aurora_reset_thread, aurora_thr_proc, aurora_thr_ebpf";
};
```

| Thread | Category | Notes |
|--------|----------|-------|
| `pdcp_timer` | PDCP | DRB PDCP retransmission timer |
| `RLC queue` | RLC | RLC AM/UM queue for DRBs |
| `PDCP data ind` | PDCP | PDCP data indication for DRBs |
| `GTPrx_*` | GTP-U | Per-tunnel GTP-U receive threads (to/from UPF) |
| `gnb_tun_read_thread` | SDAP | SDAP TUN interface read thread |

---

## Histogram Mechanics

### Exponential Packet-Size Histogram (Traffic Flows)

Traffic flows record **per-packet sizes** into 16-bin exponential histogram.
Bin boundaries and mean estimation formula used in `aurora_reader`:

| Bin | Lower (bytes) | Upper (bytes) |
|-----|--------------|--------------|
| 0   | 0            | 63           |
| 1   | 64           | 127          |
| 2   | 128          | 255          |
| 3   | 256          | 511          |
| 4   | 512          | 1 023        |
| 5   | 1 024        | 2 047        |
| 6   | 2 048        | 4 095        |
| 7   | 4 096        | 8 191        |
| 8   | 8 192        | 16 383       |
| 9   | 16 384       | 32 767       |
| 10  | 32 768       | 65 535       |
| 11  | 65 536       | 131 071      |
| 12  | 131 072      | 262 143      |
| 13  | 262 144      | 524 287      |
| 14  | 524 288      | 1 048 575    |
| 15  | 1 048 576    | 2 097 151    |

**Mean estimation (uniform distribution within bin assumed):**

```
total = sum_i { (bin_count[i] / range_size[i]) * ((range_start[i] + range_end[i]) * range_size[i] / 2) }
mean  = total / sum_i { bin_count[i] }
```

Simplifies to: `mean = sum_i { bin_count[i] * (range_start[i] + range_end[i]) / 2 } / total_count`

### Exponential Runtime Histogram (Thread Metrics)

Thread runtime distribution uses **32-bin exponential histogram** where bin `i` covers scheduling quanta with runtime in `[2^i, 2^(i+1) - 1]` nanoseconds.

| Bin | Range (ns) | Typical interpretation |
|-----|-----------|------------------------|
| 0   | [1, 1]    | Sub-nanosecond (clock noise) |
| 10  | [1024, 2047] | ~1–2 µs |
| 13  | [8192, 16383] | ~8–16 µs |
| 17  | [131072, 262143] | ~130–260 µs |
| 20  | [1048576, 2097151] | ~1–2 ms |
| 23  | [8388608, 16777215] | ~8–16 ms |
| 30  | [1073741824, 2147483647] | ~1–2 s |
| 31  | [2147483648, 4294967295] | ~2–4 s |
| overflow | > 4294967295 | Thread blocked > 4 s |

**Procedure-1 — Total runtime and derived statistics from exponential histogram:**

```
For each bin i with count > 0:
    range_start = 2^i
    range_end   = 2^(i+1) - 1
    range_size  = range_end - range_start + 1
    items_per_bin = bin_count[i] / range_size        (uniform distribution assumption)
    bin_total   = items_per_bin * (range_start + range_end) * range_size / 2

total_runtime_ns = sum over all bins { bin_total }
mean_ns          = total_runtime_ns / total_events
range_ns         = max_runtime_ns - est_min_ns       (est_min = midpoint of first non-empty bin)
variance         = sum over bins { bin_count[i] * (bin_mid[i] - mean)^2 } / total_events
std_deviation    = sqrt(variance)
skewness         = (third central moment / total_events) / std_deviation^3
kurtosis         = (fourth central moment / total_events) / std_deviation^4 - 3  (excess kurtosis)
outliers_low     = count of events in bins where bin_mid < mean - 2*std_deviation
outliers_high    = count of events in bins where bin_mid > mean + 2*std_deviation
```

### Shift-Type Histogram (FAPI MCS / PRB)

FAPI MCS and PRB values recorded into **shift-type histograms** with fixed-width buckets.
Average estimated in `aurora_reader` using:

```
BUCKET = 2^shift
range_start[i] = max(BUCKET * i, min_val)
range_end[i]   = min(BUCKET * (i+1) - 1, max_val)
avg = sum_i { items_per_bin[i] * (range_start[i] + range_end[i]) * range_size[i] / 2 }
      / sum_i { bin_count[i] }
```

| Metric | shift | BUCKET | 16-bin range |
|--------|-------|--------|--------------|
| MCS    | 2     | 4      | [0,3] [4,7] … [60,63] |
| PRB    | 5     | 32     | [0,31] [32,63] … [480,511] |

### Statistical Variants (computed in `aurora_reader` from histogram data)

For each traffic flow, reader computes all statistical distribution variants:

| Variant | Formula |
|---------|---------|
| min | `hist.min_val` — exact, recorded on every sample |
| max | `hist.max_val` — exact, recorded on every sample |
| mean | Estimated from histogram using exponential-bin formula above |
| range | `max - min` (exact, not estimated) |
| IQR | `Q3 - Q1` — Q1 at 25th percentile, Q3 at 75th percentile, located via bin CDF |
| variance | `sum(bin_count * (bin_mid - mean)^2) / total_count` |
| std_dev | `sqrt(variance)` |
| skewness | `mean((x - mean)^3) / std_dev^3` — positive = right-skewed |
| kurtosis | `mean((x - mean)^4) / std_dev^4 - 3` — excess kurtosis relative to normal distribution |
| outliers | Count of samples in bins whose midpoint falls outside `[mean - 2*std_dev, mean + 2*std_dev]` |

---

## Metric Reference

### Group 1 — Traffic Flow Metrics

13 traffic flows monitored. Each flow has total byte counter + 16-bin packet-size histogram in shared memory. `aurora_reader` derives statistical distribution variants from histogram locally.

`_size` field holds **cumulative byte total** for current interval.
`hist_*` histogram drives all derived statistical metrics.

#### Traffic Flow Definitions

| Field | Direction | Interface | Description | RAN types |
|-------|-----------|-----------|-------------|-----------|
| `Bhtx_in` | DL | Backhaul L3 | PDCP SDU received from core, queued on ingress | GNB, CU, CU-UP |
| `Bhtx_out` | DL | Backhaul L3 | PDCP SDU dequeued for PDCP processing | GNB, CU, CU-UP |
| `Bhrx_in` | UL | Backhaul L3 | UL PDCP PDU queued for transmission to core | GNB, CU, CU-UP |
| `Bhrx_out` | UL | Backhaul L3 | UL PDCP PDU transmitted on network | GNB, CU, CU-UP |
| `Mhtx_in` | DL | Midhaul F1 | PDCP PDU queued for F1-U transmission to DU | GNB, CU, CU-UP |
| `Mhtx_out` | DL | Midhaul F1 | PDCP PDU transmitted on F1-U link | GNB, CU, CU-UP |
| `Mhrx_in` | UL | Midhaul F1 | UL PDU received from DU, queued at CU ingress | GNB, CU, CU-UP, DU |
| `Mhrx_out` | UL | Midhaul F1 | UL PDU dequeued for PDCP processing at CU | GNB, CU, CU-UP, DU |
| `F1u_rlc` | DL | F1-U → RLC | F1-U PDU delivered to RLC layer at DU | GNB, DU |
| `Rlc_f1` | UL | RLC → F1-U | RLC PDU submitted to F1-U for upstream delivery | GNB, DU |
| `Rlc_mac` | DL | RLC → MAC | RLC PDU submitted to MAC scheduler for DL transmission | GNB, DU |
| `Mac_rlc` | UL | MAC → RLC | MAC PDU delivered to RLC after UL reception | GNB, DU |
| `Mac_dl_bo` | DL | MAC internal | MAC DL buffer occupancy sample (point-in-time, not cumulative) | GNB, DU |

#### Per-Flow Statistical Metrics

Each of 13 flows produces these metrics (substitute `{flow}` with flow name):

| Metric | Collected/Derived | Notes |
|--------|------------------|-------|
| `{flow}_size` | Collected | Cumulative bytes over collection interval; aggregated across all UEs. |
| `{flow}_min` | Collected | Exact minimum packet/sample size this interval. |
| `{flow}_max` | Collected | Exact maximum packet/sample size this interval. |
| `{flow}_mean` | Derived | Estimated from histogram assuming uniform distribution within each bin. |
| `{flow}_range` | Derived | `max - min` (uses exact recorded min/max, not bin estimates). |
| `{flow}_IQR` | Derived | 75th percentile minus 25th percentile, via cumulative bin distribution. |
| `{flow}_variance` | Derived | Second central moment via bin midpoints. |
| `{flow}_std_dev` | Derived | `sqrt(variance)`. |
| `{flow}_skewness` | Derived | `mean((x-mean)^3) / std_dev^3`. Positive = many small packets, rare large ones. |
| `{flow}_kurtosis` | Derived | `mean((x-mean)^4) / std_dev^4 - 3`. Excess kurtosis relative to normal distribution. |
| `{flow}_outliers` | Derived | Count of samples in bins whose midpoint falls outside `[mean - 2*std_dev, mean + 2*std_dev]`. |

> **Note on `Mac_rlc`**: Histogram `hist_mac_rlc` = primary non-derived metric for MAC→RLC uplink path. `aurora_reader` displays raw bin counts alongside computed statistical variants.

#### Collection Points

| Traffic flow | Source file | Hook |
|-------------|-------------|------|
| Bhtx_in / Bhtx_out | `nr_pdcp/nr_pdcp_oai_api.c` | PDCP TX SDU path |
| Bhrx_in / Bhrx_out | `nr_pdcp/nr_pdcp_oai_api.c` | PDCP RX SDU path |
| Mhtx_in / Mhtx_out | `nr_pdcp/nr_pdcp_oai_api.c` | PDCP→F1 PDU path |
| Mhrx_in / Mhrx_out | `nr_pdcp/nr_pdcp_oai_api.c` | F1→PDCP PDU path |
| F1u_rlc / Rlc_f1 | `nr_rlc/nr_rlc_oai_api.c` | F1-U ↔ RLC interface |
| Rlc_mac / Mac_rlc | `NR_MAC_gNB/main.c` | Per-UE scheduling loop |
| Mac_dl_bo | `NR_MAC_gNB/main.c` | Per-UE scheduling loop |

---

### Group 2 — HARQ Metrics (DL)

Collected on DU side; aggregated across all UEs over collection interval.

| Metric | Collected/Derived | Description |
|--------|------------------|-------------|
| `dl_harq_ack` | Collected | Total HARQ ACKs received |
| `dl_harq_nack` | Collected | Total HARQ NACKs + DTX received |
| `dl_harq_total` | Collected | Total HARQ feedback reports (ACK + NACK) |
| `dl_harq_loss_rate` | Derived | `dl_harq_nack / dl_harq_total` |
| `dl_harq_max_cons` | Collected | Max consecutive NACKs for any single HARQ process |

**Collection point**: `NR_MAC_gNB/gNB_scheduler_uci.c` — UCI decoding callback.

---

### Group 3 — CRC Metrics (UL)

Collected on DU side; aggregated across all UEs.

| Metric | Collected/Derived | Description |
|--------|------------------|-------------|
| `ul_crc_loss` | Collected | Total UL PUSCH CRC failures |
| `ul_crc_total` | Collected | Total UL PUSCH CRC reports |
| `ul_crc_loss_rate` | Derived | `ul_crc_loss / ul_crc_total` |

**Collection point**: `NR_MAC_gNB/gNB_scheduler_ulsch.c` — PUSCH CRC decoding.

---

### Group 4 — SINR / CSI / BSR Aggregate Metrics

Cross-UE aggregates computed every scheduling round by scanning all active per-UE MAC stats.
Represent min, max, mean across all active RNTIs.

| Metric | Collected/Derived | Description | Source field |
|--------|------------------|-------------|--------------|
| `sinr_min` | Derived | Min PUSCH SINR across all active UEs (dB) | `mac_ue_stats[].pusch_snr` |
| `sinr_max` | Derived | Max PUSCH SINR across all active UEs (dB) | `mac_ue_stats[].pusch_snr` |
| `sinr_avg` | Derived | Mean PUSCH SINR across all active UEs (dB) | `mac_ue_stats[].pusch_snr` |
| `csi_min` | Derived | Min wideband CQI across all active UEs | `mac_ue_stats[].wb_cqi` |
| `csi_max` | Derived | Max wideband CQI across all active UEs | `mac_ue_stats[].wb_cqi` |
| `csi_avg` | Derived | Mean wideband CQI across all active UEs | `mac_ue_stats[].wb_cqi` |
| `bsr_min` | Derived | Min BSR across all active UEs (bytes) | `mac_ue_stats[].bsr` |
| `bsr_max` | Derived | Max BSR across all active UEs (bytes) | `mac_ue_stats[].bsr` |
| `bsr_avg` | Derived | Mean BSR across all active UEs (bytes) | `mac_ue_stats[].bsr` |

**Collection point**: `aurora_recompute_ue_aggregates()`, called from `NR_MAC_gNB/main.c` after each UE scheduling iteration.

---

### Group 5 — FAPI DL Metrics (Aggregate)

Aggregate stats for all PDSCH PDUs scheduled within collection interval.

| Metric | Collected/Derived | Description |
|--------|------------------|-------------|
| `fapi_dl_total_pdsch_count` | Collected | Total PDSCH PDU count for interval |
| `fapi_dl_avg_pdsch` | Derived | Mean PDSCH TBS: `total_bytes / count` |
| `dl_fapi_mcs_max` | Collected | Max MCS index scheduled |
| `dl_fapi_mcs_min` | Collected | Min MCS index scheduled |
| `dl_fapi_mcs_avg` | Derived | Running-sum avg MCS; cross-checked via shift-type histogram |
| `dl_fapi_prb_max` | Collected | Max RB allocation scheduled |
| `dl_fapi_prb_min` | Collected | Min RB allocation scheduled |
| `dl_fapi_prb_avg` | Derived | Running-sum avg PRB; cross-checked via shift-type histogram |
| `dl_fapi_tbs_max` | Collected | Max TBS scheduled (bytes) |
| `dl_fapi_tbs_min` | Collected | Min TBS scheduled (bytes) |
| `dl_fapi_tbs_avg` | Derived | Mean TBS, synced with `fapi_dl_avg_pdsch` |
| `hist_dl_fapi_mcs` | Collected | Shift-type histogram for DL MCS distribution (shift=2, BUCKET=4) |
| `hist_dl_fapi_prb` | Collected | Shift-type histogram for DL PRB distribution (shift=5, BUCKET=32) |

`aurora_reader` computes histogram-based avg independently using shift-type formula, displays alongside scalar `dl_fapi_mcs_avg` / `dl_fapi_prb_avg` for cross-validation.

**Collection point**: `NR_MAC_gNB/gNB_scheduler_dlsch.c`, `prepare_pdsch_pdu()` — once per PDSCH PDU.

---

### Group 6 — FAPI UL Metrics (Aggregate)

Aggregate stats for all PUSCH PDUs scheduled within collection interval.

| Metric | Collected/Derived | Description |
|--------|------------------|-------------|
| `fapi_ul_total_pusch_count` | Collected | Total PUSCH PDU count for interval |
| `fapi_ul_avg_pusch` | Derived | Mean PUSCH TBS: `total_bytes / count` |
| `ul_fapi_mcs_max` | Collected | Max MCS index scheduled |
| `ul_fapi_mcs_min` | Collected | Min MCS index scheduled |
| `ul_fapi_mcs_avg` | Derived | Running-sum avg MCS; cross-checked via shift-type histogram |
| `ul_fapi_prb_max` | Collected | Max RB allocation scheduled |
| `ul_fapi_prb_min` | Collected | Min RB allocation scheduled |
| `ul_fapi_prb_avg` | Derived | Running-sum avg PRB; cross-checked via shift-type histogram |
| `ul_fapi_tbs_max` | Collected | Max TBS scheduled (bytes) |
| `ul_fapi_tbs_min` | Collected | Min TBS scheduled (bytes) |
| `ul_fapi_tbs_avg` | Derived | Mean TBS, synced with `fapi_ul_avg_pusch` |
| `hist_ul_fapi_mcs` | Collected | Shift-type histogram for UL MCS distribution (shift=2, BUCKET=4) |
| `hist_ul_fapi_prb` | Collected | Shift-type histogram for UL PRB distribution (shift=5, BUCKET=32) |

**Collection point**: `NR_MAC_gNB/gNB_scheduler_ulsch.c`, `prepare_pusch_pdu()` — once per PUSCH PDU.

---

### Group 7 — Per-UE FAPI Metrics

Per-RNTI snapshot of most recently scheduled DL and UL PDU parameters.
Indexed by `rnti % MAX_NO_UEs`; zero RNTI = empty slot.

| Field | Description |
|-------|-------------|
| `rnti` | UE Radio Network Temporary Identifier |
| `dl_mcs` | MCS index of last scheduled PDSCH PDU for this UE |
| `dl_prb` | RB count of last scheduled PDSCH PDU |
| `dl_tbs` | TBS (bytes) of last scheduled PDSCH PDU |
| `ul_mcs` | MCS index of last scheduled PUSCH PDU for this UE |
| `ul_prb` | RB count of last scheduled PUSCH PDU |
| `ul_tbs` | TBS (bytes) of last scheduled PUSCH PDU |

**Collection point**: `gNB_scheduler_dlsch.c` → `aurora_update_fapi_dl_ue_metrics(rnti, ...)` and
`gNB_scheduler_ulsch.c` → `aurora_update_fapi_ul_ue_metrics(rnti, ...)`.

---

### Group 8 — KPM Cell-Level Metrics

Standard O-RAN KPM cell-level indicators.
Auto-recomputed in `aurora_recompute_ue_aggregates()` each scheduling round.
Stored in `kpm_metrics[AURORA_MAX_KPM_METRICS]` (max 16 entries).

| ID | Name | Type | Description | Derived from |
|----|------|------|-------------|--------------|
| 1 | `RRC.ConnNumber` | integer | Active UE count | Count of `mac_ue_stats[].rnti != 0` |
| 2 | `DRB.UEThpDl` | real | Mean DL current TBS per active UE (bytes/interval) | `mac_ue_stats[].dl_curr_tbs` |
| 3 | `DRB.UEThpUl` | real | Mean UL current TBS per active UE (bytes/interval) | `mac_ue_stats[].ul_curr_tbs` |
| 4 | `CARR.PDSCHMCSSched` | real | Avg DL MCS scheduled this interval | `dl_fapi_mcs_avg` |
| 5 | `CARR.PUSCHMCSSched` | real | Avg UL MCS scheduled this interval | `ul_fapi_mcs_avg` |
| 6 | `CARR.PRBUsageDl` | integer | Total DL RBs allocated across all active UEs | Sum of `mac_ue_stats[].dl_aggr_prb` |
| 7 | `CARR.PRBUsageUl` | integer | Total UL RBs allocated across all active UEs | Sum of `mac_ue_stats[].ul_aggr_prb` |
| 8 | `CARR.AverageCQI` | real | Mean wideband CQI across all active UEs | `mac_ue_stats[].wb_cqi` |
| 9 | `DRB.PdcpSduBitrateDl` | integer | Total PDCP DL SDU bytes this interval | Sum of `pdcp_rb_stats[].txsdu_bytes` |
| 10 | `DRB.PdcpSduBitrateUl` | integer | Total PDCP UL SDU bytes this interval | Sum of `pdcp_rb_stats[].rxsdu_bytes` |
| 11 | `L1M.UL-sinrAvg` | real | Mean PUSCH SINR across all active UEs (dB) | `sinr_avg` |
| 12 | `L1M.DL-rsrpAvg` | real | Mean DL RSRP across all active UEs (dBm) | `mac_ue_stats[].rsrp_avg` |

---

### Group 9 — Network Slice Metrics

Per-slice performance metrics; up to 8 slices (`AURORA_MAX_SLICES`).
Updated by `aurora_update_slice_stats()` from slice scheduler or E2 RC handler.

| Field | Type | Description |
|-------|------|-------------|
| `slice_id` | uint32 | Slice identifier |
| `allocated_prbs` | uint32 | PRBs allocated to this slice |
| `throughput_dl` | uint64 | DL throughput (bps) |
| `throughput_ul` | uint64 | UL throughput (bps) |
| `latency_us` | uint32 | Avg end-to-end latency (µs) |
| `packet_loss_rate` | double | Packet loss ratio (0.0 – 1.0) |
| `ue_count` | uint32 | UEs assigned to this slice |
| `qos_satisfaction` | uint32 | QoS satisfaction percentage (0 – 100) |

**Update API**: `aurora_update_slice_stats(slice_id, allocated_prbs, throughput_dl, throughput_ul, latency_us, packet_loss_rate, ue_count, qos_satisfaction)`

---

### Group 10 — Traffic Control Queue Metrics

Per-queue traffic management metrics; up to 16 queues (`AURORA_MAX_TC_QUEUES`).
Updated by `aurora_update_tc_stats()` from RLC or PDCP queue management code.

| Field | Type | Description |
|-------|------|-------------|
| `queue_id` | uint32 | Queue identifier |
| `queue_length` | uint32 | Current packets in queue |
| `max_queue_length` | uint32 | Max observed queue depth (high-water mark, preserved across resets) |
| `packets_dropped` | uint64 | **Delta**: packets dropped from queue overflow this interval (converted from cumulative via static prev snapshot) |
| `packets_scheduled` | uint64 | **Delta**: packets dequeued+scheduled this interval (converted from cumulative via static prev snapshot) |
| `drop_rate` | double | Drop rate in packets/sec |
| `avg_delay_us` | uint32 | Avg queuing delay (µs) |
| `qci` | uint32 | QoS Class Identifier for this queue |

**Update API**: `aurora_update_tc_stats(queue_id, queue_length, max_queue_length, packets_dropped, packets_scheduled, drop_rate, avg_delay_us, qci)`

---

### Group 11 — Radio Control Cell Metrics

Per-cell radio resource management indicators; up to 4 cells (`AURORA_MAX_RC_CELLS`).
Cell 0 auto-populated by `aurora_recompute_ue_aggregates()` each scheduling round.
Handover counters updated by `aurora_update_rc_handover()` from RRC handover procedures.

| Field | Collected/Derived | Description |
|-------|------------------|-------------|
| `cell_id` | Collected | Cell identifier (0 = primary serving cell for single-cell deployments) |
| `rsrp_avg` | Derived | Mean DL RSRP across all active UEs (dBm). From `mac_ue_stats[].rsrp_avg` derived from `NR_mac_stats.cumul_rsrp / num_rsrp_meas`. |
| `rsrq_avg` | Reserved | Not tracked in OAI MAC layer; always 0. |
| `sinr_avg` | Derived | Mean PUSCH SINR across all active UEs (dB). Same as `sinr_avg` aggregate. |
| `cell_load_percent` | Derived | `sum(dl_aggr_prb) * 100 / 106`, capped at 100%. Assumes 20 MHz bandwidth (106 PRBs max). |
| `interference_level` | Derived | 0=low (SINR >= 20 dB), 1=medium (5–20 dB), 2=high (< 5 dB). |
| `handover_attempts` | Collected | **Delta**: HO attempts this interval; incremented by `aurora_update_rc_handover()`, reset to zero each interval. |
| `handover_success` | Collected | **Delta**: successful HOs this interval; incremented by `aurora_update_rc_handover()`, reset to zero each interval. |
| `handover_success_rate` | Derived | `handover_success / handover_attempts`. |

**Update API for handovers**: `aurora_update_rc_handover(cell_id, success)` — call from RRC HO success/failure path.

---

### Group 12 — Per-UE MAC Statistics

Indexed by `rnti % MAX_NO_UEs`. Updated each scheduling TTI by `aurora_update_mac_ue_all_stats()`.

| Field | Type | Description |
|-------|------|-------------|
| `rnti` | uint32 | UE identifier (0 = slot unused) |
| `dl_aggr_tbs` | uint64 | Aggregated DL total bytes scheduled (all HARQ rounds) |
| `ul_aggr_tbs` | uint64 | Aggregated UL total bytes scheduled |
| `dl_aggr_bytes_sdus` | uint64 | Aggregated DL total SDU bytes |
| `ul_aggr_bytes_sdus` | uint64 | Aggregated UL total SDU bytes |
| `dl_curr_tbs` | uint64 | DL bytes scheduled in current collection interval |
| `ul_curr_tbs` | uint64 | UL bytes scheduled in current collection interval |
| `dl_sched_rb` | uint64 | DL RBs scheduled (cumulative) |
| `ul_sched_rb` | uint64 | UL RBs scheduled (cumulative) |
| `dl_aggr_prb` | uint32 | Total DL PRBs allocated |
| `ul_aggr_prb` | uint32 | Total UL PRBs allocated |
| `dl_aggr_sdus` | uint32 | Total DL MAC SDU count |
| `ul_aggr_sdus` | uint32 | Total UL MAC SDU count |
| `dl_aggr_retx_prb` | uint32 | DL retransmission PRB count |
| `ul_aggr_retx_prb` | uint32 | UL retransmission PRB count |
| `dl_harq[5]` | uint32[] | Per-round DL HARQ counts (rounds 0–4) |
| `ul_harq[5]` | uint32[] | Per-round UL HARQ counts (rounds 0–4) |
| `dl_num_harq` | uint32 | DL HARQ rounds configured |
| `ul_num_harq` | uint32 | UL HARQ rounds configured |
| `pusch_snr` | float | PUSCH SINR (dB), from `sched_ctrl->pusch_snrx10 / 10` |
| `pucch_snr` | float | PUCCH SNR (dB), from `sched_ctrl->pucch_snrx10 / 10` |
| `dl_bler` | float | DL Block Error Rate |
| `ul_bler` | float | UL Block Error Rate |
| `wb_cqi` | uint8 | Wideband CQI index from latest CSI report |
| `dl_mcs1` | uint8 | DL MCS index from BLER stats |
| `ul_mcs1` | uint8 | UL MCS index from BLER stats |
| `dl_mcs2` | uint8 | DL MCS table index from BWP config |
| `ul_mcs2` | uint8 | UL MCS table index from BWP config |
| `phr` | int8 | Power Headroom Report (dB) |
| `rsrp_avg` | float | Avg DL RSRP (dBm), from `cumul_rsrp / num_rsrp_meas` |
| `bsr` | uint32 | Buffer Status Report — estimated UL buffer occupancy (bytes) |
| `frame` | uint16 | Frame number at last update |
| `slot` | uint16 | Slot number at last update |

**Collection point**: `NR_MAC_gNB/main.c` — `aurora_update_mac_ue_all_stats()` called per UE per scheduling TTI.

---

### Group 13 — Per-UE RLC Radio Bearer Statistics

Indexed by `rlc_rb_stats[ue_index][rb_index]` where `ue_index = rnti % MAX_NO_UEs`.
Updated by `aurora_update_rlc_ue_all_rb_stats()` per UE per TTI.

| Field | Type | Description |
|-------|------|-------------|
| `rnti` | uint32 | UE identifier |
| `rbid` | uint8 | Radio Bearer ID (0–3 = SRBs, 4–35 = DRBs) |
| `mode` | uint32 | RLC mode: 0=TM, 1=UM, 2=AM |
| `txpdu_pkts` | uint64 | **Delta**: TX PDU packets this interval (from cumulative OAI RLC counter via static prev snapshot in `aurora_rlc.c`) |
| `txpdu_bytes` | uint64 | **Delta**: TX PDU bytes this interval |
| `txsdu_pkts` | uint64 | **Delta**: TX SDU packets this interval |
| `txsdu_bytes` | uint64 | **Delta**: TX SDU bytes this interval |
| `rxpdu_pkts` | uint64 | **Delta**: RX PDU packets this interval |
| `rxpdu_bytes` | uint64 | **Delta**Compressing inline text using caveman rules. Large doc — working through each section.





## Anomaly Injection Plan

Anomaly injection for RAN metrics collection is organized by fault domain:

- Hardware level
- Infrastructure level (container / pod level)
- Application level (RAN application such as gNB, CU, DU)

### Hardware level

- Port flapping: intermittent up/down behavior on physical network interfaces. Simulated by toggling the testbed interface with `ip link set dev <iface> down` / `ip link set dev <iface> up`, or by using a programmable network switch to flap the port.
- Link failure: complete loss of physical connectivity between pods or nodes. Simulated with `tc qdisc add dev <iface> root netem loss 100%` or by disabling the interface on the testbed node.

### Infrastructure level

- CPU contention by noisy neighbours: competing pods or co-located workloads consuming CPU resources on the same node. Simulated by deploying a noisy pod/container with `stress-ng --cpu N --timeout T` or by running CPU-bound loops on the host.
- Memory contention by noisy neighbours: competing pods or co-located workloads using available memory and causing swapping or OOM pressure. Simulated by deploying a memory-hungry process with `stress-ng --vm N --vm-bytes X --timeout T` or by allocating memory in a helper container.
- Network contention by noisy neighbours: competing workloads saturating shared packet or routing resources in the node or pod network namespace. Simulated with traffic generators such as `iperf3`, `tc qdisc` burst injection, or background UDP/TCP flood traffic on the shared interface.

### Application level (RAN)

- L1 RX/TX thread contention by misconfiguration: misconfigured thread affinities, priority inversion, or undersized RT thread pools leading to L1 receive/transmit scheduling contention. Simulated by changing RAN thread affinity/priority settings in config or by reducing RT scheduling resources for `L1_rx_thread`/`L1_tx_thread`.
- MAC contention by misconfiguration: scheduler or MAC thread misconfiguration causing excessive MAC lock contention, backlog, or delayed buffer processing. Simulated by oversubscribing MAC worker threads, applying artificial MAC-side load during scheduling, or creating contention on the CPU cores allocated to MAC processing.
- PDCP contention by misconfiguration: badly tuned PDCP thread/queue settings, leading to PDCP processing stalls, packet buffering, or scheduling pressure. Simulated by adjusting PDCP queue sizes, thread counts, or by injecting extra PDCP payload processing load.
- Queue-size tuning anomalies: abnormal queue depths or poorly sized buffers at RLC, PDCP, or MAC layers causing underflow/overflow, excessive delay, or head-of-line blocking. Simulated by modifying per-layer queue size limits and buffer thresholds in OAI configuration or by forcing extreme queue sizing across RLC/PDCP/MAC.
- Memory leaks in RAN application: manually injected via additional code paths that allocate without freeing buffers/structures in gNB, CU, or DU, causing growing memory pressure over time. Simulated by adding a controlled leak path in the code and running the RAN process until resident memory growth is observable.

More application-level anomalies are being explored in parallel, with new fault cases added as RAN behavior and metric sensitivity are validated.

## Data collection plan of action

The RAN data collection effort follows a phased plan with approximate timelines to keep experiments repeatable and results comparable.

1. Setup and baseline validation (1–2 days)
   - Configure `aurora` on the target RAN node(s) and verify the `shm_key`, `ran_type`, and `thread_metrics_*` settings.
   - Confirm the shared memory region is populated and `aurora_reader` can consume metrics for the selected RAN mode.
   - Ensure collection interval is set to 100 ms and capture a stable baseline run with normal traffic and no injection.

2. Anomaly injection experiments (3–5 days)
   - Run hardware-level anomalies: port flaps and link failures.
   - Run infrastructure-level anomalies: CPU, memory, and network noisy-neighbor stress tests.
   - Run application-level anomalies: L1 contention, MAC contention, PDCP contention, and controlled memory leaks.
   - Execute one anomaly at a time and collect repeated runs for each case.

3. Analysis and metric sensitivity validation (2–3 days)
   - Compare anomaly runs against baseline to identify sensitive metrics and signatures.
   - Validate which traffic-flow, HARQ/CRC, FAPI, MAC, and thread metrics change most reliably.
   - Refine anomaly strength and repeat runs if the signal is too weak or too destructive.

4. Documentation and extension (1–2 days)
   - Record precise injection commands, RAN config, testbed setup, and observed metric changes.
   - Add new application-level anomalies to the plan as they are validated.
   - Update the README or experiment notes with any additional fault cases and timing guidance.

Total estimated effort: approximately 2 weeks


## Distributed Approach Action Plan

This project will pursue a distributed anomaly detection and resolution architecture that keeps lightweight detection on CU/DU edge nodes while centralizing heavier analysis and explanation.

### Engineering Workstreams

- Model Selection for CU and DU anomaly detection
  - Evaluate separate edge models for CU and DU to reflect their distinct telemetry profiles and RAN responsibilities.
- Code for Online Learning on side-car container
  - Build a sidecar inference pipeline that can run locally on CU/DU, ingest live AURORA telemetry, and update models online.
- Synchronization of D-apps to report the data when anomaly detected
  - Define a shared alert schema and synchronization markers so distributed edge apps can report aligned context when anomalies occur.
- Anomaly Reporting framework to a central location
  - Implement a central reporting service that receives edge alerts, stores synchronized event windows, and provides cross-node context for RCA.
- RCA integration for synchronized and collected window
  - Ensure the central RCA pipeline consumes synchronized edge and collected data windows so causal reasoning uses aligned, comparable evidence.

### Research Workstreams

- Empirical proving that traffic patterns are different in Rural Vs Urban as motivation for distributed approach using ns-3 simulations
  - Prove that rural and urban traffic patterns differ because of population density, urbanization (building distribution), mobility (roads), and related factors.
  - Use population density datasets to simulate urban and rural UE distributions.
  - Incorporate OpenStreetMap (OSM) building data into ns-3 via new building modules.
  - Use OSM and SUMO to simulate UE mobility on realistic road networks.
- Designing Anomaly detection model
  - Research and choose models suitable for CU and DU telemetry, including edge-friendly sequence and distribution detectors.
- Designing a RCA method or decide to use one of the existing RCA methods
  - Evaluate existing root cause analysis frameworks and select or adapt one that fits the distributed synchronized window model.
- Explanation module using LLM (plain or RAG)
  - Prototype explanation generation that uses LLMs, optionally with retrieval-augmented generation, to turn RCA outputs into operator-ready narratives.
- Multi-agent framework for fault resolution before it cascades into a failure
  - Define planner, reasoning, validator, and executioner agents that collaborate with operators to contain faults safely.

### Goals

- Validate distributed edge detection with strong rural vs urban motivation.
- Keep edge anomaly detection lightweight while enabling central causal reasoning and explanation.
- Provide a clear workflow from CU/DU detection through centralized RCA, explanation, and operator-guided resolution.
