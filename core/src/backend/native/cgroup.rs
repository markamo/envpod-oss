// Copyright 2026 Xtellix Inc.
// SPDX-License-Identifier: Apache-2.0

//! cgroup v2 management for pod resource limits and process control.
//!
//! Each pod gets its own cgroup under `/sys/fs/cgroup/envpod/<pod-id>/`.
//! Controllers: cpu, memory, pids, io.
//!
//! Requires cgroup v2 (unified hierarchy) and root privileges.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use crate::types::{ResourceLimits, ResourceUsage};

pub const CGROUP_BASE: &str = "/sys/fs/cgroup";
pub const ENVPOD_SLICE: &str = "envpod";

/// Check if a cgroup exists (has a cgroup.procs file).
pub fn cgroup_exists(cgroup: &Path) -> bool {
    cgroup.join("cgroup.procs").exists()
}

/// Check if a cgroup has any live processes.
pub fn has_processes(cgroup: &Path) -> bool {
    fs::read_to_string(procs_path(cgroup))
        .map(|s| s.trim().lines().any(|l| l.trim().parse::<i32>().is_ok_and(|p| p > 0)))
        .unwrap_or(false)
}

/// Get the cgroup path for a pod: /sys/fs/cgroup/envpod/<pod_id>
#[allow(dead_code)]
pub fn cgroup_path(pod_id: &str) -> PathBuf {
    PathBuf::from(CGROUP_BASE)
        .join(ENVPOD_SLICE)
        .join(pod_id)
}

/// Create a cgroup v2 hierarchy for a pod.
///
/// Enables cpu, memory, pids controllers on the parent slice.
/// Returns the full cgroup path.
pub fn create(pod_id: &str) -> Result<PathBuf> {
    let parent = PathBuf::from(CGROUP_BASE).join(ENVPOD_SLICE);
    fs::create_dir_all(&parent).context("create envpod cgroup slice")?;

    // Enable controllers on the root cgroup (best-effort, may already be enabled)
    let root_subtree = PathBuf::from(CGROUP_BASE).join("cgroup.subtree_control");
    for controller in ["+cpu", "+memory", "+pids", "+io", "+cpuset"] {
        fs::write(&root_subtree, controller).ok();
    }

    // Enable controllers on the envpod slice
    let parent_subtree = parent.join("cgroup.subtree_control");
    for controller in ["+cpu", "+memory", "+pids", "+io", "+cpuset"] {
        fs::write(&parent_subtree, controller).ok();
    }

    let pod_cgroup = parent.join(pod_id);
    fs::create_dir_all(&pod_cgroup)
        .with_context(|| format!("create pod cgroup: {}", pod_cgroup.display()))?;

    Ok(pod_cgroup)
}

/// Path to cgroup.procs file (used to add processes to the cgroup).
pub fn procs_path(cgroup: &Path) -> PathBuf {
    cgroup.join("cgroup.procs")
}

/// Add a process to the pod's cgroup.
#[allow(dead_code)]
pub fn add_process(cgroup: &Path, pid: u32) -> Result<()> {
    fs::write(procs_path(cgroup), pid.to_string())
        .with_context(|| format!("add PID {pid} to cgroup"))
}

/// Apply resource limits to the cgroup.
pub fn set_limits(cgroup: &Path, limits: &ResourceLimits) -> Result<()> {
    // CPU: cpu.max = "$QUOTA $PERIOD"
    // e.g., 2 cores → "200000 100000" (200ms quota per 100ms period)
    if let Some(cores) = limits.cpu_cores {
        let period: u64 = 100_000; // 100ms in microseconds
        let quota = (cores * period as f64) as u64;
        fs::write(cgroup.join("cpu.max"), format!("{quota} {period}"))
            .context("set cpu.max")?;
    }

    // Memory: memory.max = bytes
    if let Some(bytes) = limits.memory_bytes {
        fs::write(cgroup.join("memory.max"), bytes.to_string())
            .context("set memory.max")?;
    }

    // PIDs: pids.max = count
    if let Some(max_pids) = limits.max_pids {
        fs::write(cgroup.join("pids.max"), max_pids.to_string())
            .context("set pids.max")?;
    }

    // cpuset: pin to specific CPU cores
    if let Some(ref cpus) = limits.cpuset_cpus {
        fs::write(cgroup.join("cpuset.cpus"), cpus)
            .context("set cpuset.cpus")?;
        // cpuset.mems is required when cpuset.cpus is set — default to NUMA node 0
        fs::write(cgroup.join("cpuset.mems"), "0")
            .context("set cpuset.mems")?;
    }

    Ok(())
}

