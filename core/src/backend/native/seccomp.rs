// Copyright 2026 Xtellix Inc.
// SPDX-License-Identifier: Apache-2.0

//! seccomp-BPF syscall filtering for pods.
//!
//! Applies an allowlist of ~130 safe syscalls. Any syscall not on the list
//! returns EPERM (not SIGKILL) so failures are debuggable rather than fatal.
//!
//! The filter is applied as the LAST step in the pre_exec hook, after all
//! namespace/mount/pivot_root setup is complete.
//!
//! Profiles:
//! - `Default` — general-purpose (~130 syscalls, suitable for shells/compilers/CLI tools)
//! - `Browser` — extends Default with 7 extra syscalls needed by Chromium's zygote

use std::collections::BTreeMap;
use std::io;

use seccompiler::{apply_filter, BpfProgram, SeccompAction, SeccompFilter, TargetArch};

/// Seccomp profile controlling which syscalls are allowed inside a pod.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum SeccompProfile {
    /// General-purpose: ~130 syscalls for shells, compilers, interpreters, CLI tools.
    #[default]
    Default,
    /// Extends Default with syscalls required by headless Chromium (zygote, scheduler, I/O priority).
    Browser,
}

/// Extra syscalls needed by Chromium beyond the default allowlist.
///
/// Chromium's zygote process installs its own seccomp-BPF policy, probes process
/// personality, manages scheduler/IO priorities, drops capabilities, creates
/// namespace sandboxes for renderer processes, and uses POSIX timers.
const BROWSER_EXTRA_SYSCALLS: &[libc::c_long] = &[
    libc::SYS_seccomp,            // Chromium zygote installs its own BPF
    libc::SYS_personality,        // Chromium probes READ_IMPLIES_EXEC
    libc::SYS_ioprio_get,         // disk cache I/O priority
    libc::SYS_ioprio_set,
    // ── Namespace sandbox (Chromium sandboxes renderer/GPU processes) ──
    libc::SYS_unshare,
    libc::SYS_chroot,             // Chromium sandbox uses chroot for isolation
    libc::SYS_ptrace,             // Chromium crash reporter / sandbox setup
    // ── POSIX timers (timeout command, Chromium internal timers) ──
    libc::SYS_timer_create,
    libc::SYS_timer_settime,
    libc::SYS_timer_delete,
    libc::SYS_timer_gettime,
    libc::SYS_timer_getoverrun,
    // ── Old inotify API (some Chromium code paths use this) ──
    libc::SYS_inotify_init,
];

