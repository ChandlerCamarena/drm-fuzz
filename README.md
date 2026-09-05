# DRM/KMS Kernel Fuzzing

**Coverage-guided vulnerability research against the Linux kernel's Direct
Rendering Manager (DRM) subsystem**, progressing from a hardware-free
virtual driver to real GPU hardware, built on syzkaller, KASAN, and KCOV,
with a fully reproducible Nix-based environment.

---

## Summary

The DRM/KMS ioctl interface is the boundary between unprivileged userspace
and kernel-level GPU driver code. It parses attacker-influenced structures
on every mode-set, buffer allocation, and command submission — a well
established, still-productive class of kernel attack surface, and one with
a direct real-world escalation path: a memory-safety bug here is not a
crashed process, it is potential kernel-level compromise from an
unprivileged caller.

This project builds a reproducible research pipeline for finding such bugs:
an instrumented kernel (KASAN for detection, KCOV for coverage-guided
fuzzing feedback), syzkaller as the fuzzing engine, and a staged target
progression — from VKMS (a safe, in-tree virtual driver built for exactly
this kind of testing) to i915 (this machine's real Intel integrated GPU
driver), with Nouveau as a stretch target. Findings are triaged,
root-caused, and — where real — disclosed responsibly before any public
detail is published.

The environment itself is the first deliverable: `nix develop` plus two
scripts reproduce the exact toolchain, exact kernel version, and exact
kernel configuration on any machine, from a clean checkout, with no
undocumented manual steps.

---

## Why this project, and why it's structured this way

Kernel fuzzing campaigns are frequently under-documented and
non-reproducible — a `.config` file with unexplained flags, a kernel
version nobody recorded, a toolchain nobody pinned. That's a real problem
for a research artifact meant to be reviewed, extended, or trusted: an
unreproducible result is a claim, not evidence.

Every design decision here optimizes for the opposite: **anyone should be
able to arrive at the identical environment this research was conducted
in, from a clean machine, using only what's committed to this repository.**
That standard shapes the toolchain choices below as much as the fuzzing
methodology itself.

---

## Toolchain

| Component | Purpose | Why it's here |
|---|---|---|
| **Nix (flakes)** | Pins the entire build toolchain — compiler, QEMU, Go, kernel build dependencies — to exact versions via `flake.nix` / `flake.lock`. | Removes "works on my machine" ambiguity entirely; the dev shell is byte-for-byte reproducible, not just documented. |
| **Linux kernel, pinned to `v7.2`** | The fuzzing target. | A named, citable release rather than a moving `HEAD` — essential for any finding to be reproducible against a known baseline. |
| **KASAN** (generic, inline) | Converts silent memory-safety violations — out-of-bounds access, use-after-free — into immediate, symbolized kernel panics. | Without this, a fuzzer can trigger a real bug and observe nothing; KASAN is what makes a bug *detectable* at all, not just triggerable. Inline mode trades build time for faster execution, the right tradeoff for long-running campaigns. |
| **KCOV** (`INSTRUMENT_ALL`) | Per-syscall code-coverage tracking, consumed by syzkaller as its exploration signal. | This is what makes the fuzzing *coverage-guided* rather than blind — inputs that reach new code get prioritized for further mutation, which is the entire reason coverage-guided fuzzing outperforms random fuzzing in practice. |
| **DEBUG_INFO / DWARF4** | Embeds source-line debug information in the build. | Turns a KASAN crash report from a bare, useless address into a file, line, and function — the difference between a finding you can root-cause and one you can't. |
| **syzkaller** | The fuzzing engine (Google). Generates structured syscall inputs, mutates them under KCOV feedback, detects and triages crashes. | Purpose-built, actively maintained, the standard tool for exactly this class of research. |
| **QEMU** | Runs the instrumented kernel in isolation. | Fuzzing-induced kernel panics and memory corruption stay contained to the VM — never the host. |
| **DRM_VKMS** (module) | Virtual, hardware-free DRM driver; upstream's own purpose-built testing target. | Validates the entire pipeline — kernel, KASAN, KCOV, syzkaller, syscall descriptions — with zero hardware risk before any real driver is touched. |
| **DRM_I915** (module) | Intel integrated graphics driver. | Confirmed as this machine's actual bound display driver (`lspci -k` → `Kernel driver in use: i915`, Raptor Lake UHD Graphics 770) — the real-hardware phase of this research. |

---

## Scope

**In scope:** VKMS (primary target, validates methodology), i915 (real
hardware, primary research target), Nouveau (stretch — architecturally
distinct target on the machine's RTX 4080).

**Explicitly out of scope:** NVIDIA's proprietary driver. It is closed
source — there is no way to root-cause a crash against it, no way to build
it into an instrumented in-tree kernel the way KASAN/KCOV require, and its
disclosure process is opaque relative to upstream kernel maintainers.
Nouveau is the deliberate, open-source substitute for this hardware.

Documenting what's excluded, and why, is treated as part of the
methodology — a scope boundary stated up front is a design decision, not
an oversight discovered later.

---

## Repository layout