/// Freeze all processes in the cgroup (cgroup v2 freezer).
pub fn freeze(cgroup: &Path) -> Result<()> {
    fs::write(cgroup.join("cgroup.freeze"), "1").context("freeze cgroup")
}

/// Resume (thaw) frozen processes.
pub fn thaw(cgroup: &Path) -> Result<()> {
    fs::write(cgroup.join("cgroup.freeze"), "0").context("thaw cgroup")
}

/// Send a signal to all processes in the cgroup.
pub fn kill_all(cgroup: &Path, signal: nix::sys::signal::Signal) -> Result<()> {
    let contents = fs::read_to_string(procs_path(cgroup)).unwrap_or_default();

    for line in contents.lines() {
        if let Ok(pid) = line.trim().parse::<i32>() {
            if pid > 0 {
                let pid = nix::unistd::Pid::from_raw(pid);
                nix::sys::signal::kill(pid, signal).ok(); // best effort
            }
        }
    }

    Ok(())
}

/// Read current resource usage from cgroup controllers.
pub fn read_usage(cgroup: &Path) -> Result<ResourceUsage> {
    let mut usage = ResourceUsage::default();

    // memory.current → bytes
    if let Ok(val) = fs::read_to_string(cgroup.join("memory.current")) {
        usage.memory_bytes = val.trim().parse().unwrap_or(0);
    }

    // pids.current → count
    if let Ok(val) = fs::read_to_string(cgroup.join("pids.current")) {
        usage.pid_count = val.trim().parse().unwrap_or(0);
    }

    // CPU percentage requires two-sample delta of cpu.stat usage_usec.
    // Single-point read returns 0 — callers needing CPU% should sample over time.

    Ok(usage)
}

/// Destroy the cgroup. All processes must already be dead.
pub fn destroy(cgroup: &Path) -> Result<()> {
    if cgroup.exists() {
        // cgroup directories can only be removed with rmdir (no contents),
        // kernel removes the control files automatically.
        fs::remove_dir(cgroup)
            .with_context(|| format!("remove cgroup: {}", cgroup.display()))?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cgroup_exists_returns_false_for_nonexistent() {
        assert!(!cgroup_exists(Path::new(
            "/sys/fs/cgroup/envpod/nonexistent-test-99999"
        )));
    }

    #[test]
    fn cgroup_path_construction() {
        let path = cgroup_path("abc-123");
        assert_eq!(
            path,
            PathBuf::from("/sys/fs/cgroup/envpod/abc-123")
        );
    }

    #[test]
    fn procs_path_construction() {
        let cg = PathBuf::from("/sys/fs/cgroup/envpod/test");
        assert_eq!(
            procs_path(&cg),
            PathBuf::from("/sys/fs/cgroup/envpod/test/cgroup.procs")
        );
    }

    // Note: tests that actually write to /sys/fs/cgroup require root
    // and are run separately with `sudo cargo test -- --ignored`

    #[test]
    #[ignore = "requires root and cgroup v2"]
    fn create_and_destroy_cgroup() {
        let pod_id = format!("test-{}", uuid::Uuid::new_v4());
        let path = create(&pod_id).unwrap();
        assert!(path.exists());

        destroy(&path).unwrap();
        assert!(!path.exists());
    }

    #[test]
    #[ignore = "requires root and cgroup v2"]
    fn set_and_read_limits() {
        let pod_id = format!("test-{}", uuid::Uuid::new_v4());
        let path = create(&pod_id).unwrap();

        let limits = ResourceLimits {
            cpu_cores: Some(1.5),
            memory_bytes: Some(512 * 1024 * 1024), // 512 MB
            max_pids: Some(100),
            ..Default::default()
        };
        set_limits(&path, &limits).unwrap();

        // Verify cpu.max
        let cpu_max = fs::read_to_string(path.join("cpu.max")).unwrap();
        assert_eq!(cpu_max.trim(), "150000 100000");

        // Verify memory.max
        let mem_max = fs::read_to_string(path.join("memory.max")).unwrap();
        assert_eq!(mem_max.trim(), "536870912");

        // Verify pids.max
        let pids_max = fs::read_to_string(path.join("pids.max")).unwrap();
        assert_eq!(pids_max.trim(), "100");

        destroy(&path).unwrap();
    }
}
