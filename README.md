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
driver), with Nouveau as a stretch target. Every finding is triaged,
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

drm-fuzz/
├── flake.nix # Reproducible environment definition
├── flake.lock # Exact pinned versions of all Nix inputs
├── .gitignore # Excludes kernel/syzkaller trees, build output
├── scripts/
│ ├── kernel.config # This project's config additions (fragment)
│ ├── setup.sh # Clones pinned kernel, applies config
│ └── build.sh # Builds the configured kernel
├── linux/ # Reproduced by setup.sh — not tracked
└── syzkaller/ # Cloned/built separately — not tracked

The kernel source and syzkaller are intentionally excluded from version
control. Both are large, independently-versioned repositories in their own
right; tracking them directly would bloat this repository indefinitely and
create nested-repository ambiguity for no benefit. Instead, the scripts
that *reconstruct* them exactly are what's tracked — the reproducibility
guarantee lives in code, not in a committed binary artifact.

---

## Quick start

```bash
nix develop
bash scripts/setup.sh
bash scripts/build.sh
```

`setup.sh`:
1. Shallow-clones the kernel directly at tag `v7.2`.
2. Generates a baseline x86_64 config, merges KVM-guest defaults.
3. Merges this project's config fragment via the kernel's own
   `merge_config.sh`, logging every overridden value for auditability.
4. Resolves all resulting dependencies (`make olddefconfig`).
5. Prints a verification grep of every target config value.

`build.sh` compiles the result, producing
`linux/arch/x86/boot/bzImage` — the bootable image used in the QEMU phase.

### A known, non-fatal warning

The clone step prints:
warning: refs/tags/v7.2 <hash> is not a commit!

Expected: `v7.2` is an *annotated* tag, and Git's shallow-fetch path
resolves annotated tags indirectly, producing this warning even on a
fully correct checkout. Independently verified via `git describe --tags`
(returns exactly `v7.2`, no offset) and `git log -1` (shows Linus
Torvalds' own "Linux 7.2" tagging commit). Documented here so it reads as
a known artifact of the tooling, not a silent, unexplained anomaly.

---

## Operational safety

VKMS fuzzing is inherently contained — it runs entirely inside the QEMU
guest against a virtual driver, with no path to the host.

i915 is not contained the same way: it is this machine's actual, live
display driver (`lspci -k` confirms binding). Fuzzing it therefore carries
real risk to the host's active session. That phase will run from a
non-graphical TTY, or preferably on separate/headless hardware — never
interactively on the primary desktop session — so an in-progress kernel
panic cannot take down the working environment mid-campaign. This
decision is recorded here before that phase begins, not reconstructed
after an incident.

---

## Hardware baseline

- **iGPU:** Intel Raptor Lake-S, UHD Graphics 770 — `i915`, confirmed
  bound and active.
- **dGPU:** NVIDIA RTX 4080 — `nvidia`/`nvidia_drm`, proprietary, out of
  scope (see Scope).
- Hybrid graphics confirmed active (both GPUs simultaneously live) via
  `lspci | grep -iE "vga|3d|display"` and `lsmod`.

---

## Status

- [x] Reproducible Nix environment (`flake.nix` / `flake.lock`)
- [x] Kernel pinned to `v7.2`; KASAN, KCOV, DRM_VKMS, DRM_I915 configured
      and verified via automated script, not manual steps
- [x] Kernel builds successfully under this configuration
- [ ] QEMU boot + minimal rootfs
- [ ] syzkaller operational against VKMS in-VM
- [ ] Sanity validation: deliberately introduced bug caught end-to-end
      (syzkaller → KCOV → KASAN → symbolized report)
- [ ] Extend DRM syscall descriptions for VKMS coverage gaps
- [ ] Real fuzzing campaign against VKMS; triage and root-cause findings
- [ ] Pivot to i915 (real hardware; see Operational Safety)
- [ ] Stretch: Nouveau
- [ ] Responsible disclosure where applicable; final technical writeup

---

## Author background

This project is part of a portfolio oriented toward Linux graphics driver
and kernel-security engineering. Related background: MSc in Computer
Science, Cybersecurity specialization, Eötvös Loránd University (Fulbright
Open Research/Study Award), and prior static-analysis tooling work — a
Clang-Tidy checker detecting padding-byte information leakage at annotated
trust boundaries, accompanying an MSc thesis under Dr. Zoltán Porkoláb.
That project demonstrated static, compile-time analysis rigor; this one is
its dynamic-analysis counterpart — the same standard of methodology and
reproducibility, applied to fuzzing instead of static checking.