/// Syscalls allowed inside a pod.
///
/// This is deliberately generous for an MVP — enough to run shells, compilers,
/// interpreters, and common CLI tools. Future versions will support per-pod
/// custom profiles via pod.yaml.
const ALLOWED_SYSCALLS: &[libc::c_long] = &[
    // ── File I/O ──
    libc::SYS_read,
    libc::SYS_write,
    libc::SYS_open,
    libc::SYS_openat,
    libc::SYS_close,
    libc::SYS_stat,
    libc::SYS_fstat,
    libc::SYS_lstat,
    libc::SYS_newfstatat,
    libc::SYS_lseek,
    libc::SYS_pread64,
    libc::SYS_pwrite64,
    libc::SYS_readv,
    libc::SYS_writev,
    libc::SYS_access,
    libc::SYS_faccessat,
    libc::SYS_faccessat2,
    libc::SYS_dup,
    libc::SYS_dup2,
    libc::SYS_dup3,
    libc::SYS_fcntl,
    libc::SYS_flock,
    libc::SYS_fsync,
    libc::SYS_fdatasync,
    libc::SYS_ftruncate,
    libc::SYS_truncate,
    libc::SYS_getdents64,
    libc::SYS_getcwd,
    libc::SYS_chdir,
    libc::SYS_fchdir,
    libc::SYS_rename,
    libc::SYS_renameat,
    libc::SYS_renameat2,
    libc::SYS_mkdir,
    libc::SYS_mkdirat,
    libc::SYS_rmdir,
    libc::SYS_link,
    libc::SYS_linkat,
    libc::SYS_unlink,
    libc::SYS_unlinkat,
    libc::SYS_symlink,
    libc::SYS_symlinkat,
    libc::SYS_readlink,
    libc::SYS_readlinkat,
    libc::SYS_chmod,
    libc::SYS_fchmod,
    libc::SYS_fchmodat,
    libc::SYS_chown,
    libc::SYS_fchown,
    libc::SYS_fchownat,
    libc::SYS_lchown,
    libc::SYS_umask,
    libc::SYS_statfs,
    libc::SYS_fstatfs,
    libc::SYS_utimensat,
    libc::SYS_copy_file_range,
    libc::SYS_sendfile,
    // ── Memory management ──
    libc::SYS_mmap,
    libc::SYS_mprotect,
    libc::SYS_munmap,
    libc::SYS_brk,
    libc::SYS_mremap,
    libc::SYS_madvise,
    libc::SYS_msync,
    libc::SYS_mincore,
    libc::SYS_mlock,
    libc::SYS_mlock2,
    libc::SYS_munlock,
    // ── Process management ──
    libc::SYS_fork,
    libc::SYS_vfork,
    libc::SYS_clone,
    libc::SYS_clone3,
    libc::SYS_execve,
    libc::SYS_execveat,
    libc::SYS_exit,
    libc::SYS_exit_group,
    libc::SYS_wait4,
    libc::SYS_waitid,
    libc::SYS_getpid,
    libc::SYS_getppid,
    libc::SYS_gettid,
    libc::SYS_getuid,
    libc::SYS_geteuid,
    libc::SYS_getgid,
    libc::SYS_getegid,
    libc::SYS_getgroups,
    libc::SYS_getresuid,          // needed by apt methods to probe saved set-user-ID
    libc::SYS_getresgid,
    libc::SYS_setpgid,
    libc::SYS_getpgid,
    libc::SYS_getpgrp,
    libc::SYS_setsid,
    libc::SYS_getrlimit,
    libc::SYS_setrlimit,
    libc::SYS_prlimit64,
    libc::SYS_getrusage,
    libc::SYS_sched_yield,
    libc::SYS_sched_getaffinity,
    libc::SYS_sched_setaffinity,
    libc::SYS_sched_getparam,       // thread priority queries (node/npm libuv)
    libc::SYS_sched_getscheduler,
    libc::SYS_sched_setscheduler,
    libc::SYS_set_tid_address,
    libc::SYS_set_robust_list,
    libc::SYS_get_robust_list,
    libc::SYS_prctl,
    libc::SYS_arch_prctl,
    libc::SYS_rseq,
    libc::SYS_capget,             // needed by ping, su, sudo, and many CLI tools
    libc::SYS_capset,
    libc::SYS_setuid,             // needed by ping, apt, dpkg (safe inside user ns)
    libc::SYS_setgid,
    libc::SYS_setgroups,          // needed by apt-get update (drops supplementary groups)
    libc::SYS_setresuid,
    libc::SYS_setresgid,
    // ── Signals ──
    libc::SYS_rt_sigaction,
    libc::SYS_rt_sigprocmask,
    libc::SYS_rt_sigreturn,
    libc::SYS_rt_sigsuspend,
    libc::SYS_rt_sigpending,
    libc::SYS_rt_sigtimedwait,
    libc::SYS_kill,
    libc::SYS_tgkill,
    libc::SYS_sigaltstack,
    // ── Networking (within pod's network namespace) ──
    libc::SYS_socket,
    libc::SYS_connect,
    libc::SYS_accept,
    libc::SYS_accept4,
    libc::SYS_bind,
    libc::SYS_listen,
    libc::SYS_sendto,
    libc::SYS_recvfrom,
    libc::SYS_sendmsg,
    libc::SYS_recvmsg,
    libc::SYS_sendmmsg,
    libc::SYS_recvmmsg,
    libc::SYS_shutdown,
    libc::SYS_getsockname,
    libc::SYS_getpeername,
    libc::SYS_setsockopt,
    libc::SYS_getsockopt,
    libc::SYS_socketpair,
    // ── Polling / event / timer ──
    libc::SYS_poll,
    libc::SYS_ppoll,
    libc::SYS_select,
    libc::SYS_pselect6,
    libc::SYS_epoll_create1,
    libc::SYS_epoll_ctl,
    libc::SYS_epoll_wait,
    libc::SYS_epoll_pwait,
    libc::SYS_epoll_pwait2,
    libc::SYS_eventfd2,
    libc::SYS_timerfd_create,
    libc::SYS_timerfd_settime,
    libc::SYS_timerfd_gettime,
    // ── Pipes ──
    libc::SYS_pipe,
    libc::SYS_pipe2,
    libc::SYS_splice,
    libc::SYS_tee,
    // ── Time ──
    libc::SYS_clock_gettime,
    libc::SYS_clock_getres,
    libc::SYS_clock_nanosleep,
    libc::SYS_gettimeofday,
    libc::SYS_nanosleep,
    // ── inotify ──
    libc::SYS_inotify_init1,
    libc::SYS_inotify_add_watch,
    libc::SYS_inotify_rm_watch,
    // ── Misc (required by glibc, runtimes, etc.) ──
    libc::SYS_uname,
    libc::SYS_sysinfo,
    libc::SYS_getrandom,
    libc::SYS_futex,
    libc::SYS_ioctl,
    libc::SYS_statx,
    libc::SYS_memfd_create,
    libc::SYS_membarrier,
    libc::SYS_close_range,
];

/// Build a seccomp BPF filter for the given profile.
///
/// Default action: `Errno(EPERM)` — blocked syscalls return "operation not permitted"
/// rather than killing the process, so failures are debuggable.
pub fn build_filter(profile: SeccompProfile) -> io::Result<BpfProgram> {
    let mut rules: BTreeMap<i64, Vec<seccompiler::SeccompRule>> = BTreeMap::new();
    for &syscall in ALLOWED_SYSCALLS {
        // Empty Vec<SeccompRule> = unconditional allow for this syscall
        rules.insert(syscall, vec![]);
    }

    if profile == SeccompProfile::Browser {
        for &syscall in BROWSER_EXTRA_SYSCALLS {
            rules.insert(syscall, vec![]);
        }
    }

    let filter = SeccompFilter::new(
        rules,
        SeccompAction::Errno(libc::EPERM as u32),
        SeccompAction::Allow,
        TargetArch::x86_64,
    )
    .map_err(io::Error::other)?;

    filter.try_into().map_err(io::Error::other)
}

/// Build and install a seccomp filter for the given profile on the current thread.
///
/// Must be called AFTER all namespace/mount setup (this is the last step
/// in the pre_exec hook) because the filter restricts mount/unshare/pivot_root.
pub fn install_filter(profile: SeccompProfile) -> io::Result<()> {
    let program = build_filter(profile)?;
    apply_filter(&program).map_err(io::Error::other)
}

/// Build the default seccomp BPF filter program.
///
/// Convenience wrapper around `build_filter(SeccompProfile::Default)`.
#[allow(dead_code)]
pub fn build_default_filter() -> io::Result<BpfProgram> {
    build_filter(SeccompProfile::Default)
}

/// Build and install the default seccomp filter on the current thread.
///
/// Convenience wrapper around `install_filter(SeccompProfile::Default)`.
#[allow(dead_code)]
pub fn apply_default_filter() -> io::Result<()> {
    install_filter(SeccompProfile::Default)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filter_compiles() {
        let program = build_default_filter().expect("filter should compile");
        // BPF programs are Vec<sock_filter> — should be non-empty
        assert!(!program.is_empty(), "compiled filter should have instructions");
    }

    #[test]
    fn filter_instruction_count_is_reasonable() {
        let program = build_default_filter().expect("filter should compile");
        let count = program.len();
        // A filter with ~130 allowed syscalls should produce between 50 and 4096 instructions.
        assert!(
            (50..=4096).contains(&count),
            "filter has {count} instructions — expected 50..=4096"
        );
    }

    #[test]
    fn browser_filter_compiles() {
        let program = build_filter(SeccompProfile::Browser).expect("browser filter should compile");
        assert!(!program.is_empty(), "browser filter should have instructions");
    }

    #[test]
    fn browser_filter_is_larger_than_default() {
        let default = build_filter(SeccompProfile::Default).unwrap();
        let browser = build_filter(SeccompProfile::Browser).unwrap();
        assert!(
            browser.len() > default.len(),
            "browser filter ({} instructions) should be larger than default ({} instructions)",
            browser.len(),
            default.len()
        );
    }

    #[test]
    fn default_profile_excludes_browser_syscalls() {
        // Build the default rules and verify browser-only syscalls are absent
        let mut default_syscalls: std::collections::BTreeSet<libc::c_long> =
            ALLOWED_SYSCALLS.iter().copied().collect();
        // Default should NOT contain SYS_seccomp (a browser-only syscall)
        assert!(
            !default_syscalls.contains(&libc::SYS_seccomp),
            "default profile should not include SYS_seccomp"
        );
        assert!(
            !default_syscalls.contains(&libc::SYS_personality),
            "default profile should not include SYS_personality"
        );

        // Browser profile should include them
        for &sc in BROWSER_EXTRA_SYSCALLS {
            default_syscalls.insert(sc);
        }
        assert!(default_syscalls.contains(&libc::SYS_seccomp));
        assert!(default_syscalls.contains(&libc::SYS_personality));
    }
}
